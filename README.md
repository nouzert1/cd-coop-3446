# cd-coop-3446 — Crimson Desert co-op, ported to game build 1.0.0.3446

Unofficial two-player co-op mod for **Crimson Desert** (PC / Steam), in C++20, loaded as
`cdmp.asi` through Ultimate ASI Loader.

This is a **fork of [ByJunter/CrimsonDesertMultiplayer](https://github.com/ByJunter/CrimsonDesertMultiplayer)**
(the original author stopped developing it and released it under the GPL v3 so others could
continue). This fork exists for one reason: the game auto-updated from **1.0.0.2976 → 1.0.0.3424
→ 1.0.0.3446**, and every hardcoded address in the original is wrong for those builds. The mod
does not silently misbehave on a build it does not know — it refuses to install — so on 3446 the
original simply does nothing.

**This repository is the working state of that port, published so someone else can pick it up.**
It is not a finished product. Read [Where this stopped](#where-this-stopped) before you spend time
on it: there is one known bug at the time of writing, it is described precisely, and it is the
most useful place to start.

---

## Current status (honest)

| Feature | State |
|---|---|
| Two players connect over Steam | **Works.** Verified live: `connected`, rtt ~40-70 ms, relay 100 |
| Both players see the other's position | **Broken as of the last test** — see below |
| Joint exploration | Blocked by the position bug |
| Host's quests unaffected by the guest | Works by design |
| Shared loot | Implemented, protocol-proven between two instances, **not yet confirmed live** |
| Bosses together | **Half.** Guest sees and damages the boss and the host's quest is safe, but the guest's own quest does not advance and no loot drops for the guest |
| On-screen name over mouse | Broken (camera block moved; diagnostics only) |

### Where this stopped

The last live test connected, agreed on the build, and still showed no character. The host's log
showed both halves of the problem in adjacent lines:

```
Local player: in world
Local player: physics basis not a rotation
Local: pos (-10606.81, 620.70, -3826.01) ... | check vs game global 0.05 m
```

The position read was **correct to 5 cm** and **did not change for tens of seconds** while the
host was walking. Grouping every sample from that session:

| samples | position |
|---|---|
| 17× | −10606.81, 620.70, −3826.01 |
| 12× | −10626.67, 619.96, −3818.66 |
| 5×  | −10626.80, 619.06, −3821.20 |

**Cause:** `src/mod/game/player_reader.cpp` validated the character's axis basis for orthonormality
and returned early when it failed — discarding a position read from the same call, which does not
depend on the basis at all. The check ran at the default tolerance `0.02f` while
`camera_reader.cpp` already used `0.05f` for the same kind of game-provided basis, so roughly half
of all reads failed.

**Fix applied** (commit `270e2cc`): the basis no longer gates the position, the tolerance is
`0.05f`, and an unusable basis leaves the rotation at the identity instead of dropping the sample.
A regression test pins the tolerance from both sides.

**Not yet verified in a live game.** That is the next step and it needs two PCs. If you are
picking this up, do that first.

---

## How it works

Crimson Desert is single-player but keeps the client/server architecture of the MMO it grew out
of: the client talks to an in-process "server" through internal messages, internally called
**Troc**.

- `src/mod/net/troc_sniffer.cpp` — mid-function hooks on the two functions that carry every
  client↔server message. It reads them and injects new ones.
- `src/mod/net/local_capture.cpp` — your movement and action messages, plus data read from game
  memory (gear, weapon, horse, rope).
- `src/mod/net/coop.cpp`, `src/common/*` — the protocol, a reliable fragmented channel, sessions,
  and transports (UDP for single-PC tests, Steam for real games).
- `src/mod/net/remote_puppet.cpp` — builds a copy of the other player the way the original server
  did (`ActorLoadDataAck`) and replays their messages as the server would have relayed them.
- `src/mod/net/enemy_relay.cpp`, `native_suppress.cpp`, `guest_hits.cpp` — the shared-enemy zone,
  host-authoritative: the host's enemies are copied to the guest and the guest's hits go back.

The connection is **Steam friends only**, through `ISteamNetworkingMessages`. Direct connections
are disabled, so neither player sees the other's IP; traffic relays through Valve.

### Room codes

The host creates a Steam lobby and the mod turns its id into a 7-character code in Crockford
base32 (no I, L, O or U). Steam lobby ids are **57-bit** values (`0x0186_0000_75C8_6F5D`), not small
integers — the codec encodes the low 32 bits and ORs the constant high bits back on decode.
`tests/tests.cpp` pins this against a real captured lobby id, because a one-hex-digit slip in that
constant still round-trips internally and only a real id catches it.

The code changes on **every** host restart (the lobby id increments each launch), so for repeated
testing `[steam] peer_steamid` is the better mechanism: the guest connects straight to a SteamID64
and needs no code at all. With neither set, the mod falls back to connecting to the only Steam
friend currently playing Crimson Desert.

---

## Building

Requirements: Windows 10/11 x64, **Visual Studio 2022** (or Build Tools) with "Desktop development
with C++". Dear ImGui and SafetyHook (with Zydis) are fetched by CMake on first configure.

```powershell
.\scripts\build.ps1        # configure, build RelWithDebInfo, run unit tests
.\scripts\check-all.ps1    # + offline port verification + two-instance loopback test
```

Install into the game (`bin64`), game closed:

```powershell
.\scripts\deploy.ps1 -GameDir "<Steam>\steamapps\common\Crimson Desert\bin64"
.\scripts\deploy.ps1 -Remove
```

Single-PC testing without a second player: `cdmp_peer.exe --mode relay --delay 50`, with
`[net] transport=udp` and `[coop] enabled=1`.

Building the two-PC kit:

```powershell
.\scripts\pack-test-kit.ps1 -HostSteamId <SteamID64>   # -HostSteamId optional
```

Both players **must** use the same ZIP: the mod compares a build id on connect and refuses to pair
when they differ. The packer refuses to build a kit from a binary whose build id does not match
`HEAD`, because that mismatch shows up at the far end as nothing but an unexplained refusal.

---

## Live verification tooling

The offline verifier reads the shipped `.exe` and never runs the mod, so it cannot catch anything
that only appears at runtime. Three real bugs in this port were invisible to it and found only in
a running game.

- `scripts/verify-port.ps1` — checks every offset against the on-disk executable (RIP-relative
  displacement arithmetic, section flags, code-vs-data).
- `tools/probe/` → `cdmp_probe.exe` — external read-only memory reader. `read`, `dump`, `disasm`,
  `rtti`, `vtables`, `classes`, `scan`, `troc`. Use `--image <path>` to work offline.
- `scripts/port-3424-probe.ps1` / `PORT-3424-probe.txt`, `PORT-3446-live.txt` — the porting
  transcripts, including which addresses were measured how.

**Section names in this binary are decoys and are reshuffled every patch.** Select code sections
by `IMAGE_SCN_MEM_EXECUTE` and by content, never by name.

---

## Engineering rules

These exist because breaking them crashes the game, and `CONTRIBUTING.md` has the full set:

- No inline hooks mid-function (`safetyhook::create_mid`) — the instruction may be the target of a
  relative jump.
- Every game memory read is guarded (`VirtualQuery` + SEH).
- Never identify an entity across two PCs by its memory address.
- No work in `DllMain`.
- Bump `kVersion` for any protocol change, and serialize field by field.
- The version guard is a **PE timestamp comparison** and refuses to install on an unknown build, on
  purpose, so the mod can never corrupt a save it does not understand.

---

## Layout

| Folder | Contents |
|---|---|
| `src/common/` | Protocol, reliable channel, session, transports, clock (shared, unit-tested) |
| `src/mod/` | The mod: startup, config, overlay, memory reading, network, co-op |
| `src/mod/game/` | One header per game build (`offsets_3446.h`) plus readers |
| `tools/peer_sim/` | `cdmp_peer.exe` — relay/echo to test on one PC |
| `tools/host/` | `cdmp_host.exe` — loads `cdmp.asi` without the game |
| `tools/probe/` | `cdmp_probe.exe` — external, read-only memory reader |
| `tests/` | Unit tests |
| `scripts/` | Build, verify, deploy, packaging (PowerShell) |
| `kit/` | Config files and texts shipped in the packages |
| `docs/` | Roadmap and test plans; `docs/research/` has the dated research notes |

---

## Safety and privacy

- The mod only talks to the other player, through Steam networking, and accepts only Steam friends.
  No telemetry, no server of its own.
- Packet recording (`[sniffer] record`) is **off** by default. When on, captures and `cdmp.log`
  contain in-game data (positions, actor keys) — review before sharing.
- **Back up your saves** (`%LOCALAPPDATA%\Pearl Abyss\CD\save`) before testing, and do not save
  while the other player is in your world. That is the most likely way to damage a save.

---

## License

GPL v3, inherited from the original project — a modified version you publish must ship its source
under the same license. See [LICENSE](LICENSE).

Original work Copyright (C) 2026 ByJunter. Port to 1.0.0.3446 and subsequent fixes: see the git
history, which is written as a record of what was measured and why.

Third-party components keep their own licenses: Ultimate ASI Loader (MIT), Dear ImGui (MIT),
SafetyHook (BSL-1.0), Zydis and Zycore (MIT).

*Crimson Desert and Pearl Abyss are trademarks of Pearl Abyss Corp. This project is not affiliated
with or endorsed by Pearl Abyss and contains no game files or game content. Steam is a trademark
of Valve Corporation.*
