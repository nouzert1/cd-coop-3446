#pragma once
// Addresses for CrimsonDesert.exe 1.0.0.3460.
//
// HOW THIS BUILD ARRIVED. Steam auto-updated the game again, at 12:56 on 2026-10-31,
// from 1.0.0.3446 (PE 0x6AE46DD0, SizeOfImage 0x14268000, 332,786,072 bytes) to
// 1.0.0.3460 (PE 0x6AE58024, SizeOfImage 0x13EE0000, 329,084,312 bytes). The first
// launch afterwards logged exactly what the version guard is built to produce:
//
//   Host version: 1.0.0.3460  image base: 0x140000000  image size: 0x13EE0000
//   Game reader DISABLED: unsupported game build. Only networking will run.
//
// That message is the whole reason this file exists. It is also indistinguishable
// from "the mod is broken" to anyone who does not read it, which is why the kit ships
// with the log line quoted in the guest guide.
//
// WHAT DID *NOT* CHANGE, measured rather than assumed:
//
//   * 15262 RTTI classes on 3446, 15262 on 3460 -- identical. The game's class
//     structure is untouched, so every class this mod looks up by name still exists.
//   * The 3.5 MB shrink is the `.debug` section (the 195 MB executable decoy), not
//     code. `.text` moved by hundreds of bytes, not megabytes.
//
// WHAT DID CHANGE, and the reason this file is not a rename of the old one:
//
//   THE SHIFT IS NOT UNIFORM. Measured vtable by vtable through RTTI:
//     kVtControlledActor     +0x4010        kVtStatusComponent    +0x4000
//     kVtCharacterControl    +0x4010        kVtClientActorManager +0x4018
//   Three agree and the fourth does not. A single delta applied to the whole table
//   would have silently missed one address -- a guard that passes sometimes, which is
//   strictly worse than one that never passes, because it produces a mod that is
//   half-alive and a log that looks plausible.
//
//   This is the same lesson the 3424 -> 3446 port records at offsets_3446.h:232
//   ("The 3424 -> 3446 delta is again NOT one constant"), learned again one patch
//   later. The conclusion to draw is not "be careful with deltas" but "do not use
//   deltas at all": resolve each address by its class or its prologue, and confirm
//   it by what the code does.
//
// METHOD, per kind of value, as it was actually used here:
//   * vtables -- `probe classes <substring>` for the TypeDescriptor, then
//     `probe vtables ".?AVName@pa@@"` for the vtable. Confirmed by requiring
//     [vtable-8] to point into .rdata (the CompleteObjectLocator); a candidate whose
//     [vt-8] points at code (0x5C2A50, 0x941EE0) is not a vtable at all.
//   * virtual methods -- the Enter slot is at +0x38 (unchanged from 3446), and the
//     prologue bytes are compared against the head arrays below.
//   * data globals -- still under measurement; see the block at the end.

#include "mod/game/offsets_3446.h"

