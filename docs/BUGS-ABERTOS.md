# Open problems, and where a contributor could start

Written for someone picking this up. Ordered by **value per hour**, not by difficulty.

Everything here is stated with what is actually known. Where a cause is unknown, it says so — in
this project, an unexplained failure has three times been mislabelled and then re-opened later.

---

## TIER 1 — blocks everything else

### 1.1 The 2-PC test has never passed

**State:** unknown cause.

> Do two PCs connect **and** does the guest see the host's character in the world?

An earlier attempt (mod builds `2BE49E66` × `1B7B429D`) connected, agreed on the build, and showed
**no character**. That was attributed at the time to the build mismatch; reading the code later
showed that attribution was **wrong** — `check_build()` only records a warning and returns, and
nothing on the spawn path reads it. So the cause of that failure is still unknown.

**What is already ruled out:**

- Version mismatch (the two builds were compared and the code path does not block).
- Position exchange (it worked; the panel showed a distance).

**Why this is first:** every other feature — shared loot, joint bosses, enemy relay — depends on the
puppet existing. If you fix only one thing, fix this.

**How to start:** run the test with packet recording on. The spawn path is
`src/mod/net/remote_puppet.cpp`, which synthesises an `ActorLoadDataAck`. Compare the bytes it emits
against a **real** `ActorLoadDataAck` captured from the game's own traffic
(`docs/research/cargas-de-ator-3446.md` — the file name is Spanish, "cargas de ator"). The most
likely defect is a field the game validates and the mod fills plausibly — the same shape as the three
false results already found in this port.

---

### 1.2 The host hang/crash

**State:** unknown cause. No crash dump has ever been captured.

Four `AppHangTransient` records in the Event Viewer, **no crash**. There is no `cdb`, `windbg`, `kd`,
`dotnet-dump` or `procdump` on the machine this was developed on, and `LocalDumps` is HKLM-only
(needs admin).

**What is known:** it happens when the other player's character is injected into the host's world.
`kit/coop/INVESTIGATION.md` carries the exact log transcript, four candidate causes with the
cheapest experiment first, and the tool invocation for each.

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
