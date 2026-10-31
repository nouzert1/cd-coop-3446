<#
.SYNOPSIS
  Builds the two kits for the ROLE-SWAP test: you as guest, the other player as host.

.DESCRIPTION
  Every test so far had the same host, and it is the host that dies. That could be the
  code, or it could be that machine. Swapping the roles separates the two: if the other
  player now dies as host, the fault travels with the role and is in the code; if the
  host survives on their machine and only yours dies as guest, it travels with the PC.

  The swapped kits differ only in cdmp.ini -- role, the peer SteamID, and the room code
  each side expects. This produces both from one build, plus a README for each side that
  says what to do and, more importantly, what to send back.

  Both kits carry the same cdmp.asi. Two players must run the same build id, and this
  script refuses to pack if the binary is stale against git HEAD.

.EXAMPLE
  .\pack-role-swap.ps1 -HostSteamId <STEAMID-ANFITRIAO> -GuestSteamId <STEAMID-CONVIDADO>
#>

[CmdletBinding()]
param(
    # The player who will HOST in the swapped test (the one who was the guest before).
    [Parameter(Mandatory)][string] $HostSteamId,
    # The player who will JOIN in the swapped test (the one who was the host before).
    [Parameter(Mandatory)][string] $GuestSteamId,
    # Steam display name of the new host, for the README. Optional.
    [string] $HostName = 'the host',
    # Steam display name of the new guest, for the README. Optional.
    [string] $GuestName = 'the guest'
)

$ErrorActionPreference = 'Stop'

$root   = Split-Path $PSScriptRoot -Parent
$bin    = Join-Path $root 'build\bin\RelWithDebInfo'
$asi    = Join-Path $bin 'cdmp.asi'
$loader = Join-Path $root 'third_party\ultimate-asi-loader\v9.7.4\dinput8.dll'
$outDir = Join-Path $root 'dist\role-swap'

if (-not (Test-Path $asi))    { throw "No $asi -- run scripts\build.ps1 first." }
if (-not (Test-Path $loader)) { throw "No $loader -- the ASI loader is missing from third_party." }

# Refuse to pack a binary that does not match the source, because two players comparing
# build ids is the only compatibility check the mod does.
$idHeader = Join-Path $root 'build\generated\build_id.h'
if (-not (Test-Path $idHeader)) { throw "No $idHeader -- run scripts\build.ps1 first." }
$m = Select-String -Path $idHeader -Pattern 'CDMP_BUILD_ID\s+0x([0-9a-fA-F]+)'
if (-not $m) { throw "Cannot read CDMP_BUILD_ID from $idHeader" }
$buildId = $m.Matches[0].Groups[1].Value.ToUpperInvariant()

Push-Location $root
try {
    $head = (git rev-parse --short=8 HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $head -and $buildId -ne $head.ToUpperInvariant()) {
        throw ("The built cdmp.asi carries build id 0x{0} but HEAD is {1}. Run scripts\build.ps1." -f
               $buildId, $head)
    }
} finally { Pop-Location }

$asiHash    = (Get-FileHash $asi -Algorithm SHA256).Hash
$loaderHash = (Get-FileHash $loader -Algorithm SHA256).Hash

if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# The INI is UTF-16 LE: the mod reads it that way, and writing it as UTF-8 produces a file
# the mod accepts but reads as empty, which looks like a config problem and is not one.
function Write-Kit {
    param([string] $Name, [string] $Role, [string] $Peer, [string] $Readme)

    $dir = Join-Path $outDir $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Copy-Item $asi    (Join-Path $dir 'cdmp.asi')    -Force
    Copy-Item $loader (Join-Path $dir 'dinput8.dll') -Force

    $roleNotes = if ($Role -eq 'host') {
        @'
; HOST: leave the code EMPTY. The mod creates the room and prints the code in
; cdmp.log and on the overlay. Send that code to the other player.
'@
    } else {
        @'
; GUEST: paste the host's 7-character code here once they send it, e.g. code=000Y4G6.
; The mod also falls back to [steam] peer_steamid, but the code is what works.
'@
    }

    $ini = @"
[general]
name=Player

[net]
enabled=1
transport=steam
; host = create the room and wait; guest = join the other player's room
role=$Role
send_rate_hz=20

[steam]
; Guest: the host's SteamID64. Empty falls back to "the only friend playing
; Crimson Desert", which has been wrong before when two friends play at once.
peer_steamid=$Peer

[room]
$roleNotes
code=

[overlay]
enabled=1
self_marker=1

[sniffer]
enabled=1
record=0

[coop]
enabled=1
delay_ms=300
offset_m=0
enemy_auto=1
guest_hits=1
boss_safe=1
guest_loot=1

[dev]
damage=0
"@
    [IO.File]::WriteAllText((Join-Path $dir 'cdmp.ini'), $ini, [Text.Encoding]::Unicode)
    $Readme | Set-Content (Join-Path $dir 'LEIA-PRIMEIRO.md') -Encoding UTF8
    # The step-by-step guide, kept separate from LEIA-PRIMEIRO (which explains the test).
    # This one exists because the player's assistant is asked to "install the host kit" and
    # needs an unambiguous procedure with the hashes to verify against.
    $guide = Join-Path $PSScriptRoot "..\kit\guia-$Name.md"
    if (Test-Path $guide) { Copy-Item $guide (Join-Path $dir 'COMO-INSTALAR.md') -Force }
    Add-Content (Join-Path $dir 'SHA256SUMS.txt') -Encoding UTF8 -Value @"
$asiHash  cdmp.asi
$loaderHash  dinput8.dll
"@
}

