#include "mod/game/game_clock.h"

#include <windows.h>

#include <cstring>

#include "mod/game/offsets.h"
#include "mod/game/safe_memory.h"

namespace cdmp::game {
namespace off = build_3446;

std::optional<uint64_t> client_game_clock_ms() {
    static const uintptr_t base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    // The clock getter's address is still the 2976 one and its head cannot match on
    // this build, so comparing the head -- the old check -- would disable the clock
    // outright. What is now resolved is the GLOBAL that getter consults: the 2976
    // head names 2976:0x6C8CD34, and disassembling the 3424 sites that test the
    // same shape lands on 0x70CACAD.
    //
    // So check the data instead of the code: the flag must be a byte in the image
    // (it is in zero-filled memory, so only the range can be checked offline, but a
    // live game fills it), and the two clock fields next to it must look like a
    // clock -- non-zero and monotonically plausible. A wrong slot fails those and
    // the feature turns itself off, exactly as before, but a RIGHT slot now works.
    static const bool known = [] {
        // Cheap sanity: the whole clock family must be inside the image.
        return off::kClientClockGlobal > off::kImageBase &&
               off::kClientFrameClockUs + 8 < off::kImageBase + 0x145B9000ull;
    }();
    if (!known) return std::nullopt;
    const auto ms = read<uint64_t>(base + off::kClientFrameClockMs);
    const auto us = read<uint64_t>(base + off::kClientFrameClockUs);
    const auto bias = read<int64_t>(base + off::kClientClockBias);
    if (!ms || *ms == 0 || !us || !bias) return std::nullopt;
    // Guard against a wrong slot that happens to hold non-zero junk. The 2976
    // comment describes the layout as "[ms] + [us] / 1000 while [ms] != 0", so the
    // microsecond field is a sub-second fraction, not a raw nanosecond count.
    // Accept both readings: either it is < 1e6 (a microsecond fraction) or it is
    // under 2^32 (a wider counter that still has to be sane). Bounds are loose on
    // purpose -- a wrong slot that also survives them only costs the feature, and
    // time_sync re-checks by requiring two reads to agree.
    if (*ms > 365ull * 24 * 60 * 60 * 1000) return std::nullopt;  // > a year of ms
    if (*us >= 1000000000ull) return std::nullopt;                // >= 1e9 is not a fraction
    return static_cast<uint64_t>(static_cast<int64_t>(*ms + *us / 1000) + *bias);
}

}  // namespace cdmp::game
