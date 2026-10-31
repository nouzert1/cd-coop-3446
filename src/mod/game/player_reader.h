#pragma once
// Reads the local player's state from game memory (read-only). Re-resolves the
// whole pointer chain on every call and validates each hop by vtable, so it
// keeps working across loading screens and simply returns nullopt while the
// player is not in the world (title screen, loading).

#include <cstdint>
#include <optional>
#include <string>

#include "common/protocol.h"

namespace cdmp::game {

struct PlayerSnapshot {
    proto::Vec3 position;        // world space (chunk origin applied); Y is up
    proto::Vec3 local_position;  // physics position, relative to the map chunk
    proto::Vec3 chunk_origin;    // world = local + chunk_origin
    proto::Quat rotation;
    float health = 0.0f;         // NaN-free; 0/0 if stats could not be read
    float health_max = 0.0f;
    float stamina = 0.0f;
    float stamina_max = 0.0f;
    // Distance from `position` to the game's own world-position global -- the self-check
    // that compares two independent derivations. NEGATIVE MEANS NOT MEASURED, and that
    // distinction is load-bearing: kStaticPlayerPos is wrong on 3460 (it holds pointers),
    // so this check abstains on every sample. With a default of 0 the log printed
    // "check vs game global 0.00 m", which reads as perfect agreement and is the opposite
    // of what happened. A zero meaning "no data" must not look like a zero meaning
    // "verified".
    float static_pos_error = -1.0f;
};

class PlayerReader {
public:
    // Checks the exe build. If it is not the one our offsets are for, the
    // reader stays disabled for the whole session.
    bool init();
    bool enabled() const { return enabled_; }

    std::optional<PlayerSnapshot> read();

    // The player's ClientCharacterControlActorComponent (vtable-checked).
    std::optional<uintptr_t> character_control();

    // Why the last read() returned nullopt, for logging.
    const std::string& last_failure() const { return last_failure_; }

private:
    std::optional<uintptr_t> resolve_actor();
    void read_stats(uintptr_t components, PlayerSnapshot& out);
    std::nullopt_t fail(const char* why);

    bool enabled_ = false;
    uintptr_t base_ = 0;
    std::string last_failure_;
};

}  // namespace cdmp::game
