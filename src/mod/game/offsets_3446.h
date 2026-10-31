#pragma once
// Addresses for CrimsonDesert.exe 1.0.0.3446.
//
// Every ADDRESS below was measured on a live 3446 process with cdmp_probe; see
// docs/PORT-3446-live.txt for the raw output behind each number.
//
// This header builds on build_3424 rather than restating it. A game patch moves
// code and static data; it does not renumber internal protocol opcodes or change
// the layout of a struct the mod reads field by field. Those live in the base
// namespace and are correct as they stand. Only what a patch actually moves is
// overridden here, which keeps the diff between two builds readable -- that diff
// is the thing a future port needs to see.
//
// How 3446 arrived: Steam auto-updated the game mid-session from 1.0.0.3424
// (PE 0x6AE387F2, 336,264,088 bytes) to 1.0.0.3446 (PE 0x6AE46DD0, 332,786,072
// bytes). Every address in build_3424 became wrong at once. verify-port.ps1 named
// all 24 of them, and nothing was corrupted, because the guards compare this
// timestamp before touching memory: they refused and the mod went inert.
//
// Method, per kind of value:
//   * data globals -- re-scan the LIVE image with the ORIGINAL full signatures.
//     The 3424 *sites* moved as well as their targets, so re-decoding the old site
//     numbers yields mid-instruction garbage; the signature must be re-found, then
//     decoded.
//   * the clock flag -- decode the disp32 of `cmp byte [rip+d],0` and see which
//     target independent sites agree on. Four agreed on 3446, as on 3424.
//   * the Troc range -- run the mod's OWN walk (probe `troc`) and bracket it from
//     both sides, because here a shift would have been silently wrong.

#include "mod/game/offsets_3424.h"

