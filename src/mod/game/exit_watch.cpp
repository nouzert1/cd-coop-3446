#include "mod/game/exit_watch.h"

#include <windows.h>

#include <atomic>
#include <cstdio>
#include <cstring>

#include "mod/log.h"

// Everything here comes from ntdll and kernel32, which are already loaded -- no dbghelp,
// no psapi. That matters for a reason beyond tidiness: this code runs while the process
// is tearing down, and loading a DLL at that moment can deadlock on the loader lock. The
// stack walk deliberately uses RtlCaptureStackBackTrace (ntdll, always mapped) rather
// than SymFromAddr, which would need dbghelp and would buy nothing: module+offset is
// enough to locate the caller, and the PDB is ours to read offline.

namespace cdmp::game {
namespace {

// One line per exit attempt is all we get, and this runs while the process is already
// tearing itself down: no allocation, no locks, no C++ objects with destructors. A
// crash inside the reporter would replace a diagnosable death with an undiagnosable one.
std::atomic<bool> g_reporting{false};

using TerminateProcessFn = BOOL(WINAPI*)(HANDLE, UINT);
using ExitProcessFn = void(WINAPI*)(UINT);
using RtlExitUserProcessFn = void(WINAPI*)(UINT);
using RaiseExceptionFn = void(WINAPI*)(DWORD, DWORD, DWORD, const ULONG_PTR*);

TerminateProcessFn g_real_terminate = nullptr;
ExitProcessFn g_real_exit = nullptr;
RtlExitUserProcessFn g_real_rtl_exit = nullptr;
RaiseExceptionFn g_real_raise = nullptr;

constexpr int kMaxFrames = 16;
void* g_frames[kMaxFrames];

// Which module owns this address, and how far into it. Written straight into a caller
// buffer so nothing is allocated on the dying path.
void describe_address(void* addr, char* out, size_t cap) {
    out[0] = '\0';
    if (!addr) {
        std::snprintf(out, cap, "?");
        return;
    }
    HMODULE mod = nullptr;
    if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(addr), &mod) &&
        mod) {
        char path[MAX_PATH]{};
        if (GetModuleFileNameA(mod, path, MAX_PATH)) {
            const char* base = std::strrchr(path, '\\');
            base = base ? base + 1 : path;
            const auto off = reinterpret_cast<uintptr_t>(addr) - reinterpret_cast<uintptr_t>(mod);
            std::snprintf(out, cap, "%s+0x%llX", base, static_cast<unsigned long long>(off));
            return;
        }
    }
    std::snprintf(out, cap, "0x%p", addr);
}

// Returns how many frames were written. Best effort: this is called on a thread that is
// already going away, so every failure mode is "report fewer frames", never "throw".
int collect_stack(void** frames, int max, DWORD skip) {
    __try {
        return static_cast<int>(RtlCaptureStackBackTrace(skip, static_cast<DWORD>(max), frames, nullptr));
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 0;
    }
}

void report_exit(const char* via, DWORD code, DWORD skip_frames) {
    // Only the first exit path gets to write. A dying process can take several
    // (ExitProcess -> RtlExitUserProcess -> TerminateProcess), and four interleaved
    // reports would be harder to read than one, not easier.
    bool expected = false;
    if (!g_reporting.compare_exchange_strong(expected, true)) return;

    const int n = collect_stack(g_frames, kMaxFrames, skip_frames);

    log::error("Exit: {} called with code {} (0x{:08X}) -- the process is going down "
               "without an exception, which is why Windows logs nothing",
               via, code, code);
    if (n <= 0) {
        log::error("Exit: no stack available");
        return;
    }
    for (int i = 0; i < n; ++i) {
        char where[320];
        describe_address(g_frames[i], where, sizeof where);
        log::error("Exit:   [{}] {}", i, where);
    }
}

BOOL WINAPI hook_terminate(HANDLE proc, UINT code) {
    // Only our own process matters; terminating another process is not this problem.
    if (proc == GetCurrentProcess()) report_exit("TerminateProcess", code, 0);
    return g_real_terminate ? g_real_terminate(proc, code) : FALSE;
}

