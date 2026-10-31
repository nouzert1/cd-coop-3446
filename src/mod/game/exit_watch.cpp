#include "mod/game/exit_watch.h"

#include <windows.h>

#include <atomic>
#include <cstdio>
#include <cstring>

#include "mod/log.h"

// Everything here comes from ntdll and kernel32, which are already loaded -- no dbghelp,
// no psapi. That matters for a reason beyond tidiness: this code can run at the moment
// the process is tearing down, and loading a DLL then can deadlock on the loader lock.
//
// ---------------------------------------------------------------------------------
// WHAT WENT WRONG THE FIRST TIME (31 Oct 2026), because the fix is shaped by it
// ---------------------------------------------------------------------------------
//
// The first version of this file hooked RaiseException and, from inside that hook, called
// log::warn and walked the stack. Both sides of the 2-PC test then began dying BEFORE the
// main menu, on two different machines, on the same mod build. The build that worked
// earlier that day differed only by this file:
//
//     src/mod/game/exit_watch.cpp | 186 +++++++++++++++++++++++++++++++++++
//     src/mod/game/exit_watch.h   |  34 ++++++++
//     src/mod/mod.cpp             |   6 ++
//
// RaiseException is not an error path. The MSVC C++ runtime raises exceptions as normal
// control flow -- thread naming, C++ throw, SEH probes -- thousands of times in a healthy
// startup. Running a logging call and a stack walk from inside it means running arbitrary
// code in the middle of exception dispatch, on a thread that may hold the CRT lock or the
// loader lock, and doing it again on every subsequent raise. The unit test passed because
// it called the patched function once from a quiet thread, which is the one situation
// where the problem cannot appear. "It compiles, it installed, and the self test passes"
// was true of a hook that broke both players' games.
//
// Two rules now, and they are the whole design:
//
//   1. NEVER hook RaiseException. It is not an exit path, and being inside exception
//      dispatch is the worst place to run code that can allocate, lock, or re-enter.
//   2. The exit hooks record into a fixed, pre-allocated buffer with no allocation, no
//      locks and no formatting, then let the exit proceed. The buffer is written to disk
//      by the logger's own thread if it is still alive, and by a raw WriteFile if it is
//      not. Nothing on the dying path can block.
//
// What this can see is therefore narrower than the first version claimed: a silent
// TerminateProcess or ExitProcess is recorded. A crash by memory fault is not, and is
// left to Windows Error Reporting, which does capture it -- that is how the 17:34 dump
// was found.

