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
using build_3424::kActionLayerAdvance;
using build_3424::kActionLayerAdvanceHead;
using build_3424::kActionLayersAdvance;
using build_3424::kActionLayersAdvanceHead;
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
using build_3424::kServerActor_Key;
using build_3424::kServerDockingWriter;
using build_3424::kServerDockingWriterHead;
using build_3424::kServerOtherEquipWriter;
using build_3424::kServerOtherEquipWriterHead;
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
using build_3424::kVtWallUpMovementMethod;
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
// These three have no RTTI class of that name in this image at all
// (`probe vtables` answers "Type name not found"), so they cannot be re-resolved
// and keep their previous values. PhysicsObject and Camera were already 0 on 3424,
// which reads as "no check"; WallUpMovementMethod is non-zero and belongs to a
// feature whose consumer fails closed, so a stale value costs that feature and
// nothing else. Named here so the next person does not have to re-derive why two
// of the seven vtables are missing from the measured list above.
//   kVtPhysicsObject, kVtCamera                  -> 0 (unchanged, no check)
//   kVtWallUpMovementMethod = 0x55968B8          -> unverified on 3446

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
