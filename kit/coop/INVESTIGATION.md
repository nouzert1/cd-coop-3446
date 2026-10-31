# INVESTIGATION.md — why the host crashes when the other player's character spawns

**BUILD NOTICE.** This document describes a crash observed on game build **1.0.0.3446**, and
every address in it belongs to that build. The kit has since moved to **1.0.0.3460** and the
game has been re-ported. **Do not use any address below on 1.0.0.3460** — re-measure it first.
What still transfers is the method, the failure modes, and the three traps in Section 4.

For an AI coding agent doing reverse-engineering work. This is a **research task**, not an
install task. `INSTALL.md` covers installation.

Read the whole file before touching anything. Section 0 is a safety rule, not advice.

---

## 0. Ground rules

This investigation **crashes the game on purpose, repeatedly**. Before every run:

```powershell
$save = "$env:LOCALAPPDATA\Pearl Abyss\CD\save"
Copy-Item $save "$env:USERPROFILE\Desktop\CD-save-backup-$(Get-Date -Format HHmmss)" -Recurse -Force
```

Additional rules, each one from a crash that already happened:

- **Always work on the copy of the executable**, never in a live process, when doing
  static analysis. Use `cdmp_probe.exe --image <path>`.
- **Never let the user save while the other player is in their world.** The crash below
  happened during a session; a save at that moment is the one irreversible outcome.
- **Do not remove the guard that disables horse and enemy copies.** It exists because
  those copies crashed for a reason that has not been fixed (Section 3).
- **The game must be closed** to swap `cdmp.asi`. The rename-and-swap script waits for
  exit; do not force it.
- Report measurements, not guesses. Every address in a conclusion must say how it was
  measured. Two earlier errors in this port came from assuming a value instead of
  reading it: a base-32 constant that was one hex digit short (round-trips passed, only a
  real lobby id caught it) and a vtable found by name that pointed at a decoy.

---

## 1. The symptom, exactly

Game build **1.0.0.3446** — that is the build this crash was observed on, and every address
in this document refers to it. The kit now ships for **1.0.0.3460**, so if you are reading
this to fix a crash on 3460, re-measure before trusting any address below. Both players were
on mod build `{{BUILD_ID}}`, verified identical, so this is **not** a version mismatch.

The guest joins. Position exchange works. Then, the instant the guest's character is
spawned into the host's world, **the host's game exits with no error dialog.**

The host's `cdmp.log` ends here — these are the last lines the process ever wrote:

```
20:49:06.593  Co-op: received the other player's character (37127 bytes, player 0xA0100001, spawn 1)
20:49:06.597  Puppet: rewrote keys in user packet: user x3, player x81, body x0
20:49:06.597  Puppet: rewrote keys in body packet: user x4, player x81, body x8
20:49:06.598  Puppet: spawn queued at (-10626.6, 621.3, -3813.7)
              (2 packets, 15303 + 6445 bytes, sender player 0xA0100001, generation 1)
20:49:06.598  Co-op: the other player is in our world (spawn 1)
20:49:06.629  Inject: delivered opcode 2005 (15308 bytes) to ClientNet::OnRecvPacket
20:49:06.629  Inject: delivered opcode 2005 (6450 bytes) to ClientNet::OnRecvPacket
20:49:07.005  Net: connected | ... | remote states 11 | last remote (-10626.71, 621.32, -3813.64) hp 1093.8
20:49:07.005  Local: pos (-10680.29, 616.68, -3854.73) ... | check vs game global 0.04 m
20:49:07.005  co-op: other player loaded | events in 0 | ...
20:49:07.005  Overlay: installed true disabled false | presents 7434 drawn 7433
              >>> nothing after this <<<
```

**0.4 seconds** from injecting the spawn to process death. `opcode 2005` is
`ActorLoadDataAck`; it is the two packets above that actually load the actor.

Note what is **absent**, because absence is evidence here:

- no exception, no assert, no error line — the process died without a chance to log;
- no `ACCESS_VIOLATION` in the mod's own handler, so the fault was not caught;
- the guest did **not** crash. The host's log shows the guest's character arrived
  complete (37127 bytes) and the guest kept sending state (`remote states 11`,
  `hp 1093.8` updating). Whatever broke is in the **host's** handling of the spawn.