void WINAPI hook_exit(UINT code) {
    report_exit("ExitProcess", code, 0);
    if (g_real_exit) g_real_exit(code);
}

void WINAPI hook_rtl_exit(UINT code) {
    report_exit("RtlExitUserProcess", code, 0);
    if (g_real_rtl_exit) g_real_rtl_exit(code);
}

// Not an exit, but the CRT turns an abort into one and the distinction matters: if
// RaiseException shows up first, the abort path is the story and the exit is its tail.
void WINAPI hook_raise(DWORD code, DWORD flags, DWORD nargs, const ULONG_PTR* args) {
    static std::atomic<int> raises{0};
    if (raises.fetch_add(1) < 4) {
        log::error("Exit: RaiseException code 0x{:08X} (this usually precedes an abort)",
                   code);
    }
    if (g_real_raise) g_real_raise(code, flags, nargs, args);
}

// Install by writing the jump into the real prologue. SafetyHook is used elsewhere in
// this project but its statics are not safe to touch this late in a dying process, and
// these three functions are hot paths we must not re-enter through a trampoline while
// the loader lock is held. A plain inline patch of the entry point is enough here: we
// only need to observe, and the original bytes are not needed afterwards.
bool patch_entry(const wchar_t* module, const char* name, void* replacement, void** original) {
    HMODULE mod = GetModuleHandleW(module);
    if (!mod) return false;
    auto* fn = reinterpret_cast<uint8_t*>(GetProcAddress(mod, name));
    if (!fn) return false;

    // 48 FF 25 <rel32> = jmp qword ptr [rip+rel32] -- a 14-byte absolute jump that needs
    // no register and no return address, so it is safe to place at a function entry.
    auto* stub = static_cast<uint8_t*>(VirtualAlloc(nullptr, 64, MEM_COMMIT | MEM_RESERVE,
                                                    PAGE_EXECUTE_READWRITE));
    if (!stub) return false;

    *original = fn;  // the hook checks the flag itself; re-entrancy is not a concern here

    DWORD old = 0;
    if (!VirtualProtect(fn, 14, PAGE_EXECUTE_READWRITE, &old)) {
        VirtualFree(stub, 0, MEM_RELEASE);
        return false;
    }
    stub[0] = 0xFF;
    stub[1] = 0x25;
    *reinterpret_cast<uint32_t*>(stub + 2) = 0;
    *reinterpret_cast<uint64_t*>(stub + 6) = reinterpret_cast<uint64_t>(replacement);
    // The stub must not be freed: the patched entry point jumps through it.
    fn[0] = 0xFF;
    fn[1] = 0x25;
    *reinterpret_cast<uint32_t*>(fn + 2) = 0;
    *reinterpret_cast<uint64_t*>(fn + 6) = reinterpret_cast<uint64_t>(stub);
    VirtualProtect(fn, 14, old, &old);
    FlushInstructionCache(GetCurrentProcess(), fn, 14);
    return true;
}

}  // namespace

bool exit_watch_install() {
    const bool t = patch_entry(L"kernel32.dll", "TerminateProcess",
                               reinterpret_cast<void*>(&hook_terminate),
                               reinterpret_cast<void**>(&g_real_terminate));
    const bool e = patch_entry(L"kernel32.dll", "ExitProcess",
                               reinterpret_cast<void*>(&hook_exit),
                               reinterpret_cast<void**>(&g_real_exit));
    const bool r = patch_entry(L"ntdll.dll", "RtlExitUserProcess",
                               reinterpret_cast<void*>(&hook_rtl_exit),
                               reinterpret_cast<void**>(&g_real_rtl_exit));
    const bool x = patch_entry(L"kernel32.dll", "RaiseException",
                               reinterpret_cast<void*>(&hook_raise),
                               reinterpret_cast<void**>(&g_real_raise));

    log::info("Exit watch: TerminateProcess {} | ExitProcess {} | RtlExitUserProcess {} | "
              "RaiseException {}",
              t ? "hooked" : "FAILED", e ? "hooked" : "FAILED", r ? "hooked" : "FAILED",
              x ? "hooked" : "FAILED");
    // True if the two that a silent death must pass through are in place.
    return t || e;
}

}  // namespace cdmp::game