namespace cdmp::game::build_3460 {

// ---- build identity -------------------------------------------------------
// Read from the file, and from the running process by the first launch of the
// 3446 build against the 3460 exe. The guard compares this before touching
// memory, so a mismatch makes the mod inert rather than wrong.
inline constexpr uint32_t kPeTimestamp = 0x6AE58024;  // 3446:0x6AE46DD0, 3424:0x6AE387F2
inline constexpr uintptr_t kImageBase = 0x140000000;  // fixed, no ASLR
inline constexpr uintptr_t kImageSize = 0x13EE0000;   // 3446:0x14268000, 3424:0x145B9000

// ---- vtables, resolved by RTTI --------------------------------------------
// Each one named with the class the RTTI actually holds, NOT with the constant's
// own name. That distinction cost real time on this port: `kVtControlledActor`
// does not correspond to a class called `ControlledActor` -- no such class exists
// in either binary, so `vtables ".?AVControlledActor@pa@@"` answers "0 shown", which
// reads like "the class was removed by the patch" and is really "you guessed the
// name". The real names are recorded at offsets_3424.h:110-112.
//
//   kVtControlledActor    -> ClientChildOnlyInGameActor
//   kVtCharacterControl   -> ClientCharacterControlActorComponent
//   kVtStatusComponent    -> ClientStatusActorComponent
inline constexpr uintptr_t kVtClientActorManager = 0x593DCF0;  // 3446:0x5939CD8  (+0x4018)
inline constexpr uintptr_t kVtControlledActor = 0x590BCA0;     // 3446:0x5907C90  (+0x4010)
inline constexpr uintptr_t kVtCharacterControl = 0x593C8E0;    // 3446:0x59388D0  (+0x4010)
inline constexpr uintptr_t kVtStatusComponent = 0x59136E0;     // 3446:0x590F6E0  (+0x4000)

// ---- movement methods -----------------------------------------------------
// These three are the fixes made on 2026-10-31 for 3446, and they are the part of
// this port that is CERTAIN, because they were confirmed twice over:
//
//   1. the vtable is resolved by RTTI, not by remembering a number;
//   2. the Enter slot (+0x38) was read, and the bytes at the resulting address were
//      compared against the recorded prologue head.
//
// The deltas are identical across all three (+0x990), which is what one block of
// code moving together looks like -- corroboration, not proof. The proof is the
// byte comparison:
//
//   0x75FFC0  4C 8B DC 49 89 5B 10 49 89 6B 18 49 89 73 20 57  == kPointClimbEnterHead
//   0x74F270  48 8B C4 48 89 58 10 48 89 70 18 55 57 41 54 41  == kRideEnterHead
//
// (On 3446 the value in use for kPointClimbEnter had been 0x691400, which is not
// this function at all -- a pointer-list walk. The prologue head is generic and had
// 20 hits on 3446, so it identifies nothing on its own; the RTTI resolution is what
// makes the address trustworthy, and the head only confirms it.)
inline constexpr uintptr_t kVtWallUpMovementMethod = 0x591CF78;  // 3446:0x5918F78
inline constexpr uintptr_t kPointClimbEnter = 0x75FFC0;          // 3446:0x75F630
inline constexpr uint8_t kPointClimbEnterHead[] = {0x4C, 0x8B, 0xDC, 0x49, 0x89, 0x5B, 0x10, 0x49,
                                                   0x89, 0x6B, 0x18, 0x49, 0x89, 0x73, 0x20, 0x57};
inline constexpr uintptr_t kRideOnEnter = 0x74F270;   // 3446:0x74E8E0
inline constexpr uintptr_t kRideOffEnter = 0x750240;  // 3446:0x74F8B0
inline constexpr uint8_t kRideEnterHead[] = {0x48, 0x8B, 0xC4, 0x48, 0x89, 0x58, 0x10, 0x48,
                                             0x89, 0x70, 0x18, 0x55, 0x57, 0x41, 0x54, 0x41};
// vtables the Enter slots above were read from, recorded so the next port can
// re-derive them in one step instead of re-running the whole RTTI search:
//   PointClimbMovementMethod  exe+0x591D6A8     RideOnMovementMethod   exe+0x591D868
//   RideOffMovementMethod     exe+0x591D758     WallUpMovementMethod   exe+0x591CF78

// ---- co-op packet path ----------------------------------------------------
// kClientPostPacket. Corroborated by structure rather than by the prologue alone:
// the distance between these two functions is 0x390 in BOTH builds, which is an
// independent check that the pair is the same pair.
//
//   kClientPostPacket    3446 0x3A55B0 -> 3460 0x3A5A30
//   kClientOnRecvPacket  3446 0x3A5940 -> 3460 0x3A5DC0   (gap 0x390, unchanged)
//
// COLLATERAL FINDING, recorded because it affects how much of the 3446 behaviour
// can be trusted: the 3446 value of kClientPostPacket does not land on a function
// boundary. Disassembled at 0x3A55B0 it reads `add [rax],al` / `cmp byte ptr
// [rbp],0x00` -- mid-instruction -- while the 3460 value lands on a clean
// `mov [rsp+0x10],rbx` / `mov [rsp+0x20],r9` / `push rbp` prologue. Since the hook
// memcmps its head before installing, the sniffer's Post hook was probably never
// installed on 3446 either, and some behaviour attributed to other causes may be
// this. NOT verified live; recorded as a suspicion, not a finding.
inline constexpr uintptr_t kClientPostPacket = 0x3A5A30;
inline constexpr uint8_t kClientPostPacketHead[] = {0x48, 0x89, 0x5C, 0x24, 0x10, 0x4C, 0x89, 0x4C};
inline constexpr uintptr_t kClientOnRecvPacket = 0x3A5DC0;
inline constexpr uint8_t kClientOnRecvPacketHead[] = {0x48, 0x89, 0x5C, 0x24, 0x08, 0x48, 0x89, 0x74};

// kMinimapIconDecide. A unique hit in both binaries for its 8-byte head, which is
// the strongest kind of evidence available for a mid-function site. Note the value
// IN USE on 3446 (0x9E8A7D) was already wrong there -- the head's only hit was at
// 0x9E89BD -- so this offset was mis-set one build before this port began.
inline constexpr uintptr_t kMinimapIconDecide = 0x9E95CD;  // 3446 head hit: 0x9E89BD (in use there: 0x9E8A7D)

// ---- action layer ---------------------------------------------------------
// Both found by their prologues, and both still carry their full head arrays from
// 3446, so the mod's own memcmp is the live check. A mismatch means the hook is not
// installed and action-layer containment does not run -- a refusal, not a corruption.
inline constexpr uintptr_t kActionLayerAdvance = 0x214C0C0;  // 3446:0x2148D50
inline constexpr uintptr_t kActionLayersAdvance = 0x2320D50;  // 3446:0x232A8B0 family, +0x48E0

// ---- kServerOtherEquipWriter: the 3446 VALUE WAS WRONG, and this is not a port --
// The 3446 table declares 0x29EDD11 with a 16-byte head. Reading that address on
// 3446 returns `74 5A 33 FF 39 87 76 20 66 0F 1F 44 00 00` -- not one byte of the
// declared head matches. capture_install_equip_hook() memcmps the head before
// hooking, so it always failed, always logged "OtherEquipItemAck writer not
// recognised; equipment changes won't be sent", and NEVER hooked. Equipment of the
// other player has never been relayed, on any build. This is the same shape of
// defect as kPointClimbEnter, which also carried a wrong 3446 address.
//
// The head cannot be used to re-find the site: searched across both binaries it
// returns 12+ hits each, every one of them the same inlined `std::unique_lock`
// idiom --
//     call [0x...45589040] / mov rax,[rsp+0x10E0] / mov rdx,[rax] / test rdx,rdx
// A signature that describes a compiler idiom identifies no class. A 16-byte
// pattern with a dozen matches is not evidence of anything.
//
// The value below is INHERITED UNCHANGED and is known to be wrong. It is not fixed
// here because guessing a replacement would be worse than leaving a hook that
// visibly refuses: the log line is an honest report, while a wrong address would
// hook an unrelated function. The way to find the real site is through the
// TrocTrOtherEquipItemAck handler, the same route that located the field-time
// writer. Until then, guest equipment sync does not work and has never worked.
inline constexpr uintptr_t kServerOtherEquipWriter = 0x29EDD11;  // WRONG on 3446 too; see above

// ---- Troc handler instances -----------------------------------------------
// The mod walks a contiguous array of handler instances, 8 bytes apart, each
// holding a vtable pointer followed by its opcode and kind, and identifies each by
// its RTTI name. The walk is bracketed by these two addresses.
//
// MEASURED, and this is the cleanest result of the whole port:
//
//                      3446            3460            delta
//   begin          0x6E82D10       0x6E86D10        +0x4000
//   end            0x6EB6378       0x6EBA378        +0x4000
//   handler count       1175            1175        identical
//   span              0x33660         0x33660        identical
//
// The span is byte-identical and the count is identical, so the array did not grow
// or shrink -- it moved by exactly the +0x4000 seen in .rdata elsewhere. Verified
// from both sides: nothing before 0x6E86D10 and nothing after 0x6EBA378 carries a
// .?AVTrocTr vtable.
//
// HOW IT WAS FOUND, because the first two attempts failed for instructive reasons:
//   * `scan` over the FILE for the vtable pointer returned 0 hits. The instances
//     live in data that is initialised at load time, so the file does not contain
//     them; only the loaded image does.
//   * `troc --begin X --end Y` silently used the DEFAULT range and reported 0, which
//     read as "the array moved somewhere unknown". The arguments are POSITIONAL
//     (`troc <begin> <end>`), so the flags were ignored. This is the fourth time in
//     this project that a tool reported a fact about the game when the real problem
//     was in the call: an option that is accepted and ignored produces a confident
//     zero, and a confident zero looks exactly like a finding.
inline constexpr uintptr_t kTrocInstancesBegin = 0x6E86D10;  // 3446:0x6E82D10
inline constexpr uintptr_t kTrocInstancesEnd = 0x6EBA378;    // 3446:0x6EB6378

// ---- data globals: MEASURED LIVE ON 3460 --------------------------------
//
// kWorldSystemSlot: 0x71B5CF0. Measured live, not derived.
//
// HOW IT WAS FOUND. The 3446 value (0x71B1A40) is wrong on this build and reads as a
// GlobalVariableManager. Offline routes all failed for stated reasons, so the mod
// asked the game: it swept its own data range for a slot whose target holds the live
// ClientActorManager, and found exactly two candidates, 0x71B5CA0 and 0x71B5CF0.
//
// WHY 0x71B5CF0 AND NOT 0x71B5CA0. Neither could be separated offline -- both point
// at a world whose [+0x30] is the SAME single live manager, and both reach the same
// controlled actor. The deciding evidence is the position: walking the full chain
// from 0x71B5CF0 was traced live, hop by hop, and every hop validated by the game's
// own type rather than by an address:
//
//   [0x71B5CF0]              -> world   0x32F61FAE100
//     world  [+0x30]         -> manager 0x32F6E3D4600   RTTI ClientActorManager
//       mgr  [+0x50]         -> actor   0x32F97FED200   RTTI ClientChildOnlyInGameActor
//         actor[+0x60] (u32) -> 0xA0100001              actor key, same 0xA010____
//                                                       shape the 3446 player used
//         actor[+0x68]       -> comps   0x32F72F45200
//           comps[+0x40]     -> ctl     0x33019E77D00   RTTI ClientCharacterControlActorComponent
//             ctl  (vtable)  -> 0x14593C8E0            == kVtCharacterControl
//             ctl  [+0x140]  -> inner   0x32F562D3800
//               inner[+0x2C0] -> phys   0x32F56A23C00
//                 phys [+0x90] -> (-636.10, 613.62, -842.84)
//
// The final value is a coherent world position -- Y is an elevation, X and Z are
// ground coordinates -- and it came out of a chain where all four type checks passed.
// That is the strongest form of evidence available here: it does not depend on any
// offset being remembered correctly, only on the game's own RTTI agreeing at each hop.
//
// The two candidates are 8 bytes apart in their slot array but point at worlds 0x900
// apart. Note what this means, because it is the same trap as the previous port: the
// 3446 header recorded that the game itself reads 0x71B1A38 while kWorldSystemSlot was
// 0x71B1A40, "both hold valid pointers and both are used". So two plausible world
// slots is a property of this game, not an artefact of a bad measurement, and picking
// the one that merely looks closest to the old address is not a method.

// ---- data globals: STILL SUSPECT ----------------------------------------
//
// These carry their 3446 values and are UNVERIFIED on 3460. The list shrank this round:
// kWorldSystemSlot is now measured (above), and the chain from it to a position was
// traced live, which incidentally confirms kWorldSystem_ActorManager, kActor_ComponentTable,
// kComponents_CharacterControl, kActorManager_ControlledActor, kControl_Inner,
// kControlInner_Physics and kPhysics_Position -- all the STRUCT offsets, which is what
// the comment at the top of this file predicted (structure survives a patch; addresses
// do not).
//
// WHAT WENT WRONG EARLIER, recorded so it is not repeated. An earlier revision of this
// comment claimed cdmp_probe contradicts itself. That was WRONG. The probe works; the
// calls were bad. Two specific traps, both hit in this port:
//   * `troc --begin X --end Y` is silently ignored -- the arguments are POSITIONAL. The
//     default range was swept and returned 0, which read as "the handler array moved
//     somewhere unknown". It had moved by +0x4000, and was found as soon as the call
//     was written correctly.
//   * `xrefs` reports the address of the SHIFTED OPERAND, not the instruction start.
//     Three "sites" for one global were one instruction counted three ways.
// Both produced confident, specific, wrong numbers. A tool that reports a fact about
// the game when the defect is in the call is the single most expensive failure mode in
// this project.
//
// kStaticPlayerPos deserves a specific warning. Read as f32 it returns -88.3066, which
// LOOKS like a coordinate; `dump` shows the bytes are pointers, and following them
// yields nothing that is a position. The plausible-looking float was a coincidence of
// bit patterns. Do not accept a value because it resembles the thing you wanted.
//
// HOW TO SETTLE THE REST. Through the mod, not the probe. PlayerReader computes
// `static_pos_error` -- the distance between the position it derives from the chain and
// this global (player_reader.cpp:122-124) -- printed as `check vs game global {:.2f} m`.
// A correct chain reports centimetres. That number is self-checking: it compares two
// independent derivations, so it does not depend on any external tool agreeing.
inline constexpr uintptr_t kWorldSystemSlot = 0x71B5CF0;  // measured live; 3446:0x71B1A40
inline constexpr uintptr_t kCameraSlot = 0x70CDEA8;       // 3446 value, UNVERIFIED on 3460
inline constexpr uintptr_t kStaticPlayerPos = 0x71C0C20;  // 3446 value, UNVERIFIED (see above)
inline constexpr uintptr_t kChunkOrigin = 0x719DCA0;      // 3446 value, UNVERIFIED on 3460
inline constexpr uintptr_t kMinimapIconRoot = 0x71B1DD8;     // 3446 value, UNVERIFIED
inline constexpr uintptr_t kMinimapIconRootAlt = 0x71B1DE0;  // 3446 value, UNVERIFIED
inline constexpr uintptr_t kClientClockBias = 0x71B1CE8;     // 3446 value, UNVERIFIED
inline constexpr uintptr_t kClientClockGlobal = 0x70CDCAD;   // 3446 value, UNVERIFIED
inline constexpr uintptr_t kClientFrameClockMs = 0x70CDCE1;  // = flag + 0x34
inline constexpr uintptr_t kClientFrameClockUs = 0x70CDCE9;  // = flag + 0x3C
inline constexpr uintptr_t kClientClock = 0x1416B80;         // 3446 value, UNVERIFIED

// ---- inherited unchanged from 3446 ----------------------------------------
// RTTI class count is identical between the two builds (15262 on each), and the
// patch moved code rather than restructuring the game, so everything a patch does
// NOT move is re-exported rather than restated. This keeps the diff between two
// builds readable, and that diff is the thing a future port needs most.
//
// These names are NOT verified against 3460: they are the 3446 values, inherited
// on the argument that a patch that did not move them leaves them correct. Each one
// that matters is confirmed live through the mod, not through this list.
//

using build_3446::kActionLayerAdvanceHead;
using build_3446::kActionLayersAdvanceHead;
using build_3446::kMinimapIconDecideHead;
using build_3446::kServerOtherEquipWriterHead;
using build_3446::kServerDockingWriter;
using build_3446::kServerDockingWriterHead;
using build_3446::RelayedAck;
using build_3446::kActorManager_ControlledActor;
using build_3446::kActor_ComponentTable;
using build_3446::kActor_Key;
using build_3446::kActor_OwnerUser;
using build_3446::kCameraBlockSentinelValue;
using build_3446::kCameraBlock_Forward;
using build_3446::kCameraBlock_Position;
using build_3446::kCameraBlock_Projection;
using build_3446::kCameraBlock_Sentinel;
using build_3446::kCameraBlock_View;
using build_3446::kCamera_Block;
using build_3446::kClientClockHead;
using build_3446::kComponents_CharacterControl;
using build_3446::kComponents_Status;
using build_3446::kControlInner_Physics;
using build_3446::kControl_Inner;
using build_3446::kControl_Layer0;
using build_3446::kControl_MoveController;
using build_3446::kControl_WallData;
using build_3446::kCoopPinId;
using build_3446::kFieldTimeClient;
using build_3446::kHookArgSizeStackOffset;
using build_3446::kLayer_Chart;
using build_3446::kLayer_Playback;
using build_3446::kLoadKindMount;
using build_3446::kLoadPositionFromEnd;
using build_3446::kLoadRotationFromEnd;
using build_3446::kLoadingParkHeight;
using build_3446::kLoadingParkRadius;
using build_3446::kMaxStatEntries;
using build_3446::kMethod_Actor;
using build_3446::kMinimapIconCompanion;
using build_3446::kMinimapIconOutlinedArrow;
using build_3446::kMinimapIconPlayerArrow;
using build_3446::kMoveController_Method;
using build_3446::kMoveController_WallUp;
using build_3446::kMoveMethodWallUp;
using build_3446::kOpActorLoadDataAck;
using build_3446::kOpChangeDockingSocketByFrameEventAck;
using build_3446::kOpCreateOrChangePinMarkerAck;
using build_3446::kOpMoveActorAck;
using build_3446::kOpMoveActorReq;
using build_3446::kOpOtherEquipItemAck;
using build_3446::kOpOtherUnequipItemAck;
using build_3446::kOpRemoteCatchResultAck;
using build_3446::kOpRemoveActorAck;
using build_3446::kOpRemovePinMarkerAck;
using build_3446::kOpRotateActorAck;
using build_3446::kOpRotateActorReq;
using build_3446::kOpSetFieldTimeAck;
using build_3446::kOpSetFieldTimeReq;
using build_3446::kOpStartActionAck;
using build_3446::kOpStartActionReq;
using build_3446::kOpUnequipItemAck;
using build_3446::kOpUpdateOnDemandGimmickAck;
using build_3446::kOpUpdateWallUpDataAck;
using build_3446::kPhysics_AxisX;
using build_3446::kPhysics_AxisY;
using build_3446::kPhysics_AxisZ;
using build_3446::kPhysics_Position;
using build_3446::kPinColourCount;
using build_3446::kPinGroupNormal;
using build_3446::kPinShapeCount;
using build_3446::kRelayedAcks;
using build_3446::kRemoteCatchSceneId;
using build_3446::kServerActor_Key;
using build_3446::kServerDockingWriterHead;
using build_3446::kStatContainer_Count;
using build_3446::kStatContainer_Entries;
using build_3446::kStatEntry_Current;
using build_3446::kStatEntry_Id;
using build_3446::kStatEntry_Max;
using build_3446::kStatEntry_Size;
using build_3446::kStatId_Health;
using build_3446::kStatId_Stamina;
using build_3446::kStatus_StatContainer;
using build_3446::kTroc_Kind;
using build_3446::kTroc_Opcode;
using build_3446::kVtCamera;
using build_3446::kVtPhysicsObject;
using build_3446::kWorldSystem_ActorManager;

}  // namespace cdmp::game::build_3460
