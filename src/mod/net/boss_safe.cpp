#include "mod/net/boss_safe.h"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "mod/log.h"
#include "mod/net/boss_rules.h"

namespace cdmp::net {
namespace {

std::atomic<bool> g_safe{true};
std::atomic<bool> g_no_stagger{true};
std::atomic<bool> g_cutscene{false};
std::atomic<uint64_t> g_cutscene_since{0};
std::atomic<uint64_t> g_boss_seen_ms{0};

std::mutex g_mutex;
// Spawn-origin hashes known to be boss stages, learned from the stage names the
// game hands us. This is game DATA (the .pastage/.paseq names), so it survives a
// code patch in a way an RVA does not.
std::unordered_set<uint32_t> g_boss_origins;
// Enemies seen with a boss-sized HP pool, and their current reading for the HUD.
struct BossInfo {
    std::string name;
    float hp = 0.0f;
    float hp_max = 0.0f;
};
std::unordered_map<uint32_t, BossInfo> g_bosses;

// From the research (pendiente-jefes.md section 1.1 / 2.2): three families of
// boss stage, by name. The rules themselves live in boss_rules.h so they can be
// unit-tested.
bool name_is_boss_stage(const std::string& name) { return is_boss_stage_name(name); }

uint64_t now_ms() { return GetTickCount64(); }

}  // namespace

void boss_set_safe_mode(bool on) {
    g_safe = on;
    log::info("Boss: safe mode {}", on ? "ON (the host always lands the killing blow)" : "OFF");
}

bool boss_safe_mode() { return g_safe; }

void boss_set_no_stagger(bool on) { g_no_stagger = on; }

void boss_note_cutscene(bool active) {
    const bool was = g_cutscene.exchange(active);
    if (was == active) return;
    if (active) {
        g_cutscene_since = now_ms();
        log::info("Boss: the host entered a stage cinematic; no hits either way until it ends");
    } else {
        log::info("Boss: the host left the cinematic");
    }
}

bool boss_cutscene_active() { return g_cutscene; }

void boss_note_spawn_origin(uint32_t hash, const std::string& name) {
    if (hash == 0) return;
    if (!name_is_boss_stage(name)) return;
    std::lock_guard lock(g_mutex);
    if (g_boss_origins.insert(hash).second) {
        log::info("Boss: stage '{}' (0x{:08X}) is a boss stage", name, hash);
    }
}

void boss_reset() {
    std::lock_guard lock(g_mutex);
    g_boss_origins.clear();
    g_bosses.clear();
    g_boss_seen_ms = 0;
}

bool boss_origin_is_boss(uint32_t hash) {
    if (hash == 0) return false;
    std::lock_guard lock(g_mutex);
    return g_boss_origins.count(hash) != 0;
}

bool boss_note_max_hp(uint32_t enemy_key, int64_t max_hp_x1000) {
    if (enemy_key == 0 || max_hp_x1000 <= 0) return false;
    if (!is_boss_sized_hp(max_hp_x1000)) return false;
    std::lock_guard lock(g_mutex);
    auto [it, fresh] = g_bosses.try_emplace(enemy_key);
    if (fresh) {
        log::info("Boss: enemy 0x{:08X} has {}.{:03d} max HP: treated as a boss",
                  enemy_key, static_cast<long long>(max_hp_x1000 / 1000),
                  static_cast<int>(max_hp_x1000 % 1000));
    }
    g_boss_seen_ms = now_ms();
    return true;
}

bool boss_is_boss(uint32_t enemy_key) {
    if (enemy_key == 0) return false;
    std::lock_guard lock(g_mutex);
    return g_bosses.count(enemy_key) != 0;
}

void boss_note_hp(uint32_t enemy_key, float hp, float hp_max) {
    if (enemy_key == 0) return;
    std::lock_guard lock(g_mutex);
    auto it = g_bosses.find(enemy_key);
    if (it == g_bosses.end()) return;
    it->second.hp = hp;
    if (hp_max > 0) it->second.hp_max = hp_max;
    g_boss_seen_ms = now_ms();
}

BossHud boss_hud() {
    BossHud out;
    out.cutscene = g_cutscene.load();
    std::lock_guard lock(g_mutex);
    const uint64_t seen = g_boss_seen_ms.load();
    // Keep showing the bar for a while after the last reading: a boss that stops
    // being updated (cinematic, phase change) should not make the bar flicker.
    if (seen != 0 && now_ms() - seen < 15000) out.active = true;
    bool any = false;
    float lowest_frac = 2.0f;
    for (const auto& [key, info] : g_bosses) {
        if (info.hp_max <= 0) continue;
        // Several bosses at once (six stages have two): show the one closest to
        // dead, which is the one the fight is about.
        const float frac = info.hp / info.hp_max;
        if (!any || frac < lowest_frac) {
            any = true;
            lowest_frac = frac;
            out.name = info.name;
            out.hp = info.hp;
            out.hp_max = info.hp_max;
        }
    }
    if (!any) out.active = false;
    return out;
}

}  // namespace cdmp::net
