// Self test for the exit-watch technique used by src/mod/game/exit_watch.cpp.
//
// Why this exists: "it compiles" and "it logged that it installed" are not evidence that a
// hook is safe, and this project has been misled five times now by a value that looked
// like a result. The first version of exit_watch passed every check in this file and still
// broke both players' games, because the check that was missing was the one that mattered:
// it hooked RaiseException, which the C++ runtime raises as ordinary control flow.
//
// So the checks below are in two groups.
//
// The patch is real:
//   * the entry point of the target really holds the 14-byte absolute jump
//   * the jump really lands on the replacement
//   * the replacement can run and capture a stack
//
// The patch is safe:
//   * RaiseException is NOT patched -- the property whose absence broke the game
//   * the raising path still works with the hooks installed, i.e. a C++ throw completes
//
// The second group is the one that would have caught the 31 Oct regression. Any future
// change here should keep it, and should treat a passing first group as necessary and
// nowhere near sufficient.

#include <windows.h>

#include <atomic>
#include <cstdio>
#include <stdexcept>

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

    // ---------------------------------------------------------------------------------
    // SAFETY GROUP. This is the group that would have caught the 31 Oct 2026 regression,
    // where the mod passed every check above and still killed both players' games.
    // ---------------------------------------------------------------------------------

    // 4. RaiseException must NOT be patched. The C++ runtime raises it as ordinary control
    //    flow -- thread naming, every `throw` -- so a hook there runs arbitrary code
    //    inside exception dispatch, thousands of times per startup.
    auto* raise_fn = reinterpret_cast<uint8_t*>(
        GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "RaiseException"));
    if (!raise_fn) {
        std::printf("FAIL: RaiseException not found\n");
        ++failures;
    } else if (raise_fn[0] == 0xFF && raise_fn[1] == 0x25) {
        std::printf("FAIL: RaiseException is PATCHED. Do not hook it -- the C++ runtime "
                    "uses it as normal control flow, and doing so broke both players' "
                    "games on 31 Oct 2026.\n");
        ++failures;
    }

    // 5. Raising an exception must still work normally with the exit hooks in place, and
    //    must be catchable. A C++ throw goes through RaiseException, so this fails loudly
    //    if the exit hooks have disturbed exception handling in any way.
    bool caught = false;
    try {
        throw std::runtime_error("exit_watch self test probe");
    } catch (const std::runtime_error&) {
        caught = true;
    } catch (...) {
        caught = true;
    }
    if (!caught) {
        std::printf("FAIL: a thrown exception was not caught with the hooks installed\n");
        ++failures;
    }

    // 6. And it must still work repeatedly: the regression showed up as decay over a
    //    startup's worth of raises, not on the first one.
    int survived = 0;
    for (int i = 0; i < 2000; ++i) {
        try {
            throw std::runtime_error("probe");
        } catch (const std::runtime_error&) {
            ++survived;
        } catch (...) {
        }
    }
    if (survived != 2000) {
        std::printf("FAIL: only %d of 2000 throws completed\n", survived);
        ++failures;
    }

    if (failures == 0) {
        std::printf("exit_watch self test: OK (%d frames, RaiseException unhooked, "
                    "2000 throws survived)\n",
                    g_frames.load());
    }
    return failures;
}
