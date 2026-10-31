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

// The record type of an actor load whose copy the enemy relay may carry.
//
// The relay reads the type from the load at +2. Historically only type 3 (person)
// was accepted, and the research (docs/research/pendiente-jefes.md line 67) says why
// the rest were left out: "El relevo solo copia el tipo 3. Si un jefe llega como tipo 4
// (personaje con nombre) o 5 (vehiculo: tanques, dragon, avion), hoy no se copia."
//
// TYPE 4 is now accepted, but ONLY for a boss -- the research's own prescription, twice:
//   line 400  "aceptar el tipo 4 solo si es jefe"
//   line 458  "copia de jefes de tipo 4 con la bandera de jefe"
// A named NON-boss character stays refused. Named characters are quest and scene actors,
// and the twin's safety rules (botin-invitado.md section 6) exclude exactly those: the twin
// is an actor the GUEST's own server spawns, so it must be an ordinary world variant.
//
// TYPE 5 stays refused (vehicles: tank, plane, dragon) until the vehicle branch is solved.
// It carries a known closing risk, 0x925F0E, that already cost a full diagnostic session
// (docs/DIAGNOSTICO-HANG.md). A type 5 closes the game; this is not caution for its own sake.
//
// TYPE 7 (a boss's weapons and breakable parts) is a different question: those are valid
// ATTACKERS in player_hits, not relayed copies of their own.
//
// `is_boss` is passed in rather than looked up here, so this stays a pure rule with no
// dependency on boss_safe.cpp's mutable state and can be unit-tested.
//
// WHO FILLS `is_boss`, since the rule is useless without it. There are exactly two sources,
// and on the guest the first one is the only one that can be right:
//
//   1. THE SENDER'S FLAG (enemy_relay.cpp:1933). v10's EnemySpawn carries kEnemySpawnFlagBoss,
//      set by the host from `origin == 3 || boss_is_boss(key)` at line 708. The guest calls
//      boss_note_max_hp(copy, kBossMaxHpX1000) on receipt -- a deliberate synthetic value, not
//      a measurement: it only has to clear the >= 500000 threshold, because kBossMaxHpX1000 is
//      a CLASSIFIER here, not a real HP. The host can see the stage that spawned the actor;
//      the guest cannot, which is the whole reason the flag travels.
//
//   2. THE HP FALLBACK (local_capture.cpp:552), from the VaryHP packet's hp_max -- the only
//      place the mod ever sees a real HP POOL. The research measured every NPC across 58
//      captures at <= 220 max HP, so >= 500 genuinely separates a stage boss from a monster.
//      On the guest this fallback is too late to matter for the FIRST blow on a copy, which is
//      why source 1 exists.
//
// Neither source ever LOWERS the flag (boss_safe.cpp, no path clears it), so a boss verdict is
// permanent for the session. That direction is deliberate: a wrong boss verdict costs the
// GUEST the cheat finisher on one enemy, while a boss killed outside its stage script costs
// the HOST a stuck quest. The asymmetry is the point.
inline bool is_relayable_record_type(uint32_t type, bool is_boss) {
    if (type == 3) return true;
    if (type == 4) return is_boss;
    return false;
}

}  // namespace cdmp::net
