# Open problems, and where a contributor could start

Written for someone picking this up. Ordered by **value per hour**, not by difficulty.

Everything here is stated with what is actually known. Where a cause is unknown, it says so — in
this project, an unexplained failure has three times been mislabelled and then re-opened later.

**Last updated 31 Oct 2026, after the final 2-PC test. `/docs/DOSSIE.md` is the fuller record;
this file is the work queue.**

---

## TIER 1 — blocks everything else

### 1.1 The host dies when the guest's character is injected ⭐ **the one real blocker**

**State:** unknown cause, but **isolated to 174 ms and to a single code path.**

This replaces the old entry "the 2-PC test has never passed", which is no longer accurate. Three
2-PC tests on 31 Oct 2026 established much more than that entry claimed:

| | Result |
|---|---|
| Both games open, reach the world | ✅ |
| Steam session connects, rtt ~30 ms | ✅ |
| Position read correctly on both machines | ✅ |
| **Guest sees the host's character and survives** | ✅ `co-op: other player loaded` |
| **Host receives the guest's character, injects it, and the process dies** | ❌ |

So the direction guest←host **works**. The direction host←guest kills the host. That asymmetry is
the problem, and it did not exist in the old entry.

**The exact sequence**, from `docs/research/crash-final-2026-10-31-1817-host.log`:

```
[18:17:25.484] Co-op: received the other player's character (39795 bytes, spawn 1)
[18:17:25.487] Puppet: rewrote keys in user packet: user x3, player x104, body x0
[18:17:25.487] Puppet: rewrote keys in body packet: user x4, player x104, body x8
[18:17:25.487] Puppet: spawn queued at (-20626.6, 621.3, -6813.7) (2 packets, 16637 + 6445)
[18:17:25.510] Inject: delivered opcode 2005 (16642 bytes) to ClientNet::OnRecvPacket
[18:17:25.510] Inject: delivered opcode 2005 (6450 bytes) to ClientNet::OnRecvPacket
                >>> END OF LOG. THE PROCESS DIED HERE. <<<
```

**What this rules out**, and each was a live hypothesis before:

- Not the mod stalling in the injection — **both injections completed and returned**.
- Not a catchable exception — the `__try/__except` around the injection did **not** fire.
- Not a silent `TerminateProcess`/`ExitProcess` — the exit watch did not record one.
- Not the position — it arrived correct, `(-20626.6, 621.3, -6813.7)`, not `(0,0,0)`.

**What is left:** the game accepts the packet, begins creating the actor, and dies inside its own
processing of it.

**How to start — do this first:**

Enable packet recording in `cdmp.ini` and reproduce:

```ini
[sniffer]
enabled=1
record=1
```

This captures the exact bytes to `cdmp_packets_<date>.log` and `.bin`. **It has never been used in
any test so far**, and the 23 ms timing now makes the capture viable — you know the instant to look
at. Compare the mod's `ActorLoadDataAck` byte for byte against a **real** one captured from the
game's own traffic. `docs/research/cargas-de-ator-3446.md` documents the format.

**The strongest unexplained clue** — the payload sizes differ between sessions for the same
character:

| Session | user | body |
|---|---|---|
| 17:11 host | 16932 | 6445 |
| 17:11 guest | 16500 | 6453 |
| 18:17 host | 16637 | 6445 |

The guest survived injecting `16500+6453`; the host died on `16637+6445`. If the packet format were
simply wrong, the size is where it should show. **This asymmetry has never been investigated.**

**Second tool:** there are crash dumps for real crashes at
`%LOCALAPPDATA%\CrashDumps\CrimsonDesert.exe.<pid>.dmp`. **WinDbg is installed.** `!analyze -v`
gives module, offset and stack in minutes. It will not give the "why", but it collapses the search
space.

**Code:** `src/mod/net/remote_puppet.cpp` — packet synthesis and the key rewrite.

---

### 1.2 The host hang/crash — **this entry is now 1.1**

Merged into 1.1 above. The former text described four `AppHangTransient` records with no crash and
no dump; crash dumps **do** exist now, and WinDbg is installed on the development machine.

One thing from the old entry worth keeping: on the 17:11 run the host died immediately after
`Inject: delivered opcode 2005 (16937 bytes)`, **while the guest passed through the equivalent
injection and survived**. Same asymmetry, same open question.

---

### 1.3 The `RaiseException` hook — **FIXED, do not reintroduce**

Closed 31 Oct 2026. Recorded here because it was Tier 1 and because the lesson is worth more than
the fix.

Both players' games died **before the main menu**, on two different machines, on build `A8AE702B`.
Comparing against the build that had worked earlier the same day left **exactly one change**:

```
src/mod/game/exit_watch.cpp | 186 +++
src/mod/game/exit_watch.h   |  34 +++
src/mod/mod.cpp             |   6 ++
```

