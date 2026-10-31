# PORTING.md — how to port this mod to a new game build

**Read this when the game updates.** It will: Steam auto-updated Crimson Desert **twice** during
this project (1.0.0.3424 → 1.0.0.3446 → 1.0.0.3460). Each time, every hardcoded address broke at
once and the mod went inert — deliberately, without crashing, without touching the save.

This document is the method that worked, written so the next port is a day of work instead of a
week. It is not a list of addresses: addresses are in `src/mod/game/offsets_<build>.h`.

---

## 0. What happens when the game updates

The mod's first act is a **PE timestamp comparison**:

```
Host version: 1.0.0.3460  image base: 0x140000000  image size: 0x13EE0000  PE timestamp: 0x6AE58024
Game reader DISABLED: unsupported game build. Only networking will run.
```

**That second line is the whole diagnostic.** It is also indistinguishable from "the mod is broken"
to anyone who does not know to look for it, which is why the kit quotes it in the guest guide.

- The mod does **not** crash.
- The mod does **not** touch the save.
- Networking still runs; only game reading is off.
- No partial application of wrong offsets — the guard is all-or-nothing.

If you see this, you are porting. Nothing else is wrong.

---

## 1. The core method

> **Anchor on code proven byte-identical, confirm by surrounding context, and confirm by what the
> code DOES — never by a hit.**

A hit is not evidence. In this port, every offline route that produced a "result" produced a wrong
one at least once. The rule that saved it: **validate against something the producing code does not
control.** A raw byte dump, a second candidate, the game's own RTTI, or the thing physically moving.

### The delta is NOT a constant

Measured in the **single** 3446 → 3460 patch:

| What | Delta |
|---|---|
| Handler `.rdata` | `+0x4000` |
| Component vtables | `+0x4010`, `+0x4018` |
| Movement methods | `+0x990` |
| `GlobalVariableManager` | `+0x5680` |

Five different deltas, one patch. Three vtables agreed at `+0x4000`/`+0x4010` and the fourth did not
(`kClientActorManager` at `+0x4018`). A single delta applied to the whole table would have produced
a guard that passes *sometimes* — strictly worse than one that never passes, because it yields a
half-alive mod and a plausible-looking log.

**Do not use deltas. Resolve each address by its class or its prologue, and confirm by behaviour.**

### Struct offsets survive; addresses do not

Every struct offset the headers describe survived 3424 → 3446 → 3460 unchanged:
`kWorldSystem_ActorManager 0x30`, `kActorManager_ControlledActor 0x50`, `kActor_ComponentTable 0x68`,
`kComponents_CharacterControl 0x40`, `kActor_Key 0x60`.

Data globals and code addresses did not. Expect this split.

---

## 2. Step by step

### Step 1 — record the new build's identity

```powershell
(Get-Item "<game>\bin64\CrimsonDesert.exe").VersionInfo.FileVersion   # 1.0.0.3460
```

Then get the PE timestamp, image base and size from `cdmp_probe --image` or from the mod's own log
line above. **Write these into the new `offsets_<build>.h` before anything else.** The version guard
is built from them and nothing else works until it passes.

### Step 2 — check what did NOT move, and prove it

Cheapest first, because a whole class of work disappears if it holds:

- **RTTI class count.** 15262 on 3446, 15262 on 3460. Use `cdmp_probe classes <substring>`. If the
  class structure is untouched, every class the mod looks up by name still exists.
- **`.text` size.** The 3446 → 3460 shrink was the `.debug` section (a 195 MB decoy), not code.
  `.text` moved by hundreds of bytes.

### Step 3 — vtables, by RTTI

For each class the mod needs:

```powershell
cdmp_probe --image <exe> classes <ClassName>     # TypeDescriptor
cdmp_probe --image <exe> vtables <ClassName>     # the vtable address
```

**MSVC x64 RTTI chain**, if you need to read it by hand: `[vt-8]` is an absolute pointer to the
CompleteObjectLocator; `COL+0x0C` is the TypeDescriptor RVA; the name starts 20 bytes after the
descriptor. Vtable slots are absolute.

### Step 4 — code addresses, by prologue + behaviour

Never by resemblance. For each hooked function:

1. Find the old address's bytes in the new binary.
2. Confirm the **surrounding context** also matches, not just the first 16 bytes.
3. Confirm **what it does** — observe it live.

### Step 5 — data globals: the hard part

This is where the 3460 port lost the most time, and where the method matters most.

**What failed, with reasons:**

| Route | Why it failed |
|---|---|
| Apply a delta | Five different deltas (see above). |
| `xrefs` on the old address | Reports the *shifted operand*, not the instruction start. Three "sites" were one instruction. |
| `scan` for the handler vtable pointer | The instances are initialised at load time; only the *loaded* image has them. |
| Assume `.data` did not move because xref counts matched | Xref count was identical on both builds. Produced a wrong conclusion. |
| Accept a value that looked plausible | `-88.3066` looked like a coordinate. It was a pointer. `(1.0, 0.0, 0.1745)` looked like a position. It was a direction vector. |

**What worked:**

1. **Sweep the mod's own data range and identify the slot by what it POINTS AT.** For
   `kWorldSystemSlot`, a heap scan found exactly one live `ClientActorManager` (its vtable is
   unique). Then sweep `[0x6000000, 0x10000000)` for a pointer-to-pointer whose target's
   `[+kWorldSystem_ActorManager]` is that manager.

2. **Trace the chain live, hop by hop, with an RTTI check at each hop.** Then make the thing move.