---

## 2. The most likely cause: a missing safety net

At startup, 11 seconds before the crash, the host's log has this:

```
20:45:36.435  WRN  Puppet: horse disabled
20:45:36.435  WRN  HorseDiag: CC update (exe+0x85FBA0) not recognised
20:45:36.435  WRN  Horse and enemy copies disabled: their crash containment could not be installed
```

**"Crash containment could not be installed."** This is the lead.

`cdmp.asi` installs crash containment around the code that spawns an actor: it wraps the
actor-construction path so that a bad spawn is caught and discarded instead of killing
the process. On 1.0.0.3446 the function it hooks was not found — its address moved with
the patch — so the mod logged this warning and **disabled horse and enemy copies**, which
are the copies that depended on that containment.

The remote player copy was **not** disabled, because it is the whole point of the mod. It
then took exactly the path the containment was built to survive, with no containment
present.

This is a hypothesis with strong circumstantial support, not a measurement. **Establishing
it is the first task**, and it is testable: locate the containment target on 3446, install
it, and see whether the crash stops. If the crash persists with containment working, the
cause is elsewhere and Section 3 is the next place to look.

### What to find

The containment is four function hooks, installed by `net::horse_diag_install(contain=true)`
in `src/mod/net/horse_diag.cpp`. Each is a `Site`: an address **relative to the image
base**, plus the first 16 bytes expected at that address. All four must match or none are
installed — there is no partial success, which is why one bad address disables the whole
feature.

```cpp
constexpr Site kCcUpdate = {0x85FBA0,  {0x48,0x89,0x5C,0x24,0x10,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57}, "CC update"};
constexpr Site kCcPost   = {0x860D30,  {0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x56,0x57,0x41,0x56,0x48,0x83}, "CC post-update"};
constexpr Site kRestore  = {0x8646D0,  {0x48,0x8B,0xC4,0x48,0x89,0x58,0x20,0x48,0x89,0x50,0x10,0x55,0x56,0x57,0x41,0x54}, "restore actions"};
constexpr Site kPending  = {0x2329D70, {0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57}, "pending actions"};
```

`kCcUpdate` was the one that failed on 3446 (`HorseDiag: CC update (exe+0x85FBA0) not
recognised`). The other three may have matched and been thrown away with it, or may also
be stale — the log does not distinguish, because they are installed in one `&&` chain and
only the first failure is named. **Determine which of the four are stale**, rather than
assuming it is only `kCcUpdate`.

The other resolutions that also failed on 3446 are the same class of problem — a 3424
address the patch moved. None of them is believed to cause this crash, but they share a
root cause and a tool that finds one may find all:

| what failed | logged consequence | 3424 address |
|---|---|---|
| `HorseDiag` CC update | containment disabled (Section 2) | `exe+0x85FBA0` |
| `PointClimb::Enter` | wall climbs freeze | see source |
| `OtherEquipItemAck` writer | equipment changes not sent | `kServerOtherEquipWriter` = `0x29ED1F0` |
| minimap icon function | no minimap icon for the guest | `kMinimapIconDecide` = `0x9E89C0` |

---

## 3. Alternative causes, and how to tell them apart

If containment turns out to be installed correctly, or installing it does not stop the
crash, these are the next candidates in order of likelihood.

### 3a. Stale opcode for `ActorLoadDataAck`

Opcode numbers were **renumbered** in 3446 while the RTTI handler names stayed stable.
Seven opcodes had moved; this port resolved them by name:

```
RemoveActorAck   2516 -> 3067      StartActionReq   2223 -> 2202
MoveActorReq     2556 -> 2833      StartActionAck   2991 -> 2552
MoveActorAck     2697 -> 3094      RotateActorReq   2828 -> 2852
RotateActorAck   2687 -> 3078
```

