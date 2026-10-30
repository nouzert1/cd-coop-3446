#include "probe/process.h"

#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cstring>
#include <cwchar>
#include <format>

namespace probe {

Process::~Process() {
    if (handle_) CloseHandle(handle_);
    if (file_bytes_) UnmapViewOfFile(file_bytes_);
    if (mapping_) CloseHandle(mapping_);
    if (file_) CloseHandle(static_cast<HANDLE>(file_));
}

// ------------------------------------------------------------------ file mode

bool Process::open_image_file(const std::wstring& path) {
    HANDLE f = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    file_ = f;
    LARGE_INTEGER sz{};
    if (!GetFileSizeEx(f, &sz) || sz.QuadPart <= 0) return false;
    file_size_ = static_cast<uint64_t>(sz.QuadPart);

    HANDLE m = CreateFileMappingW(f, nullptr, PAGE_READONLY, 0, 0, nullptr);
    if (!m) return false;
    mapping_ = m;
    file_bytes_ = static_cast<const uint8_t*>(MapViewOfFile(m, FILE_MAP_READ, 0, 0, 0));
    if (!file_bytes_) return false;

    // Parse just enough PE to translate RVAs. Read from a copy so the parsing
    // helpers below can use the same bounds-checked path.
    if (file_size_ < 0x40) return false;
    uint32_t lfanew = 0;
    std::memcpy(&lfanew, file_bytes_ + 0x3C, sizeof lfanew);
    if (static_cast<uint64_t>(lfanew) + 0x18 > file_size_) return false;

    uint16_t magic = 0, nsec = 0;
    uint32_t size_of_image = 0, size_of_headers = 0;
    uint64_t image_base = 0;
    std::memcpy(&magic, file_bytes_ + lfanew + 0x18, sizeof magic);
    std::memcpy(&nsec, file_bytes_ + lfanew + 0x06, sizeof nsec);
    std::memcpy(&size_of_headers, file_bytes_ + lfanew + 0x18 + 0x3C, sizeof size_of_headers);
    std::memcpy(&size_of_image, file_bytes_ + lfanew + 0x18 + 0x38, sizeof size_of_image);
    // PE32+ has the ImageBase at +0x18 of the optional header; x64 only here.
    if (magic != 0x20B) return false;
    std::memcpy(&image_base, file_bytes_ + lfanew + 0x18 + 0x18, sizeof image_base);

    base_ = image_base;
    size_ = size_of_image;
    size_of_headers_ = size_of_headers;
    path_ = path;

    const uint64_t sec_tab = static_cast<uint64_t>(lfanew) + 0x18 + 0x0F0;
    for (uint16_t i = 0; i < nsec; ++i) {
        const uint64_t o = sec_tab + static_cast<uint64_t>(i) * 40;
        if (o + 40 > file_size_) break;
        uint32_t vsize = 0, va = 0, rsize = 0, raw = 0;
        std::memcpy(&vsize, file_bytes_ + o + 0x08, sizeof vsize);
        std::memcpy(&va, file_bytes_ + o + 0x0C, sizeof va);
        std::memcpy(&rsize, file_bytes_ + o + 0x10, sizeof rsize);
        std::memcpy(&raw, file_bytes_ + o + 0x14, sizeof raw);
        sections_.push_back({va, vsize, raw, rsize});
    }
    return !sections_.empty();
}

std::optional<uint64_t> Process::rva_to_offset(uint64_t rva) const {
    if (rva < size_of_headers_) return rva;  // the headers are at offset 0
    for (const Section& s : sections_) {
        if (rva >= s.va && rva < s.va + s.vsize) {
            const uint64_t within = rva - s.va;
            // Past the raw size the bytes are zero-fill (.bss) and do not exist
            // in the file: report that rather than reading whatever follows.
            if (within >= s.rsize) return std::nullopt;
            const uint64_t off = s.raw + within;
            return off < file_size_ ? std::optional<uint64_t>(off) : std::nullopt;
        }
    }
    return std::nullopt;
}

// ------------------------------------------------------------------ attaching

bool Process::attach_by_name(const std::wstring& exe_name) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return false;
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof entry;
    uint32_t found = 0;
    for (BOOL ok = Process32FirstW(snap, &entry); ok; ok = Process32NextW(snap, &entry)) {
        if (_wcsicmp(entry.szExeFile, exe_name.c_str()) == 0) {
            found = entry.th32ProcessID;
            break;
        }
    }
    CloseHandle(snap);
    return found != 0 && attach_by_pid(found);
}

bool Process::attach_by_pid(uint32_t pid) {
    // Read + query only: the probe must never be able to modify the game.
    handle_ = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (!handle_) return false;
    pid_ = pid;
    return load_main_module();
}

bool Process::load_main_module() {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid_);
    if (snap == INVALID_HANDLE_VALUE) return false;
    MODULEENTRY32W mod{};
    mod.dwSize = sizeof mod;
    const bool ok = Module32FirstW(snap, &mod) != FALSE;  // first entry is the exe
    CloseHandle(snap);
    if (!ok) return false;
    base_ = reinterpret_cast<uint64_t>(mod.modBaseAddr);
    size_ = mod.modBaseSize;
    path_ = mod.szExePath;
    return true;
}

bool Process::read(uint64_t addr, void* out, size_t size) const {
    if (file_bytes_) {
        if (!in_module(addr)) return false;
        const auto off = rva_to_offset(addr - base_);
        if (!off || *off + size > file_size_) return false;
        std::memcpy(out, file_bytes_ + *off, size);
        return true;
    }
    SIZE_T got = 0;
    return ReadProcessMemory(handle_, reinterpret_cast<LPCVOID>(addr), out, size, &got) &&
           got == size;
}

