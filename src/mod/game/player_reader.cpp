#include "mod/game/player_reader.h"

#include <windows.h>

#include <chrono>
#include <cmath>
#include <string>

#include "common/math3d.h"
#include "mod/game/offsets.h"
#include "mod/game/rtti.h"
#include "mod/game/safe_memory.h"
#include "mod/log.h"

namespace cdmp::game {
namespace off = build_3460;

namespace {

std::optional<proto::Vec3> read_vec3(uintptr_t addr) {
    float f[3];
    if (!safe_read(addr, f, sizeof f)) return std::nullopt;
    proto::Vec3 v{f[0], f[1], f[2]};
    if (!math::is_finite(v)) return std::nullopt;
    return v;
}

}  // namespace

bool PlayerReader::init() {
    base_ = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base_);
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base_ + dos->e_lfanew);
    enabled_ = base_ == off::kImageBase && nt->FileHeader.TimeDateStamp == off::kPeTimestamp;
    if (!enabled_) last_failure_ = "unsupported game build";
    return enabled_;
}

std::nullopt_t PlayerReader::fail(const char* why) {
    last_failure_ = why;
    return std::nullopt;
}

std::optional<uintptr_t> PlayerReader::resolve_actor() {
    auto world = read_ptr(base_ + off::kWorldSystemSlot);
    if (!world) return fail("WorldSystem not created");
    auto manager = read_ptr(*world + off::kWorldSystem_ActorManager);
    if (!manager || !has_vtable(*manager, base_ + off::kVtClientActorManager))
        return fail("ClientActorManager missing");
    auto actor = read_ptr(*manager + off::kActorManager_ControlledActor);
    if (!actor) return fail("no controlled actor (not in world)");
    if (!has_vtable(*actor, base_ + off::kVtControlledActor))
        return fail("controlled actor has unexpected type");
    return actor;
}


std::optional<uintptr_t> PlayerReader::character_control() {
    if (!enabled_) return fail("unsupported game build");
    auto actor = resolve_actor();
    if (!actor) return std::nullopt;
    auto components = read_ptr(*actor + off::kActor_ComponentTable);
    if (!components) return fail("component table missing");
    auto control = read_ptr(*components + off::kComponents_CharacterControl);
    if (!control || !has_vtable(*control, base_ + off::kVtCharacterControl))
        return fail("CharacterControl component missing");
    return control;
}