$common = @"
| | |
|---|---|
| Build id (**the two must match**) | ``$buildId`` |
| ``cdmp.asi`` SHA256 | ``$asiHash`` |
| Game version required | **1.0.0.3460** |

## Install (same for both players)

1. **Back up your save first.**
   `````powershell
   `$s = "`$env:LOCALAPPDATA\Pearl Abyss\CD\save"
   Copy-Item `$s "`$env:USERPROFILE\Desktop\CD-save-backup-`$(Get-Date -Format 'yyyyMMdd-HHmm')" -Recurse -Force
   `````
2. Close the game.
3. Copy ``cdmp.asi``, ``cdmp.ini`` and ``dinput8.dll`` into:
   `````
   C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64
   `````
4. **RENAME ``dinput8.dll`` to ``winmm.dll``.** This is not optional. The game imports
   ``WINMM.dll`` and does not import ``DINPUT8.dll``, so with the original name the file
   sits there and is never loaded -- no panel, no ``cdmp.log``, no error either.

## What is new in this build

``Exit watch`` is installed at startup. The two crashes today left **no** Windows crash
report, **no** dump and **no** exception caught by the mod. That means the process left
through ``TerminateProcess``/``ExitProcess`` rather than by faulting, and nothing records
that. The mod now does, writing the exit code, the calling module and a stack into
``cdmp.log``.

**Confirm it is on** -- this line must appear once, early in the log:

``````
Exit watch: TerminateProcess hooked | ExitProcess hooked | ...
``````

If it says ``FAILED``, stop and report it: that line is the whole experiment.
"@

Write-Kit -Name 'host' -Role 'host' -Peer '' -Readme @"
# You are the HOST in this test

$common

**You were the guest in the tests so far. This time you host.**

Your ``cdmp.ini`` already says ``role=host`` with an empty peer and an empty code. Do not
edit it.

## Order (this matters)

1. You open the game and load your save. **Enter the world.**
2. **Wait for the world to finish loading** -- walk a few steps, look around, then stand
   still for 30 seconds. Impatience here caused a false diagnosis earlier today: a
   position read before the world loaded came back as ``(0,0,0)`` and sent the
   investigation the wrong way for hours.
3. Read your **room code**:
   `````powershell
   Select-String -Path "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64\cdmp.log" -Pattern 'your code is' | Select-Object -Last 1 | ForEach-Object { `$_.Line }
   `````
4. **Send that code to $GuestName.**
5. Wait. They join. **You do not need to do anything else.**

## What we are testing

Today the host died ~1 second after the guest's character was injected, twice. We do not
know whether that is the code or your machine. **You hosting is the experiment:** if you
now die the same way, it is the code and your machine is fine.

**Do not go looking for the crash. Just play normally near each other.**

## When it ends -- and it may end suddenly

If the game closes by itself, capture the log **immediately**:

``````powershell
`$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Copy-Item "`$g\cdmp.log" "`$env:USERPROFILE\Desktop\cdmp-HOST-`$(Get-Date -Format 'HHmm').log" -Force
``````

**The last lines before it died are the entire point of this test.** Send that file.

Then send this, with the game closed:

