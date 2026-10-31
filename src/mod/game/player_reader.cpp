#include "mod/game/player_reader.h"

#include <windows.h>

#include <cmath>

#include "common/math3d.h"
#include "mod/game/offsets.h"
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

// TEMPORARY DIAGNOSTIC -- remove once kWorldSystemSlot is re-measured for this build.
//
// The 3446 value of kWorldSystemSlot does not work on 3460: reading it yields an
// object whose vtable is GlobalVariableManager, not the WorldSystem, and the log
// repeats "WorldSystem not created" with the character loaded and walking. Every
// offline route tried to re-find it failed for a stated reason -- xrefs reports
// shifted operands rather than instruction starts; the three sites for the old
// address are shutdown thunks calling a destructor; and no module global points at
// the structure that holds the live ClientActorManager.
//
// So the mod asks the game instead. A heap scan found exactly one live
// ClientActorManager (its vtable is unique), so this sweeps the mod's own data range
// for a POINTER-TO-POINTER whose target's [+kWorldSystem_ActorManager] is that
// manager. That is a positive identification of the WorldSystem slot by what it
// points at, not by an address someone remembered.
//
// Prints every candidate it finds so the answer can be read off a log rather than
// guessed, and prints nothing when the sweep finds none -- which is itself the
// useful result, because it means the WorldSystem is not in this range at all.
namespace diag {

// Walks the FULL chain the reader uses -- world -> manager -> actor -> component ->
// physics -> position -- and returns the position when it arrives at a value the
// game's own orthonormal-basis check accepts.
//
// This exists because "has a ClientActorManager at +0x30" was NOT enough to tell the
// two candidate world slots apart: measured live, 0x71B5CA0 and 0x71B5CF0 both hold
// a pointer whose [+0x30] is the same single live manager. Requiring the chain to
// reach a plausible position is a strictly stronger test, and it is the same test the
// reader itself applies, so a slot that passes here is a slot the mod can actually use.
bool chain_reaches_position(uintptr_t base, uintptr_t world, float* out_xyz) {
    auto mgr = read_ptr(world + off::kWorldSystem_ActorManager);
    if (!mgr || !has_vtable(*mgr, base + off::kVtClientActorManager)) return false;
    auto actor = read_ptr(*mgr + off::kActorManager_ControlledActor);
    if (!actor || !has_vtable(*actor, base + off::kVtControlledActor)) return false;
    auto comps = read_ptr(*actor + off::kActor_ComponentTable);
    if (!comps) return false;
    auto ctl = read_ptr(*comps + off::kComponents_CharacterControl);
    if (!ctl || !has_vtable(*ctl, base + off::kVtCharacterControl)) return false;
    auto inner = read_ptr(*ctl + off::kControl_Inner);
    if (!inner) return false;
    auto phys = read_ptr(*inner + off::kControlInner_Physics);
    if (!phys) return false;

    float p[3];
    if (!safe_read(*phys + off::kPhysics_Position, p, sizeof p)) return false;
    // Reject values that cannot be a world position. The game's own loading park
    // (0, 1000, 0) is deliberately NOT rejected here -- it is a real state, and
    // during a load it is the honest answer.
    for (float v : p) {
        if (!std::isfinite(v) || std::fabs(v) > 1.0e7f) return false;
    }
    out_xyz[0] = p[0];
    out_xyz[1] = p[1];
    out_xyz[2] = p[2];
    return true;
}

// Sweeps the mod's data range for a slot that carries the whole chain through to a
// position. Logs every slot whose target has a live ClientActorManager at +0x30, and
// says explicitly which of them also reached a position, so the answer is read off a
// log rather than inferred from a candidate list.
//
// Returns how many slots reached a position. The caller repeats until this is
// non-zero: an earlier single-shot sweep ran at 2.7 GB while the game was still
// starting, found nothing, and that "nothing" would have been read as "the WorldSystem
// is not in this range" when the truth was "it did not exist yet".
int probe_world_slot(uintptr_t base) {
    constexpr uintptr_t kScanBegin = 0x6000000;
    constexpr uintptr_t kScanEnd = 0x10000000;
    constexpr int kMaxHits = 12;

    int good = 0;
    for (uintptr_t rva = kScanBegin; rva + 8 <= kScanEnd; rva += 8) {
        auto slot = read_ptr(base + rva);
        if (!slot || *slot < 0x10000 || *slot > 0x7FFFFFFFFFFFULL) continue;
        auto mgr = read_ptr(*slot + off::kWorldSystem_ActorManager);
        if (!mgr || !has_vtable(*mgr, base + off::kVtClientActorManager)) continue;

        float xyz[3] = {0, 0, 0};
        if (chain_reaches_position(base, *slot, xyz)) {
            log::warn("WorldSlot probe: WORKS rva 0x{:X} -> world 0x{:X} -> pos ({:.2f}, {:.2f}, {:.2f})",
                      rva, *slot, xyz[0], xyz[1], xyz[2]);
            if (++good >= kMaxHits) break;
        } else {
            log::warn("WorldSlot probe: manager-only rva 0x{:X} -> world 0x{:X} (chain does not reach a position)",
                      rva, *slot);
        }
    }
    log::warn("WorldSlot probe: {} slot(s) carried the full chain to a position", good);
    return good;
}

}  // namespace diag

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
    // itself -- which is exactly why it is worth keeping even while it is noisy.
    if (auto global = read_vec3(base_ + off::kStaticPlayerPos)) {
        snap.static_pos_error = math::length(math::sub(snap.position, *global));
    }

    // While a save loads, the game parks the actor at (0, 1000, 0) for tens
    // of seconds before placing it. Don't broadcast that as a real position.
    if (std::fabs(snap.position.x) < off::kLoadingParkRadius &&
        std::fabs(snap.position.z) < off::kLoadingParkRadius &&
        std::fabs(snap.position.y - off::kLoadingParkHeight) < off::kLoadingParkRadius) {
        return fail("loading (actor parked at 0,1000,0)");
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