`RaiseException` is not an error path. The MSVC C++ runtime raises it as ordinary control flow —
thread naming, every `throw`, SEH probes — thousands of times during a healthy startup. The hook
ran a logging call and a stack walk inside exception dispatch, on a thread that may hold the CRT or
loader lock, and did it again on every subsequent raise.

Fixed in `D7FE9358`. The exit hooks now write into a fixed pre-allocated buffer with no allocation,
no locks and no formatting. `tests/exit_watch_self_test.cpp` verifies that `RaiseException` is
**not** patched and survives **2000 consecutive throws**, and fails loudly if it ever is.

**The part worth remembering:** the self test passed throughout, because it called the patched
function once from a quiet thread — the one situation in which that failure cannot appear.
"It compiles, it installs, and the test passes" was true of a hook that broke two people's games.

---

## TIER 2 — features that fail closed

These are **not** defects. The mod deliberately refuses to operate when it has no trustworthy
data. Each is a candidate for recovery, not a bug report.

| Feature | Guard / symptom | Where |
|---|---|---|
| Remote puppet rotation | `rot (0.000, 0.000, 0.000, 1.000)` — no basis computed | `src/mod/game/player_reader.cpp` |
| Time sync | `clock offset unknown` | 3460 offsets unrecovered |
| Minimap icon | `Minimap: icon function not recognised` | 3460 offset unrecovered |
| Horse | `HorseDiag: CC update (exe+0x941D40) not recognised` | 3460 offset unrecovered |
| Enemy copies | `Enemy relay: wanted but not started` | 3460 offset unrecovered |
| Game error logging | `Game errors: logger not recognised; not hooked` | 3460 offset unrecovered |
| `OtherEquipItemAck` | `Capture: OtherEquipItemAck writer not recognised` | **Also wrong on 3446** — the route is the `TrocTrOtherEquipItemAck` handler |

None of these prevent connecting. `docs/PORTING.md` has the method for recovering offsets.

---

## TIER 3 — never exercised

- The `Ctrl+Home` lab test with natives — **never run**, see `CAMPO-HORA-NAO-EXERCITADO.md`
- Joint bosses (phase D2): boss copy record types **4 and 7**
- Vehicles (type 5) — deliberately deferred

**Highest-value contribution:** get a stack. If you have a Windows debugging setup, that alone may
close this.

---

## TIER 2 — measured, fixable, self-contained

### 2.1 `kServerOtherEquipWriter` is wrong on **every** build, including 3446

**State:** confirmed broken. Equipment changes have never been relayed, on any build.

`offsets_3446.h` declares a 16-byte signature for this writer. Live, the bytes at the declared
address **do not match one byte of it**. `capture_install_equip_hook()` memcmps, so it always failed,
silently, since the hook was written.

The signature cannot re-find it: **12+ hits per binary**, all the same inlined `std::unique_lock`
idiom. That is why a byte signature was the wrong tool here.

**Where to start:** the `TrocTrOtherEquipItemAck` handler. The writer must be the function that
fills that message. Find the handler in the Troc array, look at what it calls, and the writer is one
of the few functions it reaches with a buffer in `rcx`.

**Why it is worth doing:** it is a complete feature (equipment appearance on the remote character)
gated on one address.

---

### 2.2 Recover the four globals lost in the 3460 port

**State:** measured, and the objects are not where 3446 kept them.

| Global | Holds today | Feature lost |
|---|---|---|
| `kCameraSlot` `0x70CDEA8` | `"common.v"` | guest camera → puppet unrotated |
| `kMinimapIconRoot` `0x71B1DD8` | `0xFFFF` | minimap icon |
| `kClientFrameClockMs` `0x70CDCE1` | junk | time sync |
| `kStaticPlayerPos` `0x71C0C20` | two pointers | the self-check |

All three consumers **fail closed** — they do not produce wrong values, they turn themselves off.
So these are missing features rather than bugs, and they do not block the 2-PC test.

**Two routes, both in [`PORTING.md`](PORTING.md) §4.** The cheaper one is: scan the heap for the RTTI
names and find what points at the objects, rather than searching the data region for a value.

**`kStaticPlayerPos` is special:** it is the mod's self-check (derived position vs a second global).
Losing it means losing the automatic verification that the position is right. The replacement is
**verification by motion** — see `PORTING.md` §2 step 5 — which is stronger, but manual. Recovering
this global would restore an automatic check, and is the most valuable of the four.

---

### 2.3 `kMinimapIconDecide` was already wrong on 3446

**State:** known wrong since before the 3460 port.

In use: `0x9E8A7D`. The declared head's only hit: `0x9E89BD`. Nobody re-measured it. Same class of
error as 2.1: a declared address that does not match the instruction actually being called.

---

### 2.4 `kClientPostPacket = 0x3A55B0` is mid-instruction on 3446

**State:** recorded as a suspicion. **Never verified.**

If true, the sniffer is hooking the wrong byte — which would not crash (SafetyHook would likely fail
the install) but would mean a whole capture path is off. Worth 20 minutes with
`cdmp_probe --image <exe> disasm`.

---

