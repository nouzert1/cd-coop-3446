#pragma once
// Pure rules of the boss-safety feature (boss_safe.h explains why it exists).
//
// Kept as a header with no Windows, Steam or game dependency so the decisions
// that protect the host's quest can be unit-tested (tests/tests.cpp) instead of
// only being exercised in a live boss fight.

#include <cstdint>
#include <string>

namespace cdmp::net {

// An enemy whose maximum HP is at least this (x1000, the scale the mod uses for
// stats) is treated as a boss.
//
// The research (docs/research/pendiente-jefes.md section 1.3) measured every NPC
// in 58 packet captures at <= 220 max HP, which is 220000 on this scale (the mod
// reads stats as int64 value*1000: offsets.h, and local_capture.cpp's
// "200000 // 200 HP x1000"). So the threshold has to sit ABOVE 220000, or every
// monster would be taken for a boss and co-op damage would switch itself off.
// 500000 (500 HP) is more than double the toughest NPC ever measured and still
// far below a boss. A false positive is cheap anyway: the guest keeps doing
// damage, it only stops landing the killing blow.
inline constexpr int64_t kBossMaxHpX1000 = 500000;

inline bool is_boss_sized_hp(int64_t max_hp_x1000) {
    return max_hp_x1000 >= kBossMaxHpX1000;
}

// Is this stage name one of the boss families? The names are the game's own,
// taken from its .pastage/.paseq files, so this does not depend on any address
// in a particular build.
//
//   *_bossencounter_*   world encounters (34 stages)
//   cd_boss_*           story bosses (24)
//   cd_seq_quest_*boss* quest bosses (59)
//
// Rematch and boss-rush put the host in a different level entirely, which the
// guest's world does not have, so they count as boss stages too.
inline bool is_boss_stage_name(const std::string& name) {
    if (name.empty()) return false;
    auto has = [&](const char* needle) { return name.find(needle) != std::string::npos; };
    if (has("bossencounter")) return true;
    if (has("cd_boss_")) return true;
    if (has("cd_seq_quest_") && has("boss")) return true;
    if (has("bossrematch") || has("bossrush")) return true;
    return false;
}

}  // namespace cdmp::net