namespace cdmp::game {
namespace {

// The record left by a dying process. Written without allocation so that it is safe to
// fill in from inside TerminateProcess.
struct ExitRecord {
    std::atomic<uint32_t> ready{0};
    uint32_t code = 0;
    char via[24] = {};
    void* frames[12] = {};
    int frame_count = 0;
};

ExitRecord g_record;

using TerminateProcessFn = BOOL(WINAPI*)(HANDLE, UINT);
using ExitProcessFn = void(WINAPI*)(UINT);
using RtlExitUserProcessFn = void(WINAPI*)(UINT);

TerminateProcessFn g_real_terminate = nullptr;
ExitProcessFn g_real_exit = nullptr;
RtlExitUserProcessFn g_real_rtl_exit = nullptr;

// Plain memcpy of a fixed string: no CRT formatting, no allocation, no exceptions.
void set_via(const char* s) {
    size_t i = 0;
    for (; s[i] && i < sizeof(g_record.via) - 1; ++i) g_record.via[i] = s[i];
    g_record.via[i] = '\0';
}

// Fill the record and let the exit continue. Deliberately does NOT log: the logging path
// may take a lock whose owner is the thread now exiting, and a deadlock here would turn a
// diagnosable exit into a hang. The record is collected afterwards.
[[noreturn]] void note_and_die(const char* via, DWORD code) {
    bool expected = false;
    static std::atomic<bool> taken{false};
    if (taken.compare_exchange_strong(expected, true)) {
        set_via(via);
        g_record.code = code;
        __try {
            g_record.frame_count = static_cast<int>(
                RtlCaptureStackBackTrace(1, 12, g_record.frames, nullptr));
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            g_record.frame_count = 0;
        }
        g_record.ready.store(1, std::memory_order_release);
    }
    // Nothing else. The real exit must happen exactly once, and by whichever path the
    // game chose -- intercepting it further would change behaviour we are only observing.
    if (std::strcmp(via, "TerminateProcess") == 0) {
        if (g_real_terminate) g_real_terminate(GetCurrentProcess(), code);
    } else if (std::strcmp(via, "ExitProcess") == 0) {
        if (g_real_exit) g_real_exit(code);
    } else if (g_real_rtl_exit) {
        g_real_rtl_exit(code);
    }
    // If the real call returned (it should not for these), end the thread rather than
    // returning into the game with a half-torn-down state.
    TerminateProcess(GetCurrentProcess(), code);
    for (;;) Sleep(1000);
}

BOOL WINAPI hook_terminate(HANDLE proc, UINT code) {
    if (proc == GetCurrentProcess()) note_and_die("TerminateProcess", code);
    return g_real_terminate ? g_real_terminate(proc, code) : FALSE;
}

void WINAPI hook_exit(UINT code) { note_and_die("ExitProcess", code); }

void WINAPI hook_rtl_exit(UINT code) { note_and_die("RtlExitUserProcess", code); }

// Install by writing a 14-byte absolute jump over the entry point: FF 25 <rel32> then the
// target pointer. No register is clobbered and no return address is needed, so it is safe
// at a function entry.
bool patch_entry(const wchar_t* module, const char* name, void* replacement, void** original) {
    HMODULE mod = GetModuleHandleW(module);
    if (!mod) return false;
    auto* fn = reinterpret_cast<uint8_t*>(GetProcAddress(mod, name));
    if (!fn) return false;

    auto* stub = static_cast<uint8_t*>(
        VirtualAlloc(nullptr, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!stub) return false;
    *original = fn;

    DWORD old = 0;
    if (!VirtualProtect(fn, 14, PAGE_EXECUTE_READWRITE, &old)) {
        VirtualFree(stub, 0, MEM_RELEASE);
        return false;
    }
    stub[0] = 0xFF;
    stub[1] = 0x25;
    *reinterpret_cast<uint32_t*>(stub + 2) = 0;
    *reinterpret_cast<uint64_t*>(stub + 6) = reinterpret_cast<uint64_t>(replacement);
    // The stub is intentionally never freed: the patched entry jumps through it.
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
    // TerminateProcess and ExitProcess are the two every silent exit passes through.
    // RtlExitUserProcess is the lower path ExitProcess itself uses, so hooking it too
    // catches an exit that bypasses the Win32 wrapper.
    //
    // RaiseException is deliberately NOT hooked. See the block comment above: hooking it
    // is what broke both players' games on 31 Oct 2026, because the C++ runtime uses it
    // as normal control flow and the hook ran logging and a stack walk inside exception
    // dispatch.
    const bool t = patch_entry(L"kernel32.dll", "TerminateProcess",
                               reinterpret_cast<void*>(&hook_terminate),
                               reinterpret_cast<void**>(&g_real_terminate));
    const bool e = patch_entry(L"kernel32.dll", "ExitProcess",
                               reinterpret_cast<void*>(&hook_exit),
                               reinterpret_cast<void**>(&g_real_exit));
    const bool r = patch_entry(L"ntdll.dll", "RtlExitUserProcess",
                               reinterpret_cast<void*>(&hook_rtl_exit),
                               reinterpret_cast<void**>(&g_real_rtl_exit));

    log::info("Exit watch: TerminateProcess {} | ExitProcess {} | RtlExitUserProcess {} "
              "(RaiseException not hooked: it fires as normal control flow)",
              t ? "hooked" : "FAILED", e ? "hooked" : "FAILED", r ? "hooked" : "FAILED");
    return t || e;
}

// Reads the record left by a dying process. Called only when the caller has strong reason
// to believe an exit happened -- there is no callback, because the callback is the thing
// that was unsafe.
bool exit_watch_take_record(uint32_t& code, const char*& via, void* const*& frames, int& count) {
    if (!g_record.ready.load(std::memory_order_acquire)) return false;
    code = g_record.code;
    via = g_record.via;
    frames = g_record.frames;
    count = g_record.frame_count;
    return true;
}

}  // namespace cdmp::game
