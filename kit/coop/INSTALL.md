# INSTALL.md — instructions for an automated agent

This file is written for an AI coding agent (Claude Code, Codex, Cursor, or similar)
installing the Crimson Desert co-op mod on a Windows PC. A human-readable guide is in
`COMECE-AQUI-PORTUGUES.txt`; this file is the mechanical version, with exact commands and
verification steps.

**Read all of it before running anything.** Step 0 is not optional.

---

## Step −1 — prove this is the kit you think it is

**Run this before anything else, including the backup.**

Earlier kits are still installed on some machines, and their copies of this file and of
`INVESTIGATION.md` are still sitting in the game folder. An agent that reads one of those
old files gets an old required build — and the obvious reading of "required build 1.0.0.3446"
on a 1.0.0.3460 game is to stop, or worse, to propose downgrading the game. That has already
happened once. So identify the kit by its contents, not by which file you happened to open.

```powershell
$kit = $PSScriptRoot   # or wherever you extracted this kit; adjust if needed
Get-FileHash "$kit\cdmp.asi" -Algorithm SHA256 | Select-Object -ExpandProperty Hash
```

| Result | Meaning |
|---|---|
| `{{ASI_SHA256}}` | **This is the current kit.** Continue to Step 0. |
| `70C5436365410668ED5998BB446DA4A11304A903BCC2A5AE90128EA0DD308FBE` | A kit from before 31 Oct 2026. It has the spawn crash that the current one fixes. **Discard it and get the current kit.** |
| anything else | Not a kit this document describes. Stop and ask. |

### If the game folder already has old kit files in it

Files from a previous kit may still be in `bin64` (`INSTALL.md`, `INVESTIGATION.md`,
`LEIA-ME.txt`, `README.txt`, `COMECE-AQUI-PORTUGUES.txt`, `SHA256SUMS.txt`). They describe
a different build and will mislead you. List them before starting:

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Get-ChildItem $game -Force |
  Where-Object { $_.Extension -in '.md', '.txt' } |
  Select-Object Name, Length, LastWriteTime | Sort-Object LastWriteTime
```

Anything dated before the kit you are installing is stale. The mod itself reads none of
these files — deleting them is safe, and this kit's own copies replace them.

---

## Facts you need

| Item | Value |
|---|---|
| Game | Crimson Desert, PC, Steam |
| Required game build | **1.0.0.3460** (PE timestamp `0x6AE58024`) |
| Mod binary | `cdmp.asi` (x64, C++20, GPL v3) |
| ASI loader | `dinput8.dll` in this kit — **must be renamed to `winmm.dll`** |
| This build id | `{{BUILD_ID}}` |
| `cdmp.asi` SHA256 | `{{ASI_SHA256}}` |
| Config file | `cdmp.ini` (UTF-16 LE) |
| Log the mod writes | `<game>\bin64\cdmp.log` |
| Save folder | `%LOCALAPPDATA%\Pearl Abyss\CD\save` |

Every address in this build is valid **only** for game build 1.0.0.3460. On any other
build the mod refuses to install itself, on purpose, and writes the reason to `cdmp.log`.
It will not crash and will not touch the save.

---

## Step 0 — back up the save (do this first)

```powershell
$save = "$env:LOCALAPPDATA\Pearl Abyss\CD\save"
$dest = "$env:USERPROFILE\Desktop\CD-save-backup-$(Get-Date -Format yyyyMMdd-HHmm)"
if (Test-Path $save) { Copy-Item $save $dest -Recurse -Force; "Backed up to $dest" }
else { "No save folder found at $save - the game may not have been run yet." }
```

Confirm the copy exists before continuing. This mod is experimental and has not been
widely tested. This is the only step that protects the user's progress.

---

## Step 1 — locate the game's `bin64`

```powershell
$candidates = @()
$candidates += Get-ChildItem "C:\Program Files (x86)\Steam\steamapps\common" -Directory -ErrorAction SilentlyContinue
Get-Content "C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf" -ErrorAction SilentlyContinue |
  Select-String '"path"' | ForEach-Object {
    if ($_ -match '"path"\s+"([^"]+)"') { $candidates += Get-ChildItem (Join-Path $matches[1] 'steamapps\common') -Directory -ErrorAction SilentlyContinue }
  }
$game = $candidates | Where-Object { $_.Name -like 'Crimson Desert*' } | ForEach-Object { Join-Path $_.FullName 'bin64' } |
        Where-Object { Test-Path (Join-Path $_ 'CrimsonDesert.exe') } | Select-Object -First 1
