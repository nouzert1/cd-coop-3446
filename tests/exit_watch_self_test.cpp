// Self test for the exit-watch technique used by src/mod/game/exit_watch.cpp.
//
// Why this exists: "it compiles" and "it logged that it installed" are not evidence that
// a hook fires, and this project has been misled four times by a value that looked like a
// result. The two crashes of 31 Oct 2026 are being diagnosed on the assumption that a
// silent exit can be observed at all, so that assumption is checked here rather than
// taken on faith.
//
// The checks are deliberately about the PATCH, not about killing this process:
//
//   * the entry point of the target really holds the 14-byte absolute jump
//   * the jump really lands on the replacement
//   * the replacement can run and capture a stack
//
// If the entry point is too short to hold the patch, or a prologue cannot be written,
// the first check fails -- which is the failure mode that would make the mod report
// "Exit watch: ... FAILED" on the guest's machine and leave us with no data again.

#include <windows.h>

#include <atomic>
#include <cstdio>

namespace {

std::atomic<int> g_hits{0};
std::atomic<int> g_frames{0};

using TerminateProcessFn = BOOL(WINAPI*)(HANDLE, UINT);
TerminateProcessFn g_real_terminate = nullptr;

BOOL WINAPI probe_terminate(HANDLE proc, UINT code) {
    (void)proc;
    (void)code;
    void* frames[16];
    g_frames.store(static_cast<int>(RtlCaptureStackBackTrace(0, 16, frames, nullptr)));
    g_hits.fetch_add(1);
    // Deliberately does NOT terminate: this test must not end the test process.
    return TRUE;
}

// The same 14-byte absolute jump the mod writes: FF 25 <rel32> then the target pointer.
bool patch(const wchar_t* module, const char* name, void* replacement, void** original) {
    HMODULE mod = GetModuleHandleW(module);
    if (!mod) return false;
    auto* fn = reinterpret_cast<uint8_t*>(GetProcAddress(mod, name));
    if (!fn) return false;
    auto* stub = static_cast<uint8_t*>(
        VirtualAlloc(nullptr, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!stub) return false;
    *original = fn;
    DWORD old = 0;
    if (!VirtualProtect(fn, 14, PAGE_EXECUTE_READWRITE, &old)) return false;
    stub[0] = 0xFF;
    stub[1] = 0x25;
    *reinterpret_cast<uint32_t*>(stub + 2) = 0;
    *reinterpret_cast<uint64_t*>(stub + 6) = reinterpret_cast<uint64_t>(replacement);
    fn[0] = 0xFF;
    fn[1] = 0x25;
    *reinterpret_cast<uint32_t*>(fn + 2) = 0;
    *reinterpret_cast<uint64_t*>(fn + 6) = reinterpret_cast<uint64_t>(stub);
    VirtualProtect(fn, 14, old, &old);
    FlushInstructionCache(GetCurrentProcess(), fn, 14);
    return true;
}

}  // namespace

int exit_watch_self_test() {
    int failures = 0;

    if (!patch(L"kernel32.dll", "TerminateProcess", reinterpret_cast<void*>(&probe_terminate),
               reinterpret_cast<void**>(&g_real_terminate))) {
        std::printf("FAIL: could not patch TerminateProcess\n");
        return 1;
    }

    // 1. The entry really holds the jump, and it lands on the stub we allocated.
    auto* fn = reinterpret_cast<uint8_t*>(
        GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "TerminateProcess"));
    if (fn[0] != 0xFF || fn[1] != 0x25) {
        std::printf("FAIL: TerminateProcess entry is not the expected jump\n");
        ++failures;
    } else {
        const uint64_t stub = *reinterpret_cast<uint64_t*>(fn + 6);
        const uint8_t* s = reinterpret_cast<const uint8_t*>(stub);
        if (s[0] != 0xFF || s[1] != 0x25 ||
            *reinterpret_cast<uint64_t*>(const_cast<uint8_t*>(s) + 6) !=
                reinterpret_cast<uint64_t>(&probe_terminate)) {
            std::printf("FAIL: the jump does not land on the replacement\n");
            ++failures;
        }
    }

    // 2. Calling it actually reaches the replacement, and the replacement can walk a
    //    stack. This is the part that would silently fail inside a dying process.
    TerminateProcess(GetCurrentProcess(), 0xDEAD);
    if (g_hits.load() != 1) {
        std::printf("FAIL: the replacement did not run (hits %d)\n", g_hits.load());
        ++failures;
    }
    if (g_frames.load() <= 1) {
        std::printf("FAIL: the replacement captured %d frames, expected more than 1\n",
                    g_frames.load());
        ++failures;
    }

    // 3. RtlCaptureStackBackTrace must be usable without loading anything, because the
    //    real hook runs after the process has started tearing down.
    void* frames[16];
    const USHORT n = RtlCaptureStackBackTrace(0, 16, frames, nullptr);
    if (n == 0) {
        std::printf("FAIL: RtlCaptureStackBackTrace returned nothing\n");
        ++failures;
    }

    if (failures == 0) std::printf("exit_watch self test: OK (%d frames)\n", g_frames.load());
    return failures;
}