### 2.5 `kFieldTimeClient` — unresolved

**State:** unknown. Carried through two ports without being settled. There is a
`scripts/check-fieldtime.ps1` that exists specifically to check it, and it has not produced a
conclusion recorded in `docs/`.

---

## TIER 3 — features half-built

### 3.1 Joint bosses

**State:** **half**. The guest sees the boss and damages it; the guest's own quest does not advance
and no loot drops for the guest.

This is deliberate in part — the design says the guest's quest is not affected ("isso nao afeta o
convidado no sentido de suas missoes"). But "sees and damages" without "gets loot" is a half-feature,
and `docs/JEFES-POR-QUE-NAO-FECHA.md` explains why.

**Remaining work (J3):** boss copy record types **4** and **7**. Type 5 (vehicles) is deliberately
deferred — the dragon is type 5.

**A trap avoided already:** `kMaxLoad = 16*1024` was questioned and then **closed by measurement** —
13890 `ActorLoadDataAck` records, 0 truncated, max payload 11997 for types 3/6, 4387 bytes headroom.
23 KB records are all type 7, routed separately. Do not re-open this without new data.

---

### 3.2 Shared loot

**State:** implemented, protocol-proven between two instances on one PC, **never confirmed live**.

Boss-loot refusal is correct by design. Guest loot from common enemies is the untested part.
Depends on 1.1.

---

### 3.3 The `layer_without_action` containment is permanent, not one-shot

**State:** known behaviour, unclear whether intended.

Live on 3446, the player copy `0xA010F001` was stuck with:

```
L0 chart=true cur/play=false | L1 chart=true cur/play=false | pending=0 list=true restoreByte=0
```

Once containment engages it does not release. Worth deciding whether that is the design or a bug.

---

## TIER 4 — suggested improvements (nobody has started these)

These are opinions, marked as such. They are things that would have saved time in this project.

### 4.1 Make the build bit-reproducible

Today, two builds of the same commit produce different SHA256s (575 KB of difference, caused by
MSVC's parallel `.obj` merge order reordering the string pool). It does not affect compatibility —
the mod compares `kModBuild`, not a hash — but it means **you cannot verify that a binary matches a
commit**, which is a real supply-chain weakness for a mod people install into a game.

Possible fixes: `/Brepro` (MSVC reproducible builds), a deterministic link order, or a
`SOURCE_DATE_EPOCH`. Worth trying; if it works, `SHA256SUMS.txt` becomes a meaningful attestation
instead of only "this is the file I tested".

### 4.2 Add an automated "is the build still alive" check

The failure mode when the game updates is **silent and correct**: the mod refuses to install, the
network keeps running, and only the reader is off. A user cannot tell this from a broken mod.

A one-line check that posts a GitHub issue — or, simpler, a `scripts/check-build.ps1` that compares
the installed game's PE timestamp against the newest `offsets_*.h` — would turn a support thread
into a one-command answer.

### 4.3 Offsets should be verified in CI

`scripts/verify-port.ps1` exists and checks every offset against the on-disk executable. It is not
run automatically. If it ran on every push (it needs a copy of the `.exe`, which cannot be shipped),
a bad offset would fail the build rather than the live test.

A cheaper version: keep a table of **expected RTTI class counts and vtable deltas** per build, and
assert them. Those are derivable from any dump and do not need the executable in the repo.

### 4.4 The research notes are in three languages

`docs/research/` is mostly Spanish, `docs/` is English, and the kit ships Portuguese. This was
pragmatic while one person worked on it and is a barrier now. At minimum,
`docs/research/README.md` should index which notes are still current — several are dated research
logs whose conclusions have since been superseded, and a reader cannot tell which.

### 4.5 The three false results deserve a test

Three times, a value that merely *looked* like a result was accepted:

- `-88.3066` as a position (a pointer as f32)
- `(1.0, 0.0, 0.1745)` as a position (a direction vector)
- `check vs game global 0.00 m` as a passing check (a struct default)

The third has a structural fix (`static_pos_error` defaults to `-1`, prints `n/a`). The first two do
not. A `math::looks_like_position()` helper — finite, within the map bounds, not a unit vector, not a
pointer pattern — used at every position read would catch them mechanically. It is a small function
and it addresses the single most expensive failure mode in this codebase.

---

## How to work on this without losing a week

Five rules, each learned from a specific loss:

1. **A hit is not evidence.** Confirm by surrounding context and by what the code does.
2. **A zero from a tool is not a finding until you have verified the call form** against a case with
   a known answer. `troc --begin/--end` returns a clean 0.
3. **A plausible number is the default state of an unmeasured one.** Check against something the
   producing code does not control.
4. **Verify by motion.** Two reads with the player walking must differ in the direction of travel.
   This is immune to a second address being wrong.
5. **Write down the reason, not just the value.** Every entry in `offsets_3460.h` says whether it was
   measured or is inherited-and-wrong, and why. A bare number gets trusted later by someone who has
   no way to know it was a guess.
