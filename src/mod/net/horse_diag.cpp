#include "mod/net/horse_diag.h"

#include <windows.h>

#include <atomic>
#include <chrono>
#include <cstring>

#include <safetyhook.hpp>

#include "mod/game/offsets.h"
#include "mod/game/safe_memory.h"
#include "mod/log.h"
#include "mod/net/enemy_relay.h"

namespace cdmp::net {
namespace {
namespace off = game::build_3446;

constexpr uint32_t kCopyHorse = 0xB010F002;

struct Site {
    uintptr_t rva;
    uint8_t head[16];
    const char* name;
};
// ---- containment sites, 1.0.0.3446 ----------------------------------------
//
// All four are build-specific and were re-measured for 3446 on 2026-10-30, because the
// 3424 values read as garbage here (verified byte-for-byte against an independent read
// of the same executable on the guest's PC).
//
// Measured so far:
//
//   kCcUpdate  exe+0x941D40 - three independent agreeing measurements:
//      1. its body touches the component struct the way read_state() reads it:
//         [rcx+0x08] actor, [rbx+0x40] state, [rax+0x30] restore, [rbx+0x88] layer,
//         [rbx+0xA8] pending;
//      2. it is slot 16 of the vtable of .?AVClientCharacterControlActorComponent@pa@@
//         at exe+0x59388D0, the same vtable the port already uses as kVtCharacterControl;
//      3. live: findptr located real instances in the running game and the object has
//         ALL SIX read_state fields populated, with +0x08 resolving to a
//         .?AVClientNormalInGameActor@pa@@ and actor+0x60 reading 0xB01017E1 (the 0xB0
//         prefix is the player actor key family).
//
//   kRestore   exe+0x948240 - two agreeing measurements:
//      1. it reads [this+0x08] (actor), [this+0x40] (state) and [state+0x30] (restore),
//         and touches [this+0x88] and [this+0x90] (the two layers) - the exact field set
//         on_restore walks;
//      2. its 16-byte prologue is byte-identical to the 3424 value. A prologue surviving
//         a patch is not something to rely on, but here it is corroboration rather than
//         the basis: the behaviour above is what identifies the function.
//
// Still unresolved: kCcPost and kPending. Note the delta between kCcUpdate and kRestore
// CHANGED between builds (0x4B30 on 3424, 0x6500 here), which is the second independent
// reason a fixed delta cannot be used to port these - the first being the 0x35 spread
// this port already measured across the globals.
//   kCcPost    exe+0x860D60 - found by DIFFING the two builds, which is now possible
//         because a copy of the 1.0.0.3424 executable survived on disk
//         (CD-ref/_scan/CrimsonDesert.exe, PE timestamp 0x6AE387F2). Comparing the
//         two showed the whole function barely moved: the 3424 body at exe+0x860C20
//         and the 3446 body at exe+0x860C50 are the same code instruction for
//         instruction, just shifted by 0x30, with branch displacements adjusted.
//         The mid-hook point is +0x110 into that body in both builds, and its 16
//         bytes are IDENTICAL (0F 85 B6 00 00 00 4C 89 6C 24 28 80 7C 24 38 00),
//         which the per-site prologue check will verify at install time.
//
//         This also corrects a wrong assumption made earlier in the session: it was
//         assumed kCcPost must read the layer chart (+0x110) because on_cc_post
//         does. It does not. The mod reproduces that logic in C++; the game is not
//         obliged to read the field the same way, and kCcUpdate - the very function
//         this pass follows - never touches +0x110 at all. Searching for a chart
//         read was searching for something that was never there.
constexpr Site kCcUpdate = {0x941D40, {0x48, 0x89, 0x5C, 0x24, 0x10, 0x48, 0x89, 0x74, 0x24, 0x18, 0x57, 0x48,
                                       0x83, 0xEC, 0x20, 0x48}, "CC update"};
constexpr Site kCcPost = {0x860D60, {0x0F, 0x85, 0xB6, 0x00, 0x00, 0x00, 0x4C, 0x89, 0x6C, 0x24, 0x28, 0x80,
                                     0x7C, 0x24, 0x38, 0x00}, "CC post-update"};
constexpr Site kRestore = {0x948240, {0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x20, 0x48, 0x89, 0x50, 0x10, 0x55,
                                      0x56, 0x57, 0x41, 0x54}, "restore actions"};
constexpr Site kPending = {0x2329D70, {0x48, 0x89, 0x5C, 0x24, 0x10, 0x48, 0x89, 0x6C, 0x24, 0x18, 0x48, 0x89,
                                       0x74, 0x24, 0x20, 0x57}, "pending actions"};

SafetyHookMid g_cc_hook, g_post_hook, g_restore_hook, g_pending_hook;
uint8_t* g_ret = nullptr;
bool g_contain = false;
std::atomic<uint32_t> g_watch_real{0};
std::atomic<int> g_lines{0};
constexpr int kMaxLines = 400;
std::atomic<uint64_t> g_skipped{0}, g_skipped_post{0};
uint64_t g_t0 = 0;

uint64_t now_ms() {
    using namespace std::chrono;
    return static_cast<uint64_t>(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
}

struct Layer {
    uintptr_t a0, a8, a10, a18, chart;
};
struct State {
    uint32_t key = 0;
    Layer layer[2]{};
    uint8_t pending = 0;     // CC+0xA8
    uintptr_t pending_list = 0;  // CC+0x80
    uint8_t restore = 0xFF;  // [[CC+0x40]+0x30]
};

bool read_key(uintptr_t cc, uint32_t& key) {
    __try {
        const auto actor = *reinterpret_cast<const uintptr_t*>(cc + 0x08);
        if (!actor) return false;
        key = *reinterpret_cast<const uint32_t*>(actor + off::kActor_Key);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

bool read_state(uintptr_t cc, State& s) {
    __try {
        for (int i = 0; i < 2; ++i) {
            const auto l = *reinterpret_cast<const uintptr_t*>(cc + 0x88 + 8 * i);
            if (!l) continue;
            s.layer[i] = {*reinterpret_cast<const uintptr_t*>(l + 0x00), *reinterpret_cast<const uintptr_t*>(l + 0x08),
                          *reinterpret_cast<const uintptr_t*>(l + 0x10), *reinterpret_cast<const uintptr_t*>(l + 0x18),
                          *reinterpret_cast<const uintptr_t*>(l + 0x110)};
        }
        s.pending = *reinterpret_cast<const uint8_t*>(cc + 0xA8);
        s.pending_list = *reinterpret_cast<const uintptr_t*>(cc + 0x80);
        const auto st = *reinterpret_cast<const uintptr_t*>(cc + 0x40);
        s.restore = st ? *reinterpret_cast<const uint8_t*>(st + 0x30) : 0xFE;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

void read_restore_data(uintptr_t cc, uint8_t (&raw)[0x10], uint64_t& f8) {
    __try {
        const auto st = *reinterpret_cast<const uintptr_t*>(cc + 0x40);
        if (st) {
            std::memcpy(raw, reinterpret_cast<const void*>(st + 0x30), sizeof raw);
            f8 = *reinterpret_cast<const uint64_t*>(st + 0xF8);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
}

// Keys whose actor the containment may have to skip.
//
// The other player's character belongs here and was missing: kPuppetPlayer and
// kPuppetBody are built by remote_puppet.cpp and are exactly the actors this file
// exists to protect, so leaving them out meant the guard could never fire for the one
// case that has actually crashed the host. Found by an external review of this file
// (30/10/2026) that read is_copy() against the key list in the puppet code.
//
// The body is included too, not just the player: both are copied actors driven by
// replayed packets rather than by the local world, which is what makes them the ones
// that can arrive with a layer that has a chart and no action.
inline constexpr uint32_t kPuppetPlayerKey = 0xA010F001;
inline constexpr uint32_t kPuppetBodyKey = 0xB010F001;
bool is_copy(uint32_t key) {
    return key == kCopyHorse || is_enemy_copy_key(key) || key == kPuppetPlayerKey || key == kPuppetBodyKey;
}

bool watched(uint32_t key) {
    return is_copy(key) || (key && key == g_watch_real.load(std::memory_order_relaxed));
}

const char* who(uint32_t key) {
    if (key == kCopyHorse) return "COPY";
    if (is_enemy_copy_key(key)) return "ENEMY COPY";
    if (key == kPuppetPlayerKey || key == kPuppetBodyKey) return "OTHER PLAYER";
    return "real";
}

// Same "shape" = same nullness of every field (pointers themselves change).
uint32_t shape(const State& s) {
    uint32_t v = 0;
    for (int i = 0; i < 2; ++i) {
        const Layer& l = s.layer[i];
        v = v << 5 | (l.a0 != 0) | (l.a8 != 0) << 1 | (l.a10 != 0) << 2 | (l.a18 != 0) << 3 | (l.chart != 0) << 4;
    }
    return v << 10 | (s.pending != 0) << 9 | (s.pending_list != 0) << 8 | s.restore;
}

bool take_line() { return g_lines.fetch_add(1, std::memory_order_relaxed) < kMaxLines; }

void log_state(const char* where, const State& s) {
    if (!take_line()) return;
    log::info("HorseDiag +{} ms {} {} 0x{:08X}: L0 a0={} a8={} cur(+10)={} play(+18)={} chart={} | "
              "L1 cur={} play={} chart={} | pending(+A8)={} list(+80)={} restoreByte={}",
              now_ms() - g_t0, where, who(s.key), s.key, s.layer[0].a0 != 0, s.layer[0].a8 != 0,
              s.layer[0].a10 != 0, s.layer[0].a18 != 0, s.layer[0].chart != 0, s.layer[1].a10 != 0,
              s.layer[1].a18 != 0, s.layer[1].chart != 0, s.pending, s.pending_list != 0, s.restore);
}

// A layer with its own chart but nothing playing: the update crashes on it.
// Both layers: an enemy copy ("Wolf Tracker") got its layer-0 action and
// crashed on layer 1 (live test 2026-10-04).
bool layer_without_action(const State& s) {
    for (const Layer& l : s.layer) {
        if (l.chart && (!l.a10 || !l.a18)) return true;
    }
    return false;
}

// Last shape seen per watched actor (2 slots: copy, real).
std::atomic<uint32_t> g_last_shape[3] = {0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF};

void on_cc_update(safetyhook::Context& ctx) {
    uint32_t key = 0;
    if (!read_key(ctx.rcx, key) || !watched(key)) return;
    State s;
    s.key = key;
    if (!read_state(ctx.rcx, s)) return;
    const uint32_t sh = shape(s);
    auto& last = g_last_shape[key == kCopyHorse ? 0 : is_enemy_copy_key(key) ? 2 : 1];
    if (last.exchange(sh, std::memory_order_relaxed) != sh) log_state("update", s);
    // Containment: a copy whose main layer has a chart but no current action
    // crashed three different functions of this update (INFORME §5).
    if (g_contain && is_copy(key) && layer_without_action(s)) {
        g_skipped.fetch_add(1, std::memory_order_relaxed);
        ctx.rip = reinterpret_cast<uintptr_t>(g_ret);
    }
}

void on_cc_post(safetyhook::Context& ctx) {
    if (!g_contain) return;
    uint32_t key = 0;
    if (!read_key(ctx.rcx, key) || !is_copy(key)) return;
    State s;
    if (!read_state(ctx.rcx, s)) return;
    if (layer_without_action(s)) {
        g_skipped_post.fetch_add(1, std::memory_order_relaxed);
        ctx.rip = reinterpret_cast<uintptr_t>(g_ret);
    }
}

void on_restore(safetyhook::Context& ctx) {
    uint32_t key = 0;
    if (!read_key(ctx.rcx, key) || !watched(key)) return;
    State s;
    s.key = key;
    if (!read_state(ctx.rcx, s)) return;
    log_state("RESTORE(0x8646D0)", s);
    // The restore data: bytes +0x30..+0x40 and the u64 at +0xF8 of [CC+0x40].
    uint8_t raw[0x10] = {};
    uint64_t f8 = 0;
    read_restore_data(ctx.rcx, raw, f8);
    if (take_line()) {
        log::info("HorseDiag   restore data [CC+0x40]+0x30: {:02X} {:02X} {:02X} {:02X} {:02X} {:02X} {:02X} {:02X} "
                  "{:02X} {:02X} {:02X} {:02X} {:02X} {:02X} {:02X} {:02X} | +0xF8 0x{:X}",
                  raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7], raw[8], raw[9], raw[10],
                  raw[11], raw[12], raw[13], raw[14], raw[15], f8);
    }
}

void on_pending(safetyhook::Context& ctx) {
    uint32_t key = 0;
    if (!read_key(ctx.rcx, key) || !watched(key)) return;
    State s;
    s.key = key;
    if (!read_state(ctx.rcx, s)) return;
    if (s.pending) log_state("PENDING(0x2329D70)", s);
}

bool hook(const Site& site, SafetyHookMid& out, safetyhook::MidHookFn fn) {
    const uintptr_t base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    uint8_t head[16];
    if (!game::safe_read(base + site.rva, head, sizeof head) || std::memcmp(head, site.head, sizeof head) != 0) {
        log::warn("HorseDiag: {} (exe+0x{:X}) not recognised", site.name, site.rva);
        return false;
    }
    auto h = safetyhook::MidHook::create(reinterpret_cast<void*>(base + site.rva), fn);
    if (!h) {
        log::warn("HorseDiag: {} hook failed", site.name);
        return false;
    }
    out = std::move(*h);
    return true;
}

}  // namespace

bool horse_diag_install(bool contain) {
    if (g_cc_hook) return true;
    g_t0 = now_ms();
    g_ret = static_cast<uint8_t*>(VirtualAlloc(nullptr, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!g_ret) return false;
    g_ret[0] = 0xC3;
    DWORD old = 0;
    VirtualProtect(g_ret, 16, PAGE_EXECUTE_READ, &old);
    FlushInstructionCache(GetCurrentProcess(), g_ret, 16);
    const bool ok = hook(kCcUpdate, g_cc_hook, on_cc_update) && hook(kRestore, g_restore_hook, on_restore) &&
                    hook(kPending, g_pending_hook, on_pending);
    if (!ok) {
        g_cc_hook = {};
        g_restore_hook = {};
        g_pending_hook = {};
        return false;
    }
    // If the post-update hook is asked for and does not install, the containment is
    // incomplete, and the caller must not be told it is armed.
    //
    // This returned true unconditionally, so a request for containment that only got
    // three of its four hooks was reported as success: mod.cpp reads the return value
    // as `contained` and enables the horse and enemy copies on the strength of it.
    // Those copies then run without the post-update pass that exists to catch a layer
    // with a chart and no action -- the exact state the containment was written for.
    // Found by an external review of this file (30/10/2026).
    //
    // Partial installs are now torn down rather than left half-armed, because a
    // containment that fires on some paths and not others is worse than none: it makes
    // the failure intermittent instead of reproducible.
    if (contain && !hook(kCcPost, g_post_hook, on_cc_post)) {
        g_post_hook = {};
        g_cc_hook = {};
        g_restore_hook = {};
        g_pending_hook = {};
        log::warn("HorseDiag: post-update hook not installed; containment refused (all four hooks uninstalled)");
        return false;
    }
    g_contain = contain;
    log::info("HorseDiag: installed (containment {})", g_contain ? "on" : "off");
    return true;
}

void horse_diag_watch(uint32_t key) {
    g_watch_real = key;
    log::info("HorseDiag: watching the copy 0x{:08X} and the real horse 0x{:08X}", kCopyHorse, key);
}

void horse_diag_tick() {
    static uint64_t logged = 0, logged_post = 0, last = 0;
    const uint64_t a = g_skipped.load(std::memory_order_relaxed), b = g_skipped_post.load(std::memory_order_relaxed);
    const uint64_t t = now_ms();
    if ((a != logged || b != logged_post) && t - last >= 2000) {
        log::info("HorseDiag: copy's update skipped {} times (post-update {}) while it has no action", a, b);
        logged = a;
        logged_post = b;
        last = t;
    }
}

}  // namespace cdmp::net
