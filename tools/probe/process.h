#pragma once
// Read-only access to another process (the game) via ReadProcessMemory.
// Nothing here can write to the target.

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "common/pattern.h"

namespace probe {
class Process {
public:
    ~Process();

    bool attach_by_name(const std::wstring& exe_name);
    bool attach_by_pid(uint32_t pid);

    // Offline mode: read the exe straight off disk, with no process at all.
    //
    // Everything that only needs the image -- info, scan, rip, classes, vtables,
    // dump, findptr -- works this way, which is what makes the port checkable
    // without the game running. It cannot answer questions about live state
    // (pointer chains, RTTI of a live object), and say so rather than guessing.
    bool open_image_file(const std::wstring& path);
    bool is_file_mode() const { return file_bytes_ != nullptr; }

    uint32_t pid() const { return pid_; }
    uint64_t module_base() const { return base_; }
    uint64_t module_size() const { return size_; }
    const std::wstring& module_path() const { return path_; }
    bool in_module(uint64_t addr) const { return addr >= base_ && addr < base_ + size_; }

    bool read(uint64_t addr, void* out, size_t size) const;
    template <class T>
    std::optional<T> read(uint64_t addr) const {
        T v{};
        if (!read(addr, &v, sizeof v)) return std::nullopt;
        return v;
    }
    std::string read_cstring(uint64_t addr, size_t max_len = 256) const;

    // Is this a plausible user-mode pointer to committed readable memory?
    bool is_readable(uint64_t addr) const;

    enum class Scope {
        Module,  // the exe image (code + static data)
        Heap,    // committed writable memory outside any image
    };

    // Scans readable memory in `scope`. Returns sorted absolute addresses.
    std::vector<uint64_t> scan(const cdmp::Pattern& pattern, size_t max_matches,
                               Scope scope = Scope::Module) const;

    // MSVC RTTI class name of the object at `obj` (".?AVName@ns@@"), via
    // vtable[-1] -> CompleteObjectLocator -> TypeDescriptor. Empty if none.
    std::string rtti_name(uint64_t obj) const;

    // "exe+0x1234" when inside the main module, else "0x7FF...".
    std::string describe(uint64_t addr) const;

private:
    bool load_main_module();
    // File mode: translate an image RVA to an offset in the mapped file. In a PE
    // on disk a section's raw data starts at PointerToRawData, not at its virtual
    // address, so a straight read at the RVA would land in the wrong place (or in
    // the header). Returns nullopt for RVAs that are not backed by file data --
    // e.g. .bss, which exists only once the loader maps the image.
    std::optional<uint64_t> rva_to_offset(uint64_t rva) const;

    void* handle_ = nullptr;
    uint32_t pid_ = 0;
    uint64_t base_ = 0;
    uint64_t size_ = 0;
    std::wstring path_;

    // File mode state. base_ is the image base from the PE header (the probe
    // reports addresses as base_ + rva, exactly as in process mode). The handles
    // are void* so this header does not have to pull in windows.h.
    void* file_ = nullptr;
    void* mapping_ = nullptr;
    const uint8_t* file_bytes_ = nullptr;
    uint64_t file_size_ = 0;
    uint64_t size_of_headers_ = 0;
    struct Section {
        uint64_t va;
        uint64_t vsize;
        uint64_t raw;
        uint64_t rsize;
    };
    std::vector<Section> sections_;
};

}  // namespace probe
