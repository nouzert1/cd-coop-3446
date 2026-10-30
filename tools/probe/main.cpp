// cdmp_probe.exe - read-only external memory inspector for Crimson Desert.
// Attaches with PROCESS_VM_READ only, so it cannot crash or modify the game.
// Used to verify signatures and pointer chains before the mod relies on them.
//
// Addresses: "exe+1A2B" (RVA in the game exe), "0x14001A2B" or "14001A2B".
// Offsets and addresses are hex; --max/--count/--size/--seconds are decimal
// unless written with 0x.

#include <windows.h>

#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <format>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#ifdef CDMP_PROBE_HAVE_ZYDIS
#include <Zydis/Zydis.h>
#endif

#include "common/pattern.h"
#include "probe/process.h"

using probe::Process;

namespace {

constexpr uint32_t kKnownTimestamp = 0x6AE387F2;  // CrimsonDesert.exe 1.0.0.3424

void usage() {
    std::puts(
        "cdmp_probe [--process NAME | --pid N | --image FILE] <command> ...\n"
        "\n"
        "  --image FILE   read the exe off disk, no process needed. Works for\n"
        "                 anything that only needs the image (info, scan, rip,\n"
        "                 classes, vtables, dump, findptr). Live queries -- chain,\n"
        "                 watch, rtti, --heap -- cannot work this way and say so.\n"
        "\n"
        "  info                                 process, module, build check\n"
        "  scan <aob> [--max N] [--heap]        find a byte pattern (exe image or heap)\n"
        "  sigs <file>... [--max N]             batch-scan 'name | aob | desc | src' lines\n"
        "                                       (in .md files only ```sigs blocks are read)\n"
        "  rip <addr> [--disp 3] [--len 7]      resolve a RIP-relative operand\n"
        "  read <addr> [--type T] [--count N]   T: u8 u16 u32 u64 i32 i64 f32 f64 ptr\n"
        "                                          vec3 vec4 str (default ptr)\n"
        "  chain <addr> [off ...] [--type T]    Cheat Engine style [[addr]+off]+off...\n"
        "  watch <addr> [off ...] [--type T] [--interval MS] [--seconds N]\n"
        "  dump <addr> [--size N]               qword view with floats, pointers, RTTI\n"
        "  disasm <addr> [--count N]            decode instructions, resolving RIP targets\n"
        "  rtti <addr>                          class name of the object at addr\n"
        "  classes <text> [--max N]             RTTI class names containing text\n"
        "  vtables <.?AVName@@>                 vtable address(es) of an RTTI class\n"
        "  findptr <value> [--max N] [--heap]   where is this qword stored?\n");
}

// ---------------------------------------------------------------- arguments

struct Args {
    std::vector<std::string> pos;
    std::map<std::string, std::string> opt;  // "--x" -> value ("" for flags)

    bool flag(const std::string& k) const { return opt.contains(k); }
    std::string get(const std::string& k, const std::string& def) const {
        auto it = opt.find(k);
        return it == opt.end() ? def : it->second;
    }
};

const char* kFlags[] = {"--heap"};

Args parse_args(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; ++i) {
        std::string s = argv[i];
        if (s.starts_with("--")) {
            bool is_flag = false;
            for (const char* f : kFlags) is_flag |= s == f;
            if (!is_flag && i + 1 < argc) {
                a.opt[s] = argv[++i];
            } else {
                a.opt[s] = "";
            }
        } else {
            a.pos.push_back(s);
        }
    }
    return a;
}