$game
```

`$game` must end in `bin64` and contain `CrimsonDesert.exe`. If it is empty, ask the user:
in Steam, right-click Crimson Desert > Manage > Browse local files, then open `bin64`.

**Verify the game build before installing anything:**

```powershell
(Get-Item "$game\CrimsonDesert.exe").VersionInfo.FileVersion
```

It must report `1.0.0.3460`. If it does not, **stop** and tell the user: the mod does not
support their build, and running it would do nothing. All offsets are build-specific.

---

## Step 2 — check for conflicts (stop if either is true)

```powershell
Test-Path "$game\winmm.dll"     # must be False
Test-Path "$game\dinput8.dll"   # must be False
```

If `winmm.dll` already exists, **stop and report it**. Another mod is using that filename;
whichever loads first wins and the other silently does nothing. Do not overwrite it
without asking the user.

If `dinput8.dll` exists, another ASI loader is already installed. The mod will still work
if that loader is Ultimate ASI Loader, but ask the user before replacing it.

---

## Step 3 — install

The game **must not be running**: the `.asi` cannot be replaced while it is loaded.

```powershell
if (Get-Process CrimsonDesert -ErrorAction SilentlyContinue) {
  "Crimson Desert is running. Close it and run this step again."
} else {
  Copy-Item .\cdmp.asi   "$game\cdmp.asi"   -Force
  Copy-Item .\cdmp.ini   "$game\cdmp.ini"   -Force
  Copy-Item .\dinput8.dll "$game\winmm.dll" -Force    # the rename is the install
  "Installed."
}
```

The rename in the last line is **required**, not cosmetic. The game imports `WINMM.dll`
and does not import `DINPUT8.dll`, so a file named `dinput8.dll` would sit there and never
load. The loader forwards every sound function to the real Windows DLL, so audio is
unaffected.

Resulting state in `bin64`: `winmm.dll`, `cdmp.asi`, `cdmp.ini`, `CrimsonDesert.exe`.

---

## Step 4 — verify the install

```powershell
(Get-FileHash "$game\cdmp.asi" -Algorithm SHA256).Hash
```

Must equal:

```
{{ASI_SHA256}}
```

If it differs, the wrong ZIP was downloaded. A mismatch here is the single most confusing
failure this mod has: everything connects, the distance updates, and **no character ever
appears** — because both players must run the same build id. Re-download from the release
page rather than mixing files from two downloads.

Check the config is the guest profile:

```powershell
Get-Content "$game\cdmp.ini" -Encoding Unicode | Select-String '^\s*(role|peer_steamid|transport)\s*='
```

Expected: `transport=steam`, `role=guest`, `peer_steamid=76561199441047799` (the host's
SteamID64). This kit is already configured; nothing needs editing.

---

## Step 5 — confirm the mod loads

Start the game, load a save, then:

```powershell
Get-Content "$game\cdmp.log" -TotalCount 3
```

The first line must read:

```
=== Crimson Desert Multiplayer 0.2.0 (build {{BUILD_ID}}, protocol {{PROTOCOL}}) ===
```

If `cdmp.log` does not exist at all, the mod did not load. The usual causes, in order:

1. `dinput8.dll` was copied without being renamed to `winmm.dll`.
2. Another DLL already occupied `winmm.dll` (Step 2 should have caught this).
3. The game build is not 1.0.0.3460 — the mod logs the refusal.

The in-game overlay also proves it loaded: a panel in the top-left corner, toggled with
**F8**.

---

## Step 6 — connect

The **host** must already be in the world with the same build. The guest then connects
automatically through Steam; there is no code to type and nothing to choose in-game.

Expected panel lines, in order:

```
Network: connected to '...' (XX ms)
Other player: HP xxxx/xxxx   XX m away
```

`Other player: ... XX m away` tracking the host as he moves is the real success signal.
Two lines that look like errors and are **not**:

- `Room code: (no code: room: idle)` — normal on the guest. The host owns the room.
- `Camera: camera block sentinel mismatch` — a diagnostic the game patch moved. It costs
  only an on-screen name label.

Both players must be **Steam friends**, and both should run build `{{BUILD_ID}}`.

Be precise about what a mismatch does, because an earlier version of this document got it
wrong: `ClientSession::check_build` records a warning and the HUD displays it, and
**nothing blocks the session or the spawn**. It is a signal that the two sides are not in a
controlled configuration — not a switch that turns the mod off, and its absence does not
prove the build is the problem. Reading the code is what settled this; the message alone
does not.

---

## Rules to tell the user

- **Nobody saves while the other player is in their world.** This is the most likely way to
  damage a save; it is not hypothetical.
- **Do not delete `cdmp.log`.** It is the entire diagnostic record; it says which step
  failed.
- **Do not let the game update.** In Steam, right-click Crimson Desert > Properties >
  Updates > "Only update this game when I launch it". A game update changes every address
  and the mod turns itself off until it is re-ported.

---

## Uninstall

```powershell
Remove-Item "$game\winmm.dll", "$game\cdmp.asi", "$game\cdmp.ini" -Force
```

That is complete. The mod writes nothing else and does not modify game files.

---

## If it does not work

Send both `cdmp.log` files (host and guest) to whoever provided this kit. Each stage logs
its own line, so the log identifies the failing step directly. The two numbers to compare
first are the build ids on line 1 of each log — if they differ, that is the whole problem.

## What this build does not do

Joint bosses are half done: the guest sees the boss and damages it, and the host's quest
stays safe, but the guest's own quest does not advance and no loot drops for the guest. The
guest's world never contained that boss. This is stated in the README rather than left to
be discovered.