std::optional<PlayerSnapshot> PlayerReader::read() {
    if (!enabled_) return fail("unsupported game build");

    auto actor = resolve_actor();
    if (!actor) return std::nullopt;

    auto components = read_ptr(*actor + off::kActor_ComponentTable);
    if (!components) return fail("component table missing");
    auto control = read_ptr(*components + off::kComponents_CharacterControl);
    if (!control || !has_vtable(*control, base_ + off::kVtCharacterControl))
        return fail("CharacterControl component missing");
    auto inner = read_ptr(*control + off::kControl_Inner);
    if (!inner) return fail("control inner missing");

    // The position is INLINE in the inner object on this build, not behind the physics
    // pointer the older tables describe. Measured live and proved by motion: two reads
    // 15 s apart with the player walking moved it ~45 m. See offsets_3460.h
    // (kControlInner_Position) for the reading and for why the old pointer route is
    // kept but unused -- chasing it yields a normalised direction vector, which looks
    // like a result and is not one.
    auto local = read_vec3(*inner + off::kControlInner_Position);
    if (!local) return fail("position unreadable");

    // kPhysics_Position/axis reads are gone with the pointer route. The rotation now
    // comes from the direction triple that sits immediately after the position; it is
    // three floats, not an orthonormal basis, so it is converted as a forward vector.
    auto facing = read_vec3(*inner + off::kControlInner_Position + 12);

    PlayerSnapshot snap;
    snap.local_position = *local;

    // The chunk origin is added by the game's own world-position global on this build:
    // the inline value is already world space (Y is an elevation in the hundreds of
    // metres, X and Z are map coordinates), so no origin is added here. kChunkOrigin is
    // still suspect -- see offsets_3460.h -- and adding it would double-count.
    snap.position = *local;
    snap.chunk_origin = proto::Vec3{0.0f, 0.0f, 0.0f};

    // No basis is available from this field, so the puppet is drawn unrotated rather
    // than not drawn. That is the same fallback the previous code used when the basis
    // failed its orthonormality check.
    snap.rotation = math::Quat{};
    (void)facing;

    // The game keeps its own world-space copy; a large mismatch means our
    // chunk-origin math or chain is off (it lags by a frame, so allow some).
    //
    // This is the self-check that caught the wrong globals on this build: it reported
    // 46245.31 m, which is what sent the port back to re-measure. It compares two
    // independent derivations, so it does not depend on any external tool agreeing with
    // itself -- which is why it is worth keeping.
    //
    // kStaticPlayerPos is still the 3446 value and is still WRONG on this build. Its
    // bytes are pointers, so a read that succeeds yields a meaningless distance and one
    // that fails yields nothing; either way the number is not a measurement. It is
    // computed only when BOTH sides are finite and non-zero, because the log showed
    // `check vs game global inf m` -- a division of two zeroes, which reads as a
    // catastrophic error when it is merely an absent one. Reporting an unknown as a
    // number, even a spectacular number, is worse than reporting it as unknown.
    if (auto global = read_vec3(base_ + off::kStaticPlayerPos)) {
        const float d = math::length(math::sub(snap.position, *global));
        if (std::isfinite(d) && math::length(*global) > 0.0f) snap.static_pos_error = d;
    }

    // While a save loads, the game parks the actor at the world origin for tens of
    // seconds before placing it. Don't broadcast that as a real position: the far end
    // creates the character wherever it is told, and the origin is not a place.
    //
    // The parked VALUE moved with the same change that moved the read itself. Up to
    // 3446 the position came through the physics pointer and the parked value was
    // (0, 1000, 0); on 3460 the inline field at kControlInner_Position reads (0, 0, 0).
    // This guard kept testing the old height, so it stopped matching while still
    // looking correct, and the mod broadcast (0,0,0) as a real position.
    //
    // Cost: measured, not hypothetical. In the 2-PC test of 2026-10-31 the guest's
    // position arrived as (0,0,0) for 216 consecutive state updates while their world
    // loaded, the host spawned that character, and the host's game died ~230 ms later.
    // The guest saw it standing in the sky -- (0,0,0) is above ground level, which on
    // this map sits in the hundreds of metres. Both crashes that day have this as the
    // only common anomaly. See docs/research/crash-2026-10-31-spawn*.txt.
    //
    // Accept both parked forms rather than replacing one guess with another: which one
    // the game uses is a property of the build, not of this code.
    const bool near_xz = std::fabs(snap.position.x) < off::kLoadingParkRadius &&
                         std::fabs(snap.position.z) < off::kLoadingParkRadius;
    const bool parked_at_origin = near_xz && std::fabs(snap.position.y) < off::kLoadingParkRadius;
    const bool parked_at_height =
        near_xz && std::fabs(snap.position.y - off::kLoadingParkHeight) < off::kLoadingParkRadius;
    if (parked_at_origin || parked_at_height) {
        return fail("loading (actor parked at the origin)");
    }

    read_stats(*components, snap);
    last_failure_.clear();
    return snap;
}

void PlayerReader::read_stats(uintptr_t components, PlayerSnapshot& out) {
    auto status = read_ptr(components + off::kComponents_Status);
    if (!status || !has_vtable(*status, base_ + off::kVtStatusComponent)) return;
    auto container = read_ptr(*status + off::kStatus_StatContainer);
    if (!container) return;
    auto entries = read_ptr(*container + off::kStatContainer_Entries);
    auto count = game::read<uint32_t>(*container + off::kStatContainer_Count);
    if (!entries || !count || *count > off::kMaxStatEntries) return;

    // Look stats up by id: the entry order changes between patches.
    for (uint32_t i = 0; i < *count; ++i) {
        const uintptr_t e = *entries + static_cast<uintptr_t>(i) * off::kStatEntry_Size;
        auto id = game::read<uint64_t>(e + off::kStatEntry_Id);
        if (!id) continue;
        float* cur_out = nullptr;
        float* max_out = nullptr;
        if (*id == off::kStatId_Health) {
            cur_out = &out.health;
            max_out = &out.health_max;
        } else if (*id == off::kStatId_Stamina) {
            cur_out = &out.stamina;
            max_out = &out.stamina_max;
        } else {
            continue;
        }
        auto cur = game::read<int64_t>(e + off::kStatEntry_Current);
        auto max = game::read<int64_t>(e + off::kStatEntry_Max);
        if (!cur || !max || *max <= 0 || *cur < 0 || *cur > *max) continue;
        *cur_out = static_cast<float>(*cur) / 1000.0f;
        *max_out = static_cast<float>(*max) / 1000.0f;
    }
}

}  // namespace cdmp::game