// Re-export the values a patch does not move.
//
// A game patch moves code and static data; it does not renumber internal protocol
// opcodes or re-lay a struct the mod reads field by field. Those stay correct, so
// they are named here explicitly rather than restated -- restating 88 struct
// offsets would create 88 chances to typo one for no benefit.
//
// Explicit `using` declarations rather than `using namespace build_3424`: a
// directive would make every overridden name below ambiguous between the two
// namespaces, whereas a declaration is simply shadowed by a later declaration of
// the same name in this namespace. If a name below is ever promoted (because a
// future patch moves it), delete it from this list and the compiler will point at
// the new definition instead of silently preferring the old one.
namespace cdmp::game::build_3446 {

using build_3424::RelayedAck;
// ---- kActionLayerAdvance: MEASURED. kActionLayersAdvance: head was ALWAYS wrong --
//
// MEASURED LIVE 2026-10-30 (single-PC echo, game running, world loaded):
//
//     WRN Puppet: PointClimb::Enter not recognised; wall climbs will freeze
//     WRN Enemy copies disabled: their crash guards could not be installed
//
// puppet_install_layer_guards() (remote_puppet.cpp:2489) requires BOTH heads to match.
// They did not, so mod.cpp:771 switched enemy copies OFF -- which is why a whole session
// with the echo peer produced no EnemyRelay line, no WOULD COPY and no copy of any kind.
// The enemy relay has not been running, and the only sign was one WRN easy to read past.
//
// kActionLayerAdvance, 3424 0x1F63F70 -> 3446 0x2148D50, found by signature and CONFIRMED
// by the body rather than by the bytes matching: 3446@0x2148D50 opens with
// `push rdi / sub rsp,0x80 / vmovaps [rax-0x28],xmm7 / vxorps xmm7,xmm7,xmm7 /
// vcomiss xmm7,xmm3 / mov rdi,rcx` -- float parameters, float comparisons, rcx as `this`.
// That is an advance driven by a delta. Confirmation by behaviour, not by a hit.
//
// THE HEAD WAS ALREADY RIGHT; THE ADDRESS WAS WRONG. Measured at 3446@0x2148D50:
//   48 8B C4 57 48 81 EC 80 00 00 00 C5 F8 29 78 D8
// which is kActionLayerAdvanceHead below, byte for byte. On 3424 the same head does NOT
// appear at 0x1F63F70 (that reads 18 B9 02 EB 05 ...), so on 3424 the head was wrong there
// -- but on 3446 the head identifies the function correctly and only the address had been
// left pointing at the 3424 value. Keeping this head is what makes the guard meaningful.
inline constexpr uintptr_t kActionLayerAdvance = 0x2148D50;
inline constexpr uint8_t kActionLayerAdvanceHead[] = {0x48, 0x8B, 0xC4, 0x57, 0x48, 0x81, 0xEC, 0x80,
                                                      0x00, 0x00, 0x00, 0xC5, 0xF8, 0x29, 0x78, 0xD8};

// THE HEAD RECORDED HERE WAS WRONG IN *BOTH* BUILDS. Measured, not inferred:
//
//   0x1F63F70 (3424) reads  18 B9 02 EB 05 E8 86 17 B9 02 ...   not the head below
//   0x2329700 (3424) reads  74 51 4C 89 3F 44 38 3E 74 32 ...   not the head below
//   and the kActionLayersAdvance head bytes do not occur ANYWHERE in the 3424 image
//   (scan: 0 matches), so it never described any function in that build either.
//
// A guard whose head is authored from the same wrong address as its target agrees with
// itself and passes for as long as nobody re-measures. That is exactly what happened to
// kServerOtherEquipWriter in round 20 -- the head had been written from the wrong address,
// so the check confirmed the error instead of catching it. This is the second instance.
//
// The consequence here is not a crash, it is a SILENTLY DEAD FEATURE: the relay never
// armed, and every session that was supposed to exercise enemy copies exercised nothing.
//
// Both stay 0. 0 makes puppet_install_layer_guards() return false, which keeps enemy copies
// off -- bad, but honest and fail-closed. A guessed address would install a mid-hook over
// unrelated code, and the failure would then be a crash rather than a disabled feature.
//
// TO FINISH: RESOLVED BELOW. Both sites are now measured; see kActionLayersAdvance.

// ---- kActionLayersAdvance: MEASURED AND PROVEN, 3424 0x2329700 -> 3446 0x232A8B0 -----
//
// The old head above is meaningless -- those bytes are in neither build. The site is real,
// the ADDRESS was right on 3424 all along, and only the 3446 value was missing.
//
// HOW IT WAS FIXED, because the method is the point and it is the one that has worked every
// time this port got an address right:
//
// kPending is byte-for-byte IDENTICAL between the two builds -- measured, 32 bytes from
// 0x2329D60 (3424) and 0x232AF10 (3446) agree exactly. That fixes the shift for this region
// at 0x11B0, and it fixes it from code that is PROVEN to be the same code, not from two
// addresses that merely look related. Applying it: 0x2329700 + 0x11B0 = 0x232A8B0.
//
// Then confirmed by 64 bytes of surrounding context, 20 before the hook and 44 after:
//
//   3424 0x23296E0: ... 48 8B D1 E8 6F 68 02 00 48 8B B5 90 00 00 00 48 85 F6 74 56
//                    44 38 3E 74 51 4C 89 3F 44 38 3E 74 32 48 C7 C3 FF FF FF FF 48 FF
//                    C3 44 38 3C 1E 75 F7 8B CB E8 6F 68 2D
//   3446 0x232A890: ... 48 8B D1 E8 6F 68 02 00 48 8B B5 90 00 00 00 48 85 F6 74 56
//                    44 38 3E 74 51 4C 89 3F 44 38 3E 74 32 48 C7 C3 FF FF FF FF 48 FF
//                    C3 44 38 3C 1E 75 F7 8B CB E8 6F 4B 2D
//
// 63 of the 64 bytes are identical. The one that differs is the displacement of a trailing
// `call rel32`, which MUST differ when the callee moved -- so it is evidence FOR the match,
// not against it. The target goes from exe+0x...15A540 (3424) to exe+0x...15E540 (3446).
//
// This is what "confirm by behaviour" means in practice: not that the bytes at the address
// look similar, but that the surrounding code is the same code and the only differences are
// the ones a rebuild necessarily produces.
//
// The head is written from the 3446 bytes at this address, so the guard now checks the
// function it is about to hook. Both heads being wrong before is why the relay never armed.
inline constexpr uintptr_t kActionLayersAdvance = 0x232A8B0;
inline constexpr uint8_t kActionLayersAdvanceHead[] = {0x74, 0x51, 0x4C, 0x89, 0x3F, 0x44, 0x38, 0x3E,
                                                       0x74, 0x32, 0x48, 0xC7, 0xC3, 0xFF, 0xFF, 0xFF};
using build_3424::kActorManager_ControlledActor;
using build_3424::kActor_ComponentTable;
using build_3424::kActor_Key;
using build_3424::kActor_OwnerUser;
using build_3424::kCameraBlockSentinelValue;
using build_3424::kCameraBlock_Forward;
using build_3424::kCameraBlock_Position;
using build_3424::kCameraBlock_Projection;
using build_3424::kCameraBlock_Sentinel;
using build_3424::kCameraBlock_View;
using build_3424::kCamera_Block;
using build_3424::kClientClockHead;
using build_3424::kComponents_CharacterControl;
using build_3424::kComponents_Status;
using build_3424::kControlInner_Physics;
using build_3424::kControl_Inner;
using build_3424::kControl_Layer0;
using build_3424::kControl_MoveController;
using build_3424::kControl_WallData;
using build_3424::kCoopPinId;
using build_3424::kFieldTimeClient;
using build_3424::kHookArgSizeStackOffset;
using build_3424::kLayer_Chart;
using build_3424::kLayer_Playback;
using build_3424::kLoadKindMount;
using build_3424::kLoadPositionFromEnd;
using build_3424::kLoadRotationFromEnd;
using build_3424::kLoadingParkHeight;
using build_3424::kLoadingParkRadius;
using build_3424::kMaxStatEntries;
using build_3424::kMethod_Actor;
using build_3424::kMinimapIconCompanion;
using build_3424::kMinimapIconOutlinedArrow;
using build_3424::kMinimapIconPlayerArrow;
using build_3424::kMoveController_Method;
using build_3424::kMoveController_WallUp;
using build_3424::kMoveMethodWallUp;
using build_3424::kOpActorLoadDataAck;
using build_3424::kOpChangeDockingSocketByFrameEventAck;
using build_3424::kOpCreateOrChangePinMarkerAck;
using build_3424::kOpMoveActorAck;
using build_3424::kOpMoveActorReq;
using build_3424::kOpOtherEquipItemAck;
using build_3424::kOpOtherUnequipItemAck;
using build_3424::kOpRemoteCatchResultAck;
using build_3424::kOpRemoveActorAck;
using build_3424::kOpRemovePinMarkerAck;
using build_3424::kOpRotateActorAck;
using build_3424::kOpRotateActorReq;
using build_3424::kOpSetFieldTimeAck;
using build_3424::kOpSetFieldTimeReq;
using build_3424::kOpStartActionAck;
using build_3424::kOpStartActionReq;
using build_3424::kOpUnequipItemAck;
using build_3424::kOpUpdateOnDemandGimmickAck;
using build_3424::kOpUpdateWallUpDataAck;
using build_3424::kPhysics_AxisX;
using build_3424::kPhysics_AxisY;
using build_3424::kPhysics_AxisZ;
using build_3424::kPhysics_Position;
using build_3424::kPinColourCount;
using build_3424::kPinGroupNormal;
using build_3424::kPinShapeCount;
using build_3424::kPointClimbEnter;
using build_3424::kPointClimbEnterHead;
using build_3424::kRelayedAcks;
using build_3424::kRemoteCatchSceneId;
using build_3424::kRideEnterHead;
using build_3424::kRideOffEnter;
using build_3424::kRideOnEnter;
using build_3424::kServerActor_Key;using build_3424::kServerDockingWriter;
using build_3424::kServerDockingWriterHead;
using build_3424::kStatContainer_Count;
using build_3424::kStatContainer_Entries;
using build_3424::kStatEntry_Current;
using build_3424::kStatEntry_Id;
using build_3424::kStatEntry_Max;
using build_3424::kStatEntry_Size;
using build_3424::kStatId_Health;
using build_3424::kStatId_Stamina;
using build_3424::kStatus_StatContainer;
using build_3424::kTroc_Kind;
using build_3424::kTroc_Opcode;
using build_3424::kVtCamera;
using build_3424::kVtPhysicsObject;
using build_3424::kWorldSystem_ActorManager;

// ---- build identity -------------------------------------------------------
inline constexpr uint32_t kPeTimestamp = 0x6AE46DD0;  // 3424:0x6AE387F2, 2976:0x6AB28F00
inline constexpr uintptr_t kImageBase = 0x140000000;  // fixed, no ASLR

// SizeOfImage from the PE optional header: the mapped extent of the module, and so
// the bound for "is this address even inside the game?".
//
// This is a PER-BUILD value, not a constant, which is easy to miss because it looks
// like one -- and it shrank on this patch. 3424 was 0x145B9000; 3446 is 0x14268000.
// A guard still using the old number keeps passing, because every address it bounds
// sits far below both. But a bound that is too large silently accepts an address
// outside the image, which is precisely what the bound exists to prevent.
inline constexpr uintptr_t kImageSize = 0x14268000;  // 3424:0x145B9000

// ---- static globals (RVAs) ------------------------------------------------
// All resolve into .bss (the zero-filled part of .idata), i.e. real runtime slots
// that read as zero on disk -- which is why they can only be confirmed live.
//
// The 3424 -> 3446 delta is again NOT one constant:
//   WorldSystem +0x2FF0   Camera +0x2FF8   StaticPos +0x3010
//   ChunkOrigin +0x2FDB   clock flag +0x1000
// The clock flag is a different region entirely. Applying the WorldSystem delta
// to it would miss it by 0x1FF0. All of these were measured, not interpolated:
// the game was running, so there was no reason to accept an approximation.

// Confirmed twice over: two independent upstream signatures (world_system_ref
// from CrimsonDesertTelemetry, world_system_ref_p3 from CrimsonDesertTools) both
// decode here, and it reads back as a non-null heap pointer.
inline constexpr uintptr_t kWorldSystemSlot = 0x71B1A40;  // 3424:0x71AEA50
inline constexpr uintptr_t kCameraSlot = 0x70CDEA8;       // 3424:0x70CAEB0
inline constexpr uintptr_t kStaticPlayerPos = 0x71C0C20;  // 3424:0x71BDC10

// Chunk origin / worldOffset Vec4, subtracted from the physics position to get
// world coordinates. Read exactly as the game does it:
//   vsubps xmm0, xmm0, [0x14719DCA0]
// It is 16-byte aligned, which a Vec4 must be. An earlier arithmetic slip put the
// candidate at 0x719DC8B (align 11); the disassembly is what caught it, and this
// is the one value in this file that a formula got wrong before a read fixed it.
inline constexpr uintptr_t kChunkOrigin = 0x719DCA0;  // 3424:0x719ACB0

// ---- client clock ---------------------------------------------------------
// RESOLVED, not inferred. The flag is the global four independent
// `cmp byte [rip+d], 0` sites agree on:
//   exe+0x561BB5, exe+0x2F0B197, exe+0x15F5550, exe+0x2E442A9
// Confirmed live: it holds 1 and is stable across reads.
//
// The two fields below it are no longer assumed either. On 3424 they were carried
// over from the 2976 struct layout and could not be checked, because the region is
// zero-fill and nothing on disk distinguishes one slot from another. On 3446 the
// game was running, so they were read directly:
//   flag+0x3C advanced 134323 -> 135411 -> 136500 -> ... -> 141902 over 1.947 s,
//   a steady ~3892 units/s: a real advancing counter.
//   flag+0x34 reads non-zero.
// This is the first build on which those two slots have been confirmed at all.
//
// Do NOT "fix" the spacing to 8-byte alignment. The 2976 struct put them at
// flag+0x34 and flag+0x3C -- multiples of 4, never of 8 -- so an alignment
// assertion moves them onto the wrong slots and then reports success.
inline constexpr uintptr_t kClientClockGlobal = 0x70CDCAD;   // 3424:0x70CACAD
inline constexpr uintptr_t kClientFrameClockMs = 0x70CDCE1;  // = flag + 0x34
inline constexpr uintptr_t kClientFrameClockUs = 0x70CDCE9;  // = flag + 0x3C
// Not re-resolved for 3446: the code guard that uses it fails closed and only
// disables time sync.
inline constexpr uintptr_t kClientClock = 0x1416B80;

// ---- vtables the mod validates against ------------------------------------
// MEASURED on the live 3446 game, each by RTTI name and each with exactly ONE
// match, so there is no ambiguity about which is meant:
//   probe vtables ".?AVClientActorManager@pa@@"          -> exe+0x5939CD8
//   probe vtables ".?AVClientChildOnlyInGameActor@pa@@"  -> exe+0x5907C90
//
// Why this mattered: `has_vtable(manager, base + kVtClientActorManager)` is how
// player_reader decides the WorldSystem's ActorManager is real before touching it.
// With the stale 3424 address the pointer still resolved to a genuine
// .?AVClientActorManager@pa@@ object -- the field offset 0x30 was correct all
// along -- but its vtable is at a different address now, so the comparison failed
// and the mod reported "ClientActorManager missing". Every local-player feature
// then reported unavailable, and the HUD read exactly like a broken mod rather
// than a stale constant.
//
// A vtable is a data address, so unlike the code addresses there is no prologue
// to check; the guard is the RTTI identity of the object being validated, which is
// what makes a wrong value fail closed rather than read something unrelated.
inline constexpr uintptr_t kVtClientActorManager = 0x5939CD8;  // 3424:0x5937C48
inline constexpr uintptr_t kVtControlledActor = 0x5907C90;     // 3424:0x5905BE0
inline constexpr uintptr_t kVtCharacterControl = 0x59388D0;    // 3424:0x5936838
inline constexpr uintptr_t kVtStatusComponent = 0x590F6E0;     // 3424:0x590D630
// ---- kFieldTimeClient: MEASURED WRONG on 3446 (2026-10-30) -----------------
//
// SETTLED. This is no longer "unverified because the feature never ran" -- it was measured
// live with the world loaded, and the block is zero.
//
// The earlier note here argued the opposite: that `Config: time sync off` in every session
// meant own_time() had never run, so nothing had ever read this address and no evidence
// either way existed. That reasoning was sound as far as it went, but it left the item
// unresolved when it did not have to be. The address can be tested WITHOUT the feature
// being on: if the game writes FieldTime here, the bytes are non-zero whether or not the mod
// reads them.
//
// Measurements (pid 37868, world loaded, character had moved):
//
//   exe+0x6EB2AD8   kFieldTimeClient    32 bytes of 0x00
//   exe+0x71C0C20   kStaticPlayerPos    -10141.82, 607.67, -4091.08
//   exe+0x70CDCAD   kClientClockGlobal  1
//
// The control is what makes this conclusive. check-fieldtime.ps1 now reads kStaticPlayerPos
// in the same run and refuses to call a zero block meaningful unless the position is real --
// otherwise "zero" cannot be told apart from "still in the menu", and those two lead to
// opposite actions. With the position valid and a world-space coordinate set, a global this
// code is supposed to be writing being all zero means the address moved.
//
// CONSEQUENCE TODAY: none. own_time() is the only reader and [coop] time_sync defaults to 0
// (config.cpp:197), so a wrong address here has never been used and cannot have caused
// anything the user has seen. Leaving it wrong costs the time sync feature, which is off.
//
// It stays at the 3424 value rather than 0, because unlike the action-layer sites there is
// no guard that fails closed on a wrong address here -- there is simply no reader. Setting 0
// would look like a deliberate "unavailable" marker and would be a lie about what is known.
// This is recorded as WRONG so the next person does not read it as merely unverified.
//
// TO FIX: find who writes the world time on 3446 and re-measure. Do NOT guess an address:
// a global read directly by base+offset, with no xref and no stored pointer, cannot be
// validated by reading the file.
//
// What was tried and did not work, recorded so it is not repeated:
//   * xrefs on 0x6EB2AD0-0x6EB2B00 -- on 3424 these land on exe+0x2ABFA9 and
//     exe+0x2ABF86/87/8D, but the surrounding function is the logger's name-list setup
//     (its `lea` targets a zero-filled registration table, the same shape at exe+0x2ABF83
//     in both builds, pointing at a different table each time). Those xrefs are the
//     logger, NOT the field time. Reading them as field-time writers sends the port off
//     after the wrong function.
//   * scanning the region live for a timestamp -- the .bss in that range holds runtime
//     pointers and flags (vtable pointers, 0x7F... sentinels), so a "non-zero u64 near
//     here" is not evidence of FieldTime.
//   * findptr for the absolute address -- 0 results in both images.

// ---- kVtPhysicsObject and kVtCamera stay 0, deliberately -------------------
// These are NOT unresolved pending work, and the earlier note here got the reason
// wrong. There is nothing to find: both are 0 on 3424 as well, and 0 is a value the
// consumers are written to respect --
//
//   player_reader.cpp:83    if (off::kVtPhysicsObject != 0 && !has_vtable(...))
//   camera_reader.cpp:66    if (off::kVtCamera != 0 && !has_vtable(...))
//
// -- so 0 means "identity check not available" and each reader falls through to the
// check that is actually load-bearing: for physics, the orthonormal basis and the
// cross-check against the static position; for the camera, a float sentinel at +0xAC0
// of the camera block. Setting a guessed address here would be strictly worse than 0,
// because a wrong vtable turns a working reader into one that refuses.
//
// The reason they are 0 is the honest one: `PhysicsObject` is not a class name in this
// image at all, and `Camera` matches unrelated types (hkxCamera, CameraComponent,
// ClientFrameEventCameraShake...) with no way to tell which one the field holds. That
// is a search that cannot converge, not a search that has not been run.
//   kVtPhysicsObject, kVtCamera                  -> 0 (no check, by design)
//
// ---- kVtWallUpMovementMethod: the old value was never this vtable ----------
// MEASURED on 3446, and it turned out the 3424 value was not merely stale.
//
// The class `.?AVWallUpMovementMethod@pa@@` IS in both binaries with RTTI intact, so
// `probe vtables` resolves it after all and the note above (that these cannot be
// re-resolved) was true only for the other two:
//
//   WallUpMovementMethod vtable   3424 exe+0x5916EC8   ->   3446 exe+0x5918F78
//
// The identity is not taken on faith from the name. The two vtables' slots point at the
// same member functions with a consistent 0x10 delta across every slot compared --
// 0x140773920/0x140773910, 0x1406D6D90/0x1406D6D80, 0x1403A2990/0x1403A29D0 and so on
// for eight slots -- which is the same code shifted, i.e. the same class.
//
// The value in use was 0x55968B8, which is NOT that vtable: its slots are a completely
// different set of functions, and [0x55968B8-8] does not dereference to a plausible
// CompleteObjectLocator at all (it reads as `sub rsp,0x28` and other code bytes). So the
// guard `has_vtable(wallup, base + kVtWallUpMovementMethod)` in local_capture.cpp:368
// has been comparing an object's vtable pointer against an address that is not a vtable
// of that class -- on 3424 as well as 3446.
//
// What that cost, stated precisely: read_player_wallup() returns nullopt whenever the
// move method is WallUp, so wall-climbing was never relayed between players. It failed
// closed -- no wrong data, no corruption -- which is exactly why it went unnoticed.
// Fixing the value is the first time this path can work at all, so it should be treated
// as untested rather than as a repaired feature.
inline constexpr uintptr_t kVtWallUpMovementMethod = 0x5918F78;  // 3424:0x5916EC8 (was 0x55968B8, not this vtable)

// ---- Troc handler instances ----------------------------------------------
// MEASURED by running the mod's own walk against the live game, then bracketed
// from both sides:
//   probe troc exe+6E00000 exe+6F80000  -> 1175 handlers
//   first 0x6E82D10, last 0x6EB6370, span 0x33660
//   probe troc exe+6E00000 exe+6E82D10  -> 0 handlers  (nothing below)
//   probe troc exe+6EB6370 exe+6F80000  -> 1 handler   (the last one)
//
// The 3424 range (0x6E973A0 .. 0x6EC8540) would NOT have been a small error:
// 0x6E973A0 sits 0x14690 bytes INSIDE the true range, so the walk would have
// silently skipped every handler from 0x6E82D10 to 0x6E973A0 -- including
// TrocTrStartActionAck and the PostProcessAttackResult_* family, the messages
// co-op relays combat through. The walk would still have run and simply found
// fewer types. A silently short range is more dangerous than a wrong address, so
// this pair is measured rather than shifted. (kKind/kOpcode are struct offsets in
// the base namespace and are unaffected.)
inline constexpr uintptr_t kTrocInstancesBegin = 0x6E82D10;  // 3424:0x6E973A0
inline constexpr uintptr_t kTrocInstancesEnd = 0x6EB6378;    // 3424:0x6EC8540, last + 8

// ---- minimap icon roots ---------------------------------------------------
// Derived from kWorldSystemSlot with the SAME gaps the 2976 and 3424 builds both
// used (+0x398, +0x3A0), and each confirmed to have code reaching it: 3446 code
// at exe+0x8DDE3B does
//     mov    rax, [root]
//     cmp    byte [rdx+rcx], 0
//     cmovnz rax, [rootAlt]
// which is exactly the "used under a TLS flag" pattern the 2976 comment
// described -- both slots appearing together in one select. A flat +0x2FF4 shift
// (what the other globals got) reaches NEITHER of them, so the struct-relative
// gap is doing real work here, not rounding.
inline constexpr uintptr_t kMinimapIconRoot = 0x71B1DD8;     // = kWorldSystemSlot + 0x398
inline constexpr uintptr_t kMinimapIconRootAlt = 0x71B1DE0;  // = kWorldSystemSlot + 0x3A0

// ---- the minimap icon decision function -----------------------------------
// MEASURED on 3446, and it corrects a long-standing mistake in how this site was
// recorded. The 3424 value 0x9E89C0 is NOT the start of the function -- it is a
// MID-HOOK, +0x6ED into a body that begins at 0x9E82D0. The 16 bytes stored as
// kMinimapIconDecideHead were therefore never that function's prologue; they are
// the prologue of some other function, which is why the offline guard could never
// match them and why this site appeared permanently "unresolvable". It was being
// compared against the wrong thing.
//
// Found by diffing the two builds, the method that resolved kCcPost and kPending:
//   * the interior sequence `lea rcx,[rsp+0x60] / call / cmp byte ptr [rsp+0x48],0`
//     occurs EXACTLY ONCE in the 3446 image, at exe+0x9E8A73;
//   * the site is that +0x0A = exe+0x9E8A7D, and the instructions after it line up
//     one for one with 3424, including the global it loads (3446 0x713C7D0 against
//     3424 0x71397E0, a delta of 0x2FF0 -- the struct-relative gap above, NOT the
//     flat shift the other globals took, so this is corroboration not coincidence);
//   * the internal offset is IDENTICAL in both builds: 0x9E82D0 + 0x6ED = 0x9E89BD
//     and 0x9E8390 + 0x6ED = 0x9E8A7D.
//
// The hook is installed at the site, not at the function entry, so the address the
// mod uses is the site. The head is re-recorded from the real bytes at the site.
inline constexpr uintptr_t kMinimapIconDecide = 0x9E8A7D;  // 3424:0x9E89BD (mid-hook; body at 0x9E8390)
inline constexpr uint8_t kMinimapIconDecideHead[] = {0x80, 0x7C, 0x24, 0x48, 0x00, 0x75, 0x6F, 0x8B,
                                                     0x05, 0x46, 0x3D, 0x75, 0x06, 0x41, 0x89, 0x06};

// Same reasoning: kWorldSystemSlot + 0x2A8, the gap both older builds used,
// confirmed to have code referencing it.
inline constexpr uintptr_t kClientClockBias = 0x71B1CE8;  // = kWorldSystemSlot + 0x2A8

// ---- server-side writer of OtherEquipItemAck ------------------------------
// MEASURED on 3446, and it exposed a defect that had been sitting in the 3424 value
// the whole time: the address was off by ONE BYTE.
//
//   3424 recorded 0x29ED1F0 -> 02 48 8B 84 24 E0 10 00 00 ...
//   3424 actually  0x29ED1F1 -> 48 8B 84 24 E0 10 00 00 48 8B 10 48 85 D2 74 0A
//
// 0x29ED1F0 lands in the MIDDLE of the `mov rax,[rsp+0x10E0]` instruction, so the 16
// bytes compared against `kServerOtherEquipWriterHead` began with a stray 02 and could
// never equal the recorded head. The head itself was written from the same wrong place,
// so the comparison was consistent with itself and the mistake was invisible: the guard
// in local_capture.cpp compares the live bytes against the stored head, both of which
// came from the misaligned address. The only way it could have shown up is on a build
// where that byte happened to differ, which is what 3446 is.
//
// A mid-hook address must be the START of an instruction. safetyhook does not repair a
// misaligned site; it hooks where it is told, so a one-byte error would have made the
// hook fire mid-instruction and copy garbage from rcx/r8/r9 through copy_equip_args.
// That this never bit on 3424 is luck, not design.
//
// Found by diffing the two builds, as with kCcPost and kPending:
//   * the function entry is identifiable by its prologue and its large frame --
//     `mov [rsp+8],rbx / mov [rsp+0x18],r8b / push rdi / mov eax,0x1060` -- and that
//     prologue is byte-identical in both builds, so only the START address moved;
//   * 3424 entry 0x29ED140 and 3446 entry 0x29EDC60 put the site at the SAME internal
//     offset, +0xB1, which is what makes this a measurement rather than a guess;
//   * the 16 bytes at the 3446 site are byte-for-byte equal to the 3424 site's.
//
// The `mov [rsp+0x18],r8b` in the prologue is independent corroboration that the hook's
// arguments are where on_equip_writer thinks they are: it reads ctx.r8, and r8b is
// stored by the callee's own prologue.
inline constexpr uintptr_t kServerOtherEquipWriter = 0x29EDD11;  // 3424:0x29ED1F1 (was 0x29ED1F0, one byte early)
inline constexpr uint8_t kServerOtherEquipWriterHead[] = {0x48, 0x8B, 0x84, 0x24, 0xE0, 0x10, 0x00, 0x00,
                                                          0x48, 0x8B, 0x10, 0x48, 0x85, 0xD2, 0x74, 0x0A};

// ---- code the co-op path cannot work without ------------------------------
// Both re-found on 3446 by scanning for their prologues; both matched as the
// FIRST hit, which is the same position they held on 3424:
//   kClientPostPacket    3424 0x3A5570 -> 3446 0x3A55B0  (+0x40)
//   kClientOnRecvPacket  3424 0x3A5900 -> 3446 0x3A5940  (+0x40)
// The head arrays below are what the mod verifies before hooking. On a mismatch
// the sniffer refuses to install and co-op does not transmit -- a refusal, not a
// corruption.
inline constexpr uintptr_t kClientPostPacket = 0x3A55B0;
inline constexpr uint8_t kClientPostPacketHead[] = {0x48, 0x89, 0x5C, 0x24, 0x10, 0x4C, 0x89, 0x4C};
inline constexpr uintptr_t kClientOnRecvPacket = 0x3A5940;
inline constexpr uint8_t kClientOnRecvPacketHead[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74};

}  // namespace cdmp::game::build_3446