std::string Process::read_cstring(uint64_t addr, size_t max_len) const {
    std::string s;
    char buf[64];
    while (s.size() < max_len) {
        if (!read(addr + s.size(), buf, sizeof buf)) break;
        for (char c : buf) {
            if (c == '\0' || s.size() >= max_len) return s;
            s.push_back(c);
        }
    }
    return s;
}

bool Process::is_readable(uint64_t addr) const {
    if (addr < 0x10000 || addr > 0x00007FFFFFFFFFFFull) return false;
    if (file_bytes_) {
        if (!in_module(addr)) return false;
        return rva_to_offset(addr - base_).has_value();
    }
    MEMORY_BASIC_INFORMATION mbi{};
    if (!VirtualQueryEx(handle_, reinterpret_cast<LPCVOID>(addr), &mbi, sizeof mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;
    return true;
}

std::vector<uint64_t> Process::scan(const cdmp::Pattern& pattern, size_t max_matches,
                                    Scope scope) const {
    std::vector<uint64_t> result;
    std::vector<size_t> offsets;
    std::vector<uint8_t> buf;
    constexpr size_t kChunk = 16 * 1024 * 1024;
    const size_t overlap = pattern.size() - 1;
    constexpr DWORD kWritable =
        PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;

    // File mode: walk the sections, and scan mapped file bytes directly. A
    // pattern cannot match across a section boundary in the file (the loader maps
    // each section separately anyway), so per-section scanning is correct, and
    // .bss -- which has no file bytes -- is skipped rather than read as zeros.
    if (file_bytes_) {
        if (scope == Scope::Heap) return result;  // no heap without a process
        for (const Section& s : sections_) {
            if (result.size() >= max_matches) break;
            // Whole-section scan including headers-copied data: raw size only.
            for (uint64_t within = 0; within < s.rsize;) {
                const uint64_t take = std::min<uint64_t>(kChunk, s.rsize - within);
                const uint8_t* p = file_bytes_ + s.raw + within;
                if (s.raw + within + take > file_size_) break;
                offsets.clear();
                cdmp::find_pattern({p, static_cast<size_t>(take)}, pattern, offsets,
                                   max_matches - result.size());
                for (size_t off : offsets) {
                    result.push_back(base_ + s.va + within + off);
                }
                if (take <= overlap) break;
                within += take - overlap;
            }
        }
        std::sort(result.begin(), result.end());
        result.erase(std::unique(result.begin(), result.end()), result.end());
        if (result.size() > max_matches) result.resize(max_matches);
        return result;
    }

    uint64_t addr = scope == Scope::Module ? base_ : 0x10000;
    const uint64_t end = scope == Scope::Module ? base_ + size_ : 0x00007FFFFFFF0000ull;
    while (addr < end && result.size() < max_matches) {
        MEMORY_BASIC_INFORMATION mbi{};
        if (!VirtualQueryEx(handle_, reinterpret_cast<LPCVOID>(addr), &mbi, sizeof mbi)) break;
        const uint64_t region_start = reinterpret_cast<uint64_t>(mbi.BaseAddress);
        const uint64_t region_end = std::min<uint64_t>(region_start + mbi.RegionSize, end);
        bool readable = mbi.State == MEM_COMMIT && !(mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD));
        if (scope == Scope::Heap) {
            readable = readable && mbi.Type != MEM_IMAGE && (mbi.Protect & kWritable);
        }

        if (readable) {
            for (uint64_t pos = std::max(addr, region_start); pos < region_end;) {
                const size_t want = static_cast<size_t>(std::min<uint64_t>(kChunk, region_end - pos));
                buf.resize(want);
                SIZE_T got = 0;
                ReadProcessMemory(handle_, reinterpret_cast<LPCVOID>(pos), buf.data(), want, &got);
                if (got == 0) break;
                offsets.clear();
                cdmp::find_pattern({buf.data(), got}, pattern, offsets,
                                   max_matches - result.size());
                for (size_t off : offsets) result.push_back(pos + off);
                if (result.size() >= max_matches || got <= overlap) break;
                // Step back by the pattern length so matches spanning two
                // chunks are not missed (and not reported twice).
                pos += got - overlap;
                if (got < want) break;
            }
        }
        addr = region_end;
    }
    std::sort(result.begin(), result.end());
    result.erase(std::unique(result.begin(), result.end()), result.end());
    return result;
}

std::string Process::rtti_name(uint64_t obj) const {
    auto vtable = read<uint64_t>(obj);
    if (!vtable || !in_module(*vtable)) return {};
    auto col = read<uint64_t>(*vtable - 8);
    if (!col || !in_module(*col)) return {};
    // x64 CompleteObjectLocator: signature 1, then RVA of TypeDescriptor at +0x0C.
    auto signature = read<uint32_t>(*col);
    auto td_rva = read<uint32_t>(*col + 0x0C);
    if (!signature || *signature != 1 || !td_rva) return {};
    std::string name = read_cstring(base_ + *td_rva + 0x10, 200);
    return name.starts_with(".?A") ? name : std::string{};
}

std::string Process::describe(uint64_t addr) const {
    if (in_module(addr)) return std::format("exe+0x{:X}", addr - base_);
    return std::format("0x{:X}", addr);
}

}  // namespace probe