`ActorLoadDataAck` was **not** among the seven that moved and stayed at `2005`, which is
what the log shows being injected. That is consistent — but "did not move" was concluded
from a name-based lookup, so **re-verify it directly**: resolve the handler for
`ActorLoadDataAck` on 3446 by RTTI and confirm it is `2005`. A wrong opcode delivered to
`ClientNet::OnRecvPacket` is exactly the kind of thing that crashes without logging.

### 3b. The captured character packet is not valid for 3446

The spawn payloads are **captured live from the guest** (15303 + 6445 bytes) and replayed.
The port rewrote actor keys inside them (`player x81`) but the *shape* of the record chain
is whatever 3446's client produces. If a struct grew a field in the patch, the replay
delivers a packet whose internal offsets are stale, and the client reads past the end.

This is worth checking because the mod already validates the shape before injecting
(`Puppet: the other player's character is not a plain player load`), and that validation
**passed** — so the top-level chain is right. The risk is in the nested records the
validator does not walk.

### 3c. The guest's gear / equip path

The mod, right after queuing the spawn, also queues `OtherUnequipItemAck` /
`OtherEquipItemAck` to dress the copy. The `OtherEquipItemAck` **writer** failed to
resolve on 3446 (Section 2 table). A partially-working equip path that emits a packet with
a wrong slot or serial could kill the client on load.

Testable independently: set `[coop] equip=0` in the host's INI and repeat. If the crash
goes away, the cause is here and the spawn itself is fine. **This is the cheapest
experiment available and should be run first**, because it needs no new addresses:

```ini
[coop]
equip=0
horse=0
```

If the crash persists with both off, the fault is in the spawn packet itself and Section 2
becomes the primary path.

---

## 4. Tools

`cdmp_probe.exe` — external, read-only memory reader. Also works offline on a copy of the
executable, which is the safe way to do static work:

```
cdmp_probe.exe rtti     <module+va>   resolve an RTTI class name
cdmp_probe.exe vtables  <ClassName>   find vtables by RTTI (exactly one match expected)
cdmp_probe.exe disasm   <module+va> [n]
cdmp_probe.exe dump     <module+va> <n>
cdmp_probe.exe troc     <begin> <end> enumerate Troc handlers in an address range
cdmp_probe.exe read     <module+va> <n>
cdmp_probe.exe --image <path-to-exe> ...    offline, no game running
```

`scripts/verify-port.ps1` — checks every offset in `src/mod/game/offsets_3446.h` against
the on-disk executable, including RIP-relative displacement arithmetic. It **cannot** catch
a runtime bug; three bugs in this port were found only in a live game.

### Three traps that cost real time in this port

1. **Section names are decoys and are reshuffled every patch.** Select code by
   `IMAGE_SCN_MEM_EXECUTE` (0x20000000) *and* by content. Never by name. In 3446, the
   section named `.tls$` is executable real code and `.debug` is a 195 MB executable
   decoy.
2. **RIP-relative arithmetic**: `target = (site + disp_offset) + 4 + disp32`. Getting the
   `+4` wrong yields a plausible-looking address that is off by four bytes.
3. **A Troc range is a range, not a shift.** 3446 has **1175 handlers** from `exe+0x6E82D10`
   to `exe+0x6EB6370`. The 3424 begin address sits 0x14690 bytes *inside* that range, so
   reusing it silently skips 576 handlers (49%). Enumerate, do not shift.

---

## 5. What to send back

Whatever the outcome, it should be reportable without the reader having a game open:

1. **Which candidate was the cause**, and the measurement that proved it — not the
   reasoning that suggested it.
2. **The address, if one was measured**, with: the value, the method (`rtti` / `disasm` /
   live read), and the surrounding instruction bytes so it can be re-checked.
3. **The log lines** on both sides of the fix, host and guest, from a run where the
   character spawns and survives 60 seconds.
4. **What is still unresolved** — the table in Section 2 is unlikely to be fully emptied,
   and an honest list of what remains is worth more than a claim of completeness.

If the crash is fixed, the change belongs upstream in this repository rather than only on
one machine: `src/mod/game/offsets_3446.h` for addresses, and a commit message that records
how each was measured. This project's git history is written that way on purpose — the
reasoning is the deliverable, because the next game patch will invalidate every one of
these numbers and the *method* is what survives.