3. **Verify by MOTION.** This is the strongest control available and it is immune to a second
   address being wrong:

   ```
   reading 1: (-20549.8086, 587.6920, -6922.1904)
   reading 2: (-20517.7422, 579.1594, -6952.5029)     ~45 m walked
   ```

   A wrong address does not follow the player. **Use this instead of the `kStaticPlayerPos`
   self-check whenever that global is compromised** — which it is on 3460.

### Step 6 — the Troc array

The opcode numbers renumber per build and the mod resolves them at runtime, so verify by finding
the array, not by trusting a number.

```powershell
cdmp_probe --pid <pid> troc <begin> <end>       # POSITIONAL. No --begin/--end.
```

On 3460: `0x6E86D10` … `0x6EBA378`, **1175 handlers, span `0x33660`** — byte-identical span to 3446,
shifted `+0x4000`. Confirm by reading opcodes for handlers whose names you know.

---

## 3. The failure modes, named

Every one of these cost real time in this port.

### A confident zero from an ignored option

`troc --begin X --end Y` returns 0. A 0 from a **silently ignored argument** is indistinguishable
from a **real finding that the thing is absent**. Before believing any zero, verify the call form
against a case where you already know the answer.

### A plausible number that is not a measurement

Three times in one port:

| Value | Looked like | Actually |
|---|---|---|
| `-88.3066` | a coordinate | a pointer read as f32 |
| `(1.0, 0.0, 0.1745)` | a position | a normalised direction vector |
| `check vs game global 0.00 m` | perfect verification | the struct default; the check never ran |

**In this codebase, a plausible number is the default state of an unmeasured one.** An abstention
must not print the same way as a pass — hence `static_pos_error` defaults to `-1` and prints `n/a`.

### `+ local changes` when the tree was clean

The dirty flag is computed at **CMake configure time** from `git status -- porcelain -- src`. A
binary built while a diagnostic sat uncommitted in `src/` genuinely carries `+ local changes` — and
keeps carrying it after the file is committed, because the flag is baked in. Not a bug; a true
statement about a state that no longer exists.

### Section names are decoys

They are reshuffled every patch. Select code by `IMAGE_SCN_MEM_EXECUTE` and by content, never by
name.

---

## 4. What the 3460 port could not recover

Four data globals were re-measured and their objects **left the region** where 3446 kept them. This
is not displacement; the region was reorganised. Measured values in
[`research/globais-3460.md`](research/globais-3460.md).

| Global | Holds on 3460 | Feature lost |
|---|---|---|
| `kCameraSlot` `0x70CDEA8` | `"common.v"` (UTF-16 text) | guest camera → puppet unrotated |
| `kMinimapIconRoot` `0x71B1DD8` | `0xFFFF` | minimap icon |
| `kMinimapIconRootAlt` `0x71B1DE0` | `0x0` | — |
| `kClientFrameClockMs` `0x70CDCE1` | `0xB000000000000200` | time sync |
| `kStaticPlayerPos` `0x71C0C20` | two pointers | the self-check |

A sweep of `[0x70C0000, 0x71D0000)` identifying each by a property only the real object can have
returned **zero candidates in all four categories**, with a valid reference position and verified
working reads. That is a real result, not a broken sweep.

### Two ways to settle them later

1. **Find each object by its CONSTRUCTOR.** Locate the function that writes the slot on the old
   build, re-find it on the new build by prologue. A writer is more stable than a reader, and the
   address it writes is in the instruction.
2. **Find the object first, then what points at it.** Scan the heap for the RTTI names
   (`MinimapIcon`, `Camera`), as the live `ClientActorManager` was found. If the objects exist, the
   slot referencing them is findable from what points at them.

**Do not retry** "the `.data` section did not move because these addresses still have xrefs".

### A byte misalignment worth knowing about

```
0x70CDCE8: 0x2748813B0
0x70CDCE9: 0x0002748813      <-- what the old table reads
```

The clock's microsecond counter starts one byte earlier than the table says. The mod reads the
byte-shifted value and gets a number that **passes its own guard** (`< 1e9`). A check written against
the right value read from the wrong place will not catch itself.

---

## 5. When you finish a port

1. `.\scripts\build.ps1` — must report `Build OK` and 2/2 tests.
2. Run the mod live and confirm:
   - `Game reader enabled (build <new>)`
   - `Local player: in world`
   - a real position that **changes when you walk**
3. `.\scripts\instalar-host.ps1` — installs and verifies SHA256 after copy.
4. `.\scripts\pack-test-kit.ps1 -HostSteamId <id>` — refuses if the build id does not match `HEAD`.
5. Update the version strings the **guests** read: `kit/coop/INSTALL.md` and the Portuguese
   quick-start generator in `scripts/pack-test-kit.ps1` (search for `PASSO 0`). Both were missed
   once and shipped a kit telling the guest to verify the wrong build.

**Verify the kit, not the script that generates it.** An earlier revision had correct script logic
and a kit that told the guest to check for `1.0.0.3446`.

---

## 6. Reference implementations

| File | What it shows |
|---|---|
| `src/mod/game/offsets_3460.h` | A completed port: every global marked measured or wrong, with the reason |
| `src/mod/game/player_reader.cpp` | The actor chain, and how the position moved from a pointer chase to an inline field |
| `docs/research/porte-3460.md` | The 3446 → 3460 port, six sections, raw log lines |
| `docs/research/globais-3460.md` | The four globals, measured, with what each consumer does when wrong |
| `docs/research/troc-rtti.md` | How the Troc dispatch was reverse-engineered |
| `docs/HISTORIA-PORTES.md` | Every port so far, what broke, what the cause turned out to be |