``````powershell
`$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Write-Host "--- build ---" -ForegroundColor Cyan
Select-String -Path "`$g\cdmp.log" -Pattern 'Crimson Desert Multiplayer|Game reader' | Select-Object -First 2 | ForEach-Object { `$_.Line }
Write-Host "--- exit watch installed? ---" -ForegroundColor Cyan
Select-String -Path "`$g\cdmp.log" -Pattern 'Exit watch' | ForEach-Object { `$_.Line }
Write-Host "--- did it record an exit? ---" -ForegroundColor Cyan
Select-String -Path "`$g\cdmp.log" -Pattern 'Exit:' | ForEach-Object { `$_.Line }
Write-Host "--- room and connection ---" -ForegroundColor Cyan
Select-String -Path "`$g\cdmp.log" -Pattern 'your code is|Net: connected|peer timed out' | Select-Object -Last 4 | ForEach-Object { `$_.Line }
Write-Host "--- last 20 lines ---" -ForegroundColor Cyan
Get-Content "`$g\cdmp.log" | Select-Object -Last 20
``````

The ``--- did it record an exit? ---`` block is the one that answers the question. If it
has ``Exit:`` lines, we finally know what killed it. If it is empty, the death is even
quieter than we thought, and that is also a real answer.

## If nothing crashes

Then **that is the finding**. Say so plainly and say how long you played. It means the
fault travels with the machine and not with the role, which changes what we look at next.
"@

Write-Kit -Name 'guest' -Role 'guest' -Peer $HostSteamId -Readme @"
# You are the GUEST in this test

$common

**You were the host in the tests so far. This time $HostName hosts and you join.**

Your ``cdmp.ini`` already has ``role=guest`` and ``peer_steamid=$HostSteamId``. The only
thing you must do is **paste the room code** once $HostName sends it.

## Order

1. **Wait for $HostName to open the game and enter the world first.** Do not open yours yet.
2. They send you a **7-character code** (like ``1YZDAWX``).
3. Open your game and load your save entry.
4. **Let the world finish loading** -- walk a few steps, look around, stand still 30 seconds.
5. Paste the code into your ``cdmp.ini``:
   `````powershell
   `$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
   `$c = Read-Host "Paste the 7-character code"
   `$t = [IO.File]::ReadAllText("`$g\cdmp.ini", [Text.Encoding]::Unicode)
   `$t = [regex]::Replace(`$t, '(?m)^code=.*`$', "code=`$c")
   [IO.File]::WriteAllText("`$g\cdmp.ini", `$t, [Text.Encoding]::Unicode)
   Write-Host "code set to `$c -- restart the game if it was already open" -ForegroundColor Green
   `````
   Type the code in the panel field instead if you prefer; both work.
6. Enter the world and go to where $HostName is.

## What we are testing

**Today the host died when the guest's character appeared.** You were the guest, so you
survived both times and your logs were clean. This time you are the guest again, and the
question is whether $HostName now dies the same way.

## What to send

Afterwards, with the game closed:

``````powershell
`$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Write-Host "--- your position (should CHANGE when you walk) ---" -ForegroundColor Cyan
Select-String -Path "`$g\cdmp.log" -Pattern 'Local: pos' | Select-Object -Last 3 | ForEach-Object { `$_.Line }
Write-Host "--- did you see their character? ---" -ForegroundColor Cyan
Select-String -Path "`$g\cdmp.log" -Pattern 'other player loaded|spawn queued|spawn refused' | Select-Object -Last 4 | ForEach-Object { `$_.Line }
Write-Host "--- connection ---" -ForegroundColor Cyan
Select-String -Path "`$g\cdmp.log" -Pattern 'Net: connected|peer timed out' | Select-Object -Last 3 | ForEach-Object { `$_.Line }
``````

**Also answer in one line each:**

1. Did you see their character? Walking, or standing still?
2. Did your game survive the whole test?
3. Did theirs close at any point?
"@

Write-Host ''
Write-Host "Kits written to $outDir" -ForegroundColor Green
Write-Host "  host  -> $HostSteamId ($HostName)  role=host"
Write-Host "  guest -> $GuestSteamId ($GuestName) role=guest peer=$HostSteamId"
Write-Host ''
Write-Host "cdmp.asi SHA256: $asiHash"
Write-Host "build id:        $buildId"
Write-Host ''
Write-Host "Zip them and send the 'host' one to $HostName and the 'guest' one to $GuestName."
Write-Host "They are NOT interchangeable: the cdmp.ini differs."