std::optional<int64_t> parse_hex(std::string s) {
    bool neg = false;
    if (s.starts_with("-")) {
        neg = true;
        s = s.substr(1);
    } else if (s.starts_with("+")) {
        s = s.substr(1);
    }
    if (s.starts_with("0x") || s.starts_with("0X")) s = s.substr(2);
    if (s.empty()) return std::nullopt;
    try {
        size_t used = 0;
        const uint64_t v = std::stoull(s, &used, 16);
        if (used != s.size()) return std::nullopt;
        return neg ? -static_cast<int64_t>(v) : static_cast<int64_t>(v);
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<uint64_t> parse_addr(const Process& p, const std::string& s) {
    std::string lower = s;
    for (char& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (lower.starts_with("exe+")) {
        auto rva = parse_hex(s.substr(4));
        if (!rva) return std::nullopt;
        return p.module_base() + static_cast<uint64_t>(*rva);
    }
    auto v = parse_hex(s);
    if (!v) return std::nullopt;
    return static_cast<uint64_t>(*v);
}

size_t parse_count(const std::string& s, size_t def) {
    try {
        return static_cast<size_t>(std::stoull(s, nullptr, 0));
    } catch (...) {
        return def;
    }
}

// ---------------------------------------------------------------- values

std::string format_value(const Process& p, uint64_t addr, const std::string& type) {
    auto rd = [&](auto tag) { return p.read<decltype(tag)>(addr); };
    const std::string bad = "<unreadable>";
    if (type == "u8") { auto v = rd(uint8_t{}); return v ? std::format("{} (0x{:X})", *v, *v) : bad; }
    if (type == "u16") { auto v = rd(uint16_t{}); return v ? std::format("{} (0x{:X})", *v, *v) : bad; }
    if (type == "u32") { auto v = rd(uint32_t{}); return v ? std::format("{} (0x{:X})", *v, *v) : bad; }
    if (type == "u64") { auto v = rd(uint64_t{}); return v ? std::format("{} (0x{:X})", *v, *v) : bad; }
    if (type == "i32") { auto v = rd(int32_t{}); return v ? std::format("{}", *v) : bad; }
    if (type == "i64") { auto v = rd(int64_t{}); return v ? std::format("{}", *v) : bad; }
    if (type == "f32") { auto v = rd(float{}); return v ? std::format("{:.4f}", *v) : bad; }
    if (type == "f64") { auto v = rd(double{}); return v ? std::format("{:.4f}", *v) : bad; }
    if (type == "vec3" || type == "vec4") {
        float f[4] = {};
        const size_t n = type == "vec3" ? 3 : 4;
        if (!p.read(addr, f, n * sizeof(float))) return bad;
        std::string s = "(";
        for (size_t i = 0; i < n; ++i) s += std::format("{}{:.3f}", i ? ", " : "", f[i]);
        return s + ")";
    }
    if (type == "str") return "\"" + p.read_cstring(addr, 128) + "\"";
    // ptr (default)
    auto v = rd(uint64_t{});
    if (!v) return bad;
    std::string s = p.describe(*v);
    if (p.is_readable(*v)) {
        const std::string cls = p.rtti_name(*v);
        if (!cls.empty()) s += "  -> object " + cls;
    }
    return s;
}

size_t type_size(const std::string& type) {
    if (type == "u8") return 1;
    if (type == "u16") return 2;
    if (type == "u32" || type == "i32" || type == "f32") return 4;
    if (type == "vec3") return 12;
    if (type == "vec4") return 16;
    return 8;
}

// Follows [[addr]+o1]+o2...; prints each hop when verbose. nullopt if a hop
// lands on unreadable memory.
std::optional<uint64_t> follow_chain(const Process& p, uint64_t addr,
                                     const std::vector<int64_t>& offs, bool verbose) {
    for (int64_t off : offs) {
        auto next = p.read<uint64_t>(addr);
        if (!next) {
            if (verbose) std::printf("  [%s] unreadable\n", p.describe(addr).c_str());
            return std::nullopt;
        }
        const uint64_t target = *next + static_cast<uint64_t>(off);
        if (verbose) {
            const std::string cls = p.rtti_name(*next);
            std::printf("  [%s] = %s%s  %+lld -> %s\n", p.describe(addr).c_str(),
                        p.describe(*next).c_str(), cls.empty() ? "" : ("  (" + cls + ")").c_str(),
                        static_cast<long long>(off), p.describe(target).c_str());
        }
        addr = target;
    }
    return addr;
}

// ---------------------------------------------------------------- sigs files

struct Sig {
    std::string name, aob, desc, source, file;
};

std::string trim(const std::string& s) {
    const size_t b = s.find_first_not_of(" \t\r");
    if (b == std::string::npos) return {};
    const size_t e = s.find_last_not_of(" \t\r");
    return s.substr(b, e - b + 1);
}

std::vector<Sig> load_sigs(const std::string& path) {
    std::ifstream in(path);
    std::vector<std::string> lines;
    for (std::string line; std::getline(in, line);) lines.push_back(line);

    bool has_blocks = false;
    for (auto& l : lines) has_blocks |= trim(l).starts_with("```sigs");

    std::vector<Sig> sigs;
    bool inside = !has_blocks;
    for (auto& raw : lines) {
        const std::string l = trim(raw);
        if (has_blocks) {
            if (l.starts_with("```sigs")) { inside = true; continue; }
            if (l.starts_with("```")) { inside = false; continue; }
        }
        if (!inside || l.empty() || l.starts_with("#") || l.starts_with(";")) continue;

        std::vector<std::string> parts;
        std::stringstream ss(l);
        for (std::string part; std::getline(ss, part, '|');) parts.push_back(trim(part));
        if (parts.size() < 2) continue;
        sigs.push_back({parts[0], parts[1], parts.size() > 2 ? parts[2] : "",
                        parts.size() > 3 ? parts[3] : "", path});
    }
    return sigs;
}

// ---------------------------------------------------------------- commands

int cmd_info(const Process& p) {
    std::printf("PID      %u\n", p.pid());
    std::wprintf(L"Module   %s\n", p.module_path().c_str());
    std::printf("Base     0x%llX  size 0x%llX\n", static_cast<unsigned long long>(p.module_base()),
                static_cast<unsigned long long>(p.module_size()));
    auto e_lfanew = p.read<int32_t>(p.module_base() + 0x3C);
    auto ts = e_lfanew ? p.read<uint32_t>(p.module_base() + *e_lfanew + 8) : std::nullopt;
    if (ts) {
        std::printf("PE timestamp 0x%08X %s\n", *ts,
                    *ts == kKnownTimestamp ? "(known build 1.0.0.3424)"
                                           : "(UNKNOWN BUILD - offsets/sigs may be invalid)");
    }
    return 0;
}

int cmd_scan(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    auto pat = cdmp::parse_pattern(a.pos[1]);
    if (!pat) return std::puts("Bad pattern"), 2;
    const size_t max = parse_count(a.get("--max", "20"), 20);
    const auto scope = a.flag("--heap") ? Process::Scope::Heap : Process::Scope::Module;
    const auto hits = p.scan(*pat, max, scope);
    std::printf("%zu match(es)%s\n", hits.size(), hits.size() >= max ? " (limit reached)" : "");
    for (uint64_t h : hits) std::printf("  %s\n", p.describe(h).c_str());
    return 0;
}

int cmd_sigs(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    const size_t max = parse_count(a.get("--max", "4"), 4);
    int unique = 0, total = 0;
    for (size_t i = 1; i < a.pos.size(); ++i) {
        for (const Sig& s : load_sigs(a.pos[i])) {
            ++total;
            auto pat = cdmp::parse_pattern(s.aob);
            if (!pat) {
                std::printf("%-36s BAD PATTERN\n", s.name.c_str());
                continue;
            }
            const auto hits = p.scan(*pat, max);
            std::string where;
            for (uint64_t h : hits) where += " " + p.describe(h);
            const std::string count =
                hits.size() >= max ? std::format("{}+", max) : std::to_string(hits.size());
            unique += hits.size() == 1;
            std::printf("%-36s %3s %s%s\n", s.name.c_str(), count.c_str(),
                        hits.size() == 1 ? "OK  " : (hits.empty() ? "MISS" : "MULT"), where.c_str());
        }
    }
    std::printf("\n%d/%d signatures matched exactly once\n", unique, total);
    return 0;
}

int cmd_rip(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    auto addr = parse_addr(p, a.pos[1]);
    if (!addr) return std::puts("Bad address"), 2;
    const auto disp_at = parse_count(a.get("--disp", "3"), 3);
    const auto len = parse_count(a.get("--len", "7"), 7);
    auto disp = p.read<int32_t>(*addr + disp_at);
    if (!disp) return std::puts("Unreadable"), 1;
    const uint64_t target = *addr + len + static_cast<int64_t>(*disp);
    std::printf("target %s  value %s\n", p.describe(target).c_str(),
                format_value(p, target, "ptr").c_str());
    return 0;
}

int cmd_read(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    auto addr = parse_addr(p, a.pos[1]);
    if (!addr) return std::puts("Bad address"), 2;
    const std::string type = a.get("--type", "ptr");
    const size_t count = parse_count(a.get("--count", "1"), 1);
    for (size_t i = 0; i < count; ++i) {
        const uint64_t at = *addr + i * type_size(type);
        std::printf("%s: %s\n", p.describe(at).c_str(), format_value(p, at, type).c_str());
    }
    return 0;
}

std::optional<std::vector<int64_t>> parse_offsets(const Args& a, size_t from) {
    std::vector<int64_t> offs;
    for (size_t i = from; i < a.pos.size(); ++i) {
        auto o = parse_hex(a.pos[i]);
        if (!o) return std::nullopt;
        offs.push_back(*o);
    }
    return offs;
}

int cmd_chain(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    auto addr = parse_addr(p, a.pos[1]);
    auto offs = parse_offsets(a, 2);
    if (!addr || !offs) return std::puts("Bad address/offset"), 2;
    auto final_addr = follow_chain(p, *addr, *offs, true);
    if (!final_addr) return 1;
    const std::string type = a.get("--type", "ptr");
    std::printf("=> %s : %s\n", p.describe(*final_addr).c_str(),
                format_value(p, *final_addr, type).c_str());
    return 0;
}

volatile bool g_running = true;
BOOL WINAPI on_ctrl(DWORD) {
    g_running = false;
    return TRUE;
}

int cmd_watch(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    auto addr = parse_addr(p, a.pos[1]);
    auto offs = parse_offsets(a, 2);
    if (!addr || !offs) return std::puts("Bad address/offset"), 2;
    const std::string type = a.get("--type", "vec3");
    const DWORD interval = static_cast<DWORD>(parse_count(a.get("--interval", "250"), 250));
    const size_t seconds = parse_count(a.get("--seconds", "30"), 30);
    SetConsoleCtrlHandler(on_ctrl, TRUE);

    std::string last;
    const ULONGLONG until = GetTickCount64() + seconds * 1000;
    while (g_running && GetTickCount64() < until) {
        // Re-resolve every tick: pointers change across loading screens.
        auto at = follow_chain(p, *addr, *offs, false);
        std::string now = at ? format_value(p, *at, type) : "<chain broken>";
        if (now != last) {
            SYSTEMTIME t;
            GetLocalTime(&t);
            std::printf("[%02d:%02d:%02d.%03d] %s\n", t.wHour, t.wMinute, t.wSecond,
                        t.wMilliseconds, now.c_str());
            std::fflush(stdout);
            last = now;
        }
        Sleep(interval);
    }
    return 0;
}

int cmd_dump(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    auto addr = parse_addr(p, a.pos[1]);
    if (!addr) return std::puts("Bad address"), 2;
    const size_t size = parse_count(a.get("--size", "0x100"), 0x100);
    const std::string cls = p.rtti_name(*addr);
    if (!cls.empty()) std::printf("object %s\n", cls.c_str());
    for (size_t off = 0; off < size; off += 8) {
        uint64_t q = 0;
        if (!p.read(*addr + off, &q, 8)) {
            std::printf("+%04zX  <unreadable>\n", off);
            continue;
        }
        float f[2];
        std::memcpy(f, &q, 8);
        std::string note;
        if (p.in_module(q)) {
            note = p.describe(q);
        } else if (p.is_readable(q)) {
            const std::string c = p.rtti_name(q);
            note = "ptr" + (c.empty() ? std::string{} : " -> " + c);
        }
        auto fmt_f = [](float v) {
            return (std::isfinite(v) && std::fabs(v) < 1e7f && (v == 0 || std::fabs(v) > 1e-4f))
                       ? std::format("{:12.4f}", v)
                       : std::string(12, ' ');
        };
        std::printf("+%04zX  %016llX  %s %s  %s\n", off, static_cast<unsigned long long>(q),
                    fmt_f(f[0]).c_str(), fmt_f(f[1]).c_str(), note.c_str());
    }
    return 0;
}

// Decode instructions starting at an address. This is how a code address gets
// IDENTIFIED rather than guessed: a byte pattern says "some function looks like
// this", whereas reading the body says which global it touches and what it does.
// RIP-relative operands are resolved inline, so a `cmp byte [rip+d],0` shows the
// absolute address it tests -- exactly the link needed to tie a code site to a
// data slot.
int cmd_disasm(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    auto addr = parse_addr(p, a.pos[1]);
    if (!addr) return std::puts("Bad address"), 2;
#ifndef CDMP_PROBE_HAVE_ZYDIS
    std::puts("Built without Zydis; disassembly unavailable.");
    return 2;
#else
    const size_t count = parse_count(a.get("--count", "40"), 40);
    const uint64_t start = *addr;
    // Read a window big enough for the instruction count.
    std::vector<uint8_t> code(count * 16 + 16);
    if (!p.read(start, code.data(), code.size())) {
        std::puts("Cannot read code at that address");
        return 1;
    }
    ZydisDecoder dec;
    if (!ZYAN_SUCCESS(ZydisDecoderInit(&dec, ZYDIS_MACHINE_MODE_LONG_64,
                                       ZYDIS_STACK_WIDTH_64))) {
        std::puts("Zydis init failed");
        return 1;
    }
    ZydisFormatter fmt;
    ZydisFormatterInit(&fmt, ZYDIS_FORMATTER_STYLE_INTEL);

    size_t off = 0;
    for (size_t i = 0; i < count && off < code.size(); ++i) {
        ZydisDecodedInstruction insn;
        ZydisDecodedOperand ops[ZYDIS_MAX_OPERAND_COUNT];
        if (!ZYAN_SUCCESS(ZydisDecoderDecodeFull(&dec, code.data() + off,
                                                 code.size() - off, &insn, ops))) {
            std::printf("%-18s db %02X\n", p.describe(start + off).c_str(), code[off]);
            ++off;
            continue;
        }
        char text[256] = {};
        ZydisFormatterFormatInstruction(&fmt, &insn, ops, insn.operand_count_visible, text,
                                        sizeof text, start + off, nullptr);
        std::string note;
        // Resolve any RIP-relative memory operand to an absolute address, and say
        // whether it lands in the image and what is there.
        for (int k = 0; k < insn.operand_count_visible; ++k) {
            const ZydisDecodedOperand& op = ops[k];
            if (op.type != ZYDIS_OPERAND_TYPE_MEMORY) continue;
            if (op.mem.base != ZYDIS_REGISTER_RIP) continue;
            const uint64_t target = start + off + insn.length +
                                    static_cast<uint64_t>(op.mem.disp.value);
            note = std::format("   -> {}", p.describe(target));
            if (p.is_readable(target)) {
                uint8_t b = 0;
                if (p.read(target, &b, 1)) note += std::format(" (byte {})", b);
            } else {
                note += " (in zero-filled memory; loaded only at runtime)";
            }
        }
        // A call through a register or memory is worth flagging: it is often a
        // virtual dispatch or an import.
        if (insn.mnemonic == ZYDIS_MNEMONIC_CALL && insn.operand_count_visible == 1 &&
            ops[0].type == ZYDIS_OPERAND_TYPE_IMMEDIATE) {
            const uint64_t target = ops[0].imm.is_relative
                                        ? start + off + insn.length + ops[0].imm.value.s
                                        : static_cast<uint64_t>(ops[0].imm.value.u);
            note += std::format("   call {}", p.describe(target));
        }
        std::printf("%-18s %-46s%s\n", p.describe(start + off).c_str(), text, note.c_str());
        off += insn.length;
    }
    return 0;
#endif
}

int cmd_rtti(const Process& p, const Args& a) {    if (a.pos.size() < 2) return usage(), 2;
    auto addr = parse_addr(p, a.pos[1]);
    if (!addr) return std::puts("Bad address"), 2;
    const std::string cls = p.rtti_name(*addr);
    std::printf("%s\n", cls.empty() ? "(no RTTI)" : cls.c_str());
    return 0;
}

int cmd_classes(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    const std::string needle = a.pos[1];
    const size_t max = parse_count(a.get("--max", "50"), 50);
    auto pat = cdmp::parse_pattern("2E 3F 41 56");  // ".?AV" (class)
    auto pat_struct = cdmp::parse_pattern("2E 3F 41 55");  // ".?AU" (struct)
    std::vector<uint64_t> hits = p.scan(*pat, 200000);
    auto more = p.scan(*pat_struct, 200000);
    hits.insert(hits.end(), more.begin(), more.end());
    size_t shown = 0;
    for (uint64_t h : hits) {
        const std::string name = p.read_cstring(h, 200);
        if (name.find(needle) == std::string::npos || !name.ends_with("@@")) continue;
        // TypeDescriptor: vftable ptr (8) + spare (8) + name.
        std::printf("%-70s TypeDescriptor %s\n", name.c_str(), p.describe(h - 0x10).c_str());
        if (++shown >= max) break;
    }
    std::printf("%zu shown\n", shown);
    return 0;
}

std::string le_bytes(uint64_t v, int n) {
    std::string s;
    for (int i = 0; i < n; ++i) s += std::format("{}{:02X}", i ? " " : "", (v >> (8 * i)) & 0xFF);
    return s;
}

int cmd_vtables(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    const std::string name = a.pos[1];
    // 1) Find the TypeDescriptor by its name.
    std::string hex;
    for (char c : name) hex += std::format("{:02X} ", static_cast<unsigned char>(c));
    hex += "00";
    auto name_hits = p.scan(*cdmp::parse_pattern(hex), 4);
    if (name_hits.empty()) return std::puts("Type name not found"), 1;
    for (uint64_t nh : name_hits) {
        const uint64_t td = nh - 0x10;
        const uint64_t td_rva = td - p.module_base();
        // 2) CompleteObjectLocators referencing it: sig 1, then TD RVA at +0x0C.
        auto col_pat = cdmp::parse_pattern("01 00 00 00 ?? ?? ?? ?? ?? ?? ?? ?? " + le_bytes(td_rva, 4));
        for (uint64_t col : p.scan(*col_pat, 64)) {
            auto self_rva = p.read<uint32_t>(col + 0x14);
            if (!self_rva || p.module_base() + *self_rva != col) continue;
            const uint32_t sub_offset = p.read<uint32_t>(col + 4).value_or(0);
            // 3) The vtable is preceded by a pointer to the COL.
            for (uint64_t ref : p.scan(*cdmp::parse_pattern(le_bytes(col, 8)), 16)) {
                std::printf("vtable %s  (COL %s, subobject offset 0x%X)\n",
                            p.describe(ref + 8).c_str(), p.describe(col).c_str(), sub_offset);
            }
        }
    }
    return 0;
}

int cmd_findptr(const Process& p, const Args& a) {
    if (a.pos.size() < 2) return usage(), 2;
    auto value = parse_addr(p, a.pos[1]);
    if (!value) return std::puts("Bad value"), 2;
    const size_t max = parse_count(a.get("--max", "50"), 50);
    const auto scope = a.flag("--heap") ? Process::Scope::Heap : Process::Scope::Module;
    // Pointers are 8-byte aligned in practice; filter unaligned hits.
    size_t shown = 0;
    for (uint64_t h : p.scan(*cdmp::parse_pattern(le_bytes(*value, 8)), max * 4, scope)) {
        if (h % 8) continue;
        std::printf("  %s\n", p.describe(h).c_str());
        if (++shown >= max) break;
    }
    std::printf("%zu found in %s\n", shown, scope == Process::Scope::Heap ? "heap" : "exe image");
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    Args a = parse_args(argc, argv);
    if (a.pos.empty()) return usage(), 2;

    Process p;
    bool attached = false;
    if (a.opt.contains("--image")) {
        // Offline: the exe off disk. No process, so anything that needs live state
        // is refused below rather than answered with a plausible-looking zero.
        const std::string path = a.get("--image", "");
        attached = p.open_image_file(std::wstring(path.begin(), path.end()));
        if (!attached) {
            std::printf("Cannot open image '%s' (error %lu)\n", path.c_str(), GetLastError());
            return 1;
        }
        const std::string& c = a.pos[0];
        if (c == "chain" || c == "watch" || c == "rtti") {
            std::printf("'%s' needs live memory (a running game); --image only reads the file.\n"
                        "Commands that work with --image: info scan sigs rip read dump disasm "
                        "classes vtables findptr\n", c.c_str());
            return 2;
        }
        if (a.flag("--heap")) {
            std::printf("'--heap' needs live memory; --image only reads the file.\n");
            return 2;
        }
    } else if (a.opt.contains("--pid")) {
        attached = p.attach_by_pid(static_cast<uint32_t>(parse_count(a.get("--pid", "0"), 0)));
    } else {
        const std::string name = a.get("--process", "CrimsonDesert.exe");
        attached = p.attach_by_name(std::wstring(name.begin(), name.end()));
    }
    if (!attached) {
        std::printf("Cannot attach (is the game running?) error %lu\n", GetLastError());
        return 1;
    }

    const std::string& cmd = a.pos[0];
    if (cmd == "info") return cmd_info(p);
    if (cmd == "scan") return cmd_scan(p, a);
    if (cmd == "sigs") return cmd_sigs(p, a);
    if (cmd == "rip") return cmd_rip(p, a);
    if (cmd == "read") return cmd_read(p, a);
    if (cmd == "chain") return cmd_chain(p, a);
    if (cmd == "watch") return cmd_watch(p, a);
    if (cmd == "dump") return cmd_dump(p, a);
    if (cmd == "disasm") return cmd_disasm(p, a);
    if (cmd == "rtti") return cmd_rtti(p, a);
    if (cmd == "classes") return cmd_classes(p, a);
    if (cmd == "vtables") return cmd_vtables(p, a);
    if (cmd == "findptr") return cmd_findptr(p, a);
    usage();
    return 2;
}
