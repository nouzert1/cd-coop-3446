#pragma once
// Boss safety (docs/research/pendiente-jefes.md, plan J1).
//
// WHY THIS EXISTS
// A boss fight in this game is not a monster with a big health bar: it is a
// scripted "stage" (a .pastage graph plus a .paseq timeline) that the HOST's
// client drives. The stage decides everything that matters -- the boss's phases,
// the entrance and phase cinematics, the arena barrier, and the `set_battleEnd`
// that closes the fight. The boss itself only exists in the host's world.
//
// That makes the guest's normal lethal blow dangerous. Today a lethal blow runs
// `VaryStatCheatReq` down to 1 HP and then, if the enemy is still fighting,
// `KillCheatReq`. Against a stage boss that kills it OUTSIDE the script:
//
//   - no `BossPhase`, so the next phase never starts;
//   - no final cinematic;
//   - no `set_battleEnd`, so the arena barrier stays up and the HOST'S QUEST IS
//     STUCK. The host cannot fix it without reloading.
//
// The same applies to `DieByRunOutFatalReq` on a boss that is in its "fatal"
// (groggy) state: it skips the finishing sequence the stage is waiting for.
//
// WHAT THIS DOES
// When the target is considered a boss, `guest_hits` stops using the cheat kill
// and the fatal finisher, and stops staggering. Damage still applies, so the
// guest really does help -- the HOST always lands the killing blow, which is
// what drives the stage's own script.
//
// HOW A BOSS IS RECOGNISED
// Not by guessing: by the signals the research identified as reliable.
//   1. `cutscene_active()` -- the host told us its client is in a stage
//      cinematic (SetAvoidByCutSceneAck). Nothing of ours lands during one.
//   2. `note_boss_stage()` -- a stage whose name is a boss stage. The names come
//      from the game's own stage files, so this is data, not a code offset.
//   3. `note_tanky()` -- a fallback for bosses we could not name: an enemy whose
//      maximum HP is far above any normal monster. The research measured every
//      NPC in 58 captures at <= 220 max HP, so the threshold is safe.
//
// Every one of these is a *widening* of caution, never a permission: with all
// three silent, behaviour is exactly the old behaviour.

#include <cstdint>
#include <string>

namespace cdmp::net {

// [coop] boss_safe (default on). Off restores the old lethal behaviour exactly.
void boss_set_safe_mode(bool on);
bool boss_safe_mode();

// The stagger is disabled on bosses: an injected reaction can put a boss into a
// state its phase AI does not expect (research 0.4c).
void boss_set_no_stagger(bool on);

// Host, from the sniffer: SetAvoidByCutSceneAck (2561). flag=1 while the host's
// client is inside a stage cinematic. Cheap and exact.
void boss_note_cutscene(bool active);

// True while the host is in a stage cinematic. The guest must not land damage,
// and the host must not land any either, during one.
bool boss_cutscene_active();

// Host, from the sniffer: the hash the game carries at load+0x1043 identifies
// the stage that spawned an actor. Boss stages are recognised by their name
// (cd_boss_*, cd_seq_quest_*_boss*, *_bossencounter_*), which the research
// lists as the three boss families.
//
// `hash` is the spawn-origin hash. `name` is the stage name when it is known
// (empty is fine: the hash alone still matches if it was registered before).
void boss_note_spawn_origin(uint32_t hash, const std::string& name);

// Forget the stage names learned from the current world (a new world shows
// different stages). The built-in boss-family rules stay.
void boss_reset();

// Is this origin hash a boss stage? False when nothing is known about it, which
// keeps unknown enemies behaving exactly as before.
bool boss_origin_is_boss(uint32_t hash);

// Fallback, from the host: an enemy whose maximum HP is far above any normal
// monster. `max_hp_x1000` is the scale the mod uses elsewhere (value * 1000).
// Returns true once the enemy has been seen with a boss-sized pool.
bool boss_note_max_hp(uint32_t enemy_key, int64_t max_hp_x1000);

// Is this enemy already known to be a boss? False when unknown.
bool boss_is_boss(uint32_t enemy_key);

// "Boss fight in progress" state, for the overlay: true while a boss is known
// to be active (or was seen recently), with the guest's HP reading of it.
struct BossHud {
    bool active = false;
    std::string name;
    float hp = 0.0f;
    float hp_max = 0.0f;
    bool cutscene = false;
};
void boss_note_hp(uint32_t enemy_key, float hp, float hp_max);
BossHud boss_hud();

}  // namespace cdmp::net
