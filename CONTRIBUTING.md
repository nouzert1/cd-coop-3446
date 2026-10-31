# Contributing

**This project is not maintained by a team.** Issues and pull requests may never be answered. The
reliable way to continue it is to **fork it** and build your own version (keeping the GPL v3).

These notes are what you need to work on it without losing a week — mostly because losing a week is
what already happened here.

## Read first, in this order

| | |
|---|---|
| [README.md](README.md) | What works, what does not, and the one test that has never passed |
| [docs/PORTING.md](docs/PORTING.md) | How to port to a new game build — **read before touching offsets** |
| [docs/BUGS-ABERTOS.md](docs/BUGS-ABERTOS.md) | Every open problem, ordered by value per hour |
| [docs/HISTORIA-PORTES.md](docs/HISTORIA-PORTES.md) | What broke in each patch, and why the causes differed |

## Before you start

- **Game build.** Everything — offsets, signatures, message ids — is for game build
  **1.0.0.3460** (PE timestamp `0x6AE58024`, image base `0x140000000`). Write the build next to any
  new finding. A game update means finding every address again: see `docs/PORTING.md`.
- **The version guard is deliberate.** The mod refuses to read the game on an unknown build so it can
  never corrupt a save it does not understand. Do not "fix" this by removing the guard.
- **Back up your saves** (`%LOCALAPPDATA%\Pearl Abyss\CD\save`) before any test that **writes** to
  game memory or injects messages.
- **One game per PC.** For a first test use `cdmp_peer.exe` on one PC; real two-player tests need two
  PCs and two Steam accounts that own the game (see `docs/TESTE-2-PCS-2026-10-31.md`).
- **Languages.** `docs/` is English; `docs/research/` is mostly Spanish (dated research logs, some
  superseded); the kit ships Portuguese for the guest.

## Commands

```powershell
.\scripts\build.ps1              # configure, build RelWithDebInfo, run unit tests
.\scripts\check-all.ps1          # + offline port verification + two-instance loopback test
.\scripts\verify-port.ps1        # check every offset against the on-disk executable
.\scripts\deploy.ps1             # install into the game; -Remove to uninstall
.\scripts\instalar-host.ps1      # 2-PC host profile, verifies SHA256 after copy
.\scripts\pack-test-kit.ps1 -HostSteamId <SteamID64>
```

- The game ignores `WM_CLOSE`: on the title screen, close it with `Stop-Process`.
- `LoadLibrary` fails with long paths (error 206) — use a short path such as `build\e2e\`.
- Single-PC test without a second player: start `cdmp_peer.exe`, then
  `cdmp_host.exe <path\cdmp.asi> <seconds>`.

## Engineering rules

A crash is reported to Pearl Abyss by its crash handler, so these matter.

- **No inline hooks in the middle of a function** unless you use `safetyhook::create_mid` — the
  instruction may be the target of a relative jump.
- **Every read of game memory is guarded** (`VirtualQuery` and/or SEH).
- **Never identify entities across PCs by their memory address.** Use the game's actor keys
  translated by the mod, or the mod's own ids.
- **No work inside `DllMain`.** Everything runs on the worker thread.
- The loader (`winmm.dll`) is also loaded into `crashpad_handler.exe`; `dllmain.cpp` filters by
  executable name. Keep it that way.
- **Overlay:** only inline hooks (SafetyHook) on functions, never vtable patches (Streamline calls
  Present directly). Install it **deferred** — installing at startup hung the game. Test overlay
  changes with `cdmp_dx12_test.exe` before the game.
- **The protocol is serialized field by field**; bump `kVersion` so mismatched versions refuse to
  connect.
- **Safety of the people who use it:** accept Steam friends only, validate every network field
  (sizes, counts, keys), and never let the other player's data reach game functions unchecked.

## Rules of evidence

Five, each learned from a specific loss. `docs/PORTING.md` §3 has the full account.

1. **A hit is not evidence.** Confirm by surrounding context and by what the code does.
2. **A zero from a tool is not a finding** until the call form is verified against a case with a
   known answer. `troc --begin/--end` returns a clean 0 because the flags are ignored.
3. **A plausible number is the default state of an unmeasured one.** Three values in this port looked
   like results and were not: `-88.3066`, `(1.0, 0.0, 0.1745)`, `check vs game global 0.00 m`.
4. **Verify by motion.** Two position reads with the player walking must differ along the direction
   of travel. Immune to a second address being wrong.
5. **Write down the reason, not just the value.** Every entry in `offsets_3460.h` says whether it was
   measured or is inherited-and-wrong. A bare number gets trusted later by someone who has no way to
   know it was a guess.

## Writing a commit here

The git history is the project's primary record. A useful commit message says **what was measured,
how, and what the alternative explanations were that got ruled out** — not just what changed. The
most valuable commits in this repo are the ones recording a wrong turn and its cost.

## Third-party code

- `reference/` (git-ignored) was used for a clone of another co-op attempt that **has no license**: it
  may be read as a reference but none of its code may be copied. Analysis in
  `docs/ANALISIS-CrimsonDesertCoop.md`.
- New dependencies must be GPL v3-compatible and added to `kit/public/THIRD-PARTY-NOTICES.txt`.
