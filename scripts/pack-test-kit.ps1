# Builds the ZIP for the two-PC test and writes the folder the friend needs.
#
#   .\scripts\pack-test-kit.ps1
#
# Output: dist\cdmp-3446-test-kit\  and  dist\cdmp-3446-test-kit.zip
#
# The ZIP is identical for both players, which matters: the mod compares a build
# id on connect and shows "Different mod versions" if they do not match, so both
# sides MUST come from the same ZIP.

param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo')]
    [string]$Config = 'RelWithDebInfo',

    # The HOST's SteamID64, written into the guest's [steam] peer_steamid.
    #
    # Optional, and deliberately not defaulted: it identifies a real Steam account,
    # so shipping one in the repository would be nobody's business but its owner's.
    # Omitted, the guest falls back to connecting to the only friend playing
    # Crimson Desert -- which is how the first working test connected anyway.
    [string]$HostSteamId = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bin = Join-Path $root "build\bin\$Config"
$dist = Join-Path $root 'dist'
$kit = Join-Path $dist 'cdmp-3446-test-kit'

if (-not (Test-Path "$bin\cdmp.asi")) { throw "Build first: $bin\cdmp.asi not found" }
if (Get-Process CrimsonDesert -ErrorAction SilentlyContinue) {
    Write-Warning 'The game is running; the build id is read from source so this is fine, but close it before deploying.'
}

# The binary must have been built from the commit that is checked out now.
#
# The build id is baked in at CMake configure time (CMakeLists.txt runs git
# rev-parse through execute_process), so a .asi built before a later commit keeps
# the OLDER id. The mod exchanges this id on connect and the HUD warns when the two
# sides differ, so shipping a stale binary means both players see "Different mod
# versions" while holding what looks like the same ZIP -- with nothing pointing at
# the real cause.
#
# (This comment used to say the mod "refuses to pair" on a mismatch. It does not:
# check_build() in client_session.cpp records a warning and returns, and nothing on the
# spawn path reads it. The stale-build check below is still worth having, because two
# sides on different builds is an uncontrolled test, but overstating what the mismatch
# does sends the next person looking in the wrong place.)
$idHeader = Join-Path $root 'build\generated\build_id.h'
$head = (& git -C $root rev-parse --short=8 HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $head) {
    Write-Warning 'Not a git repository: cannot check the build id against a commit.'
} elseif (-not (Test-Path $idHeader)) {
    Write-Warning "No $idHeader; cannot check the build id. Run scripts\build.ps1."
} else {
    $head = $head.Trim()
    $m = Select-String -Path $idHeader -Pattern 'CDMP_BUILD_ID\s+0x([0-9a-fA-F]+)'
    if (-not $m) { throw "Cannot read CDMP_BUILD_ID from $idHeader" }
    $built = $m.Matches[0].Groups[1].Value.ToLower()
    if ($built -ne $head) {
        throw ("The built cdmp.asi is STALE: it carries build id 0x{0} but HEAD is {1}. " +
               "Rebuild with scripts\build.ps1 before packing, or both players will see " +
               "'Different mod versions' from the same ZIP.") -f $built, $head
    }
    Write-Host "Build id matches HEAD ($head)."
}

# Start clean so a stale file can never end up in the ZIP.
if (Test-Path $kit) { Remove-Item $kit -Recurse -Force }
New-Item -ItemType Directory -Path $kit -Force | Out-Null

# --- what the friend needs, and nothing else ------------------------------
Copy-Item "$bin\cdmp.asi" $kit

$loader = Join-Path $root 'third_party\ultimate-asi-loader\v9.7.4\dinput8.dll'
if (-not (Test-Path $loader)) { throw "ASI loader not found: $loader" }
Copy-Item $loader (Join-Path $kit 'dinput8.dll')

# The INI the guest edits: take the default one the build writes, so the keys
# always match this build.
$iniSrc = Join-Path $bin 'cdmp.ini'
if (-not (Test-Path $iniSrc)) {
    # No INI yet (the mod writes one on first game run). The fallback below has
    # to carry EVERY key the test depends on, because a key that is absent is
    # invisible: the player gets the default without knowing the choice existed.
    Write-Host 'No cdmp.ini in the build output; it is written on first game run.'
    Write-Host 'Creating the test INI, with every key this test uses.'
    @'
[general]
player_name=Player

[net]
; Both players: transport=steam (the only transport that works between PCs).
transport=steam
; HOST: set role=host and leave [room] code EMPTY.
; GUEST: leave role=guest and paste the host's code below.
role=guest

[room]
; GUEST: paste the host's 7-character code here, e.g. code=000Y4G6
; HOST: leave EMPTY -- the mod makes the room and shows the code.
code=

[overlay]
enabled=1
; The panel speaks English or Spanish only ("en" | "es"); anything else = en.
language=en

[coop]
; The main switch. 1 turns co-op on (the other player appears in your world).
enabled=1
; Playout delay in ms: how far behind you see the other player. Longer is
; smoother but laggier. 300 is a sane starting point.
delay_ms=300

; ENEMY RELAY -- leave at 1, shared loot depends on it.
; This is what makes the host's enemies appear as copies in your world. It is
; also the only thing that tells the mod WHICH creature a copy is, and shared
; loot needs that to know what to put in your world. With this at 0, shared loot
; silently never fires.
enemy_auto=1

; YOUR BLOWS ON THE HOST'S ENEMIES -- leave at 1, shared loot depends on it too.
; With this on, when you hit a copy of one of the host's enemies, the blow is
; applied to the real enemy in the host's world. It is also what tells the mod
; that YOU took part in the kill, which is the condition shared loot fires on:
; a creature you never touched gives you nothing, by design.
; (This replaces the older "damage" mirroring below; if both are set, this one
; wins and the mod says so in the log.)
guest_hits=1
; The stagger reaction on those blows. Leave at 0 for the first test: it injects
; a hit reaction into the other player's enemy, which is the riskiest part.
guest_hit_stagger=0

; MIRRORED DAMAGE -- leave at 0 when guest_hits is 1.
; An older, blunter way to hurt the host's enemies (send the damage number).
; It and guest_hits would both hurt the same enemy, so guest_hits wins.
damage=0

; BOSS SAFETY -- leave this at 1.
; A boss fight here is a scripted scene that the HOST's game runs: it owns the
; boss's phases, the cutscenes and the end of the fight. The boss only really
; exists in the host's world, so if the GUEST lands the killing blow the boss
; dies outside that script, the end-of-fight never fires, and the HOST'S QUEST
; GETS STUCK behind the arena barrier.
; 1 (default): you still do damage and still help, but the host lands the
;              killing blow, bosses are not staggered, and nothing lands while
;              the host is in a cutscene.
; 0: old behaviour. Only with a save backup, and expect stuck quests.
boss_safe=1

; SHARED LOOT -- GUEST only, leave at 1 to test it.
; When you help kill one of the host's enemies, your own world would normally
; give you nothing, because that creature only exists in the host's world.
; With this on, your server makes its own copy of that creature after the one
; you helped kill goes down, kills it here, and lets you loot it normally -- so
; each of you takes your own drop from the same kill, and your own quests and
; XP are not affected.
; It only fires for an enemy you actually helped kill, within 30 m of you.
; Hosts can leave it at 0: the enemies are already theirs.
guest_loot=1
'@ | Set-Content -Path (Join-Path $kit 'cdmp.ini') -Encoding Unicode
} else {
    Copy-Item $iniSrc (Join-Path $kit 'cdmp.ini')
}

# --- force the keys this test depends on, whichever INI was used -----------
# Copying the build's own INI is not enough, because it is the mod's DEFAULT file:
# on this build it says transport=udp, which is the loopback transport used for
# local testing and cannot reach another PC at all. A kit shipped with it would
# look correct, install cleanly, and fail to connect with nothing in the README to
# explain why. The guard below already refused to pack that file; this makes the
# chosen values authoritative instead of depending on what happened to be in the
# source, so the kit is correct whether or not a build-output INI exists.
$kitIni = Join-Path $kit 'cdmp.ini'
$iniLines = Get-Content $kitIni -Encoding Unicode
function Set-IniKey([string[]]$lines, [string]$section, [string]$key, [string]$value) {
    $out = New-Object System.Collections.Generic.List[string]
    $cur = ''
    $done = $false
    foreach ($l in $lines) {
        $m = [regex]::Match($l, '^\s*\[([^\]]+)\]')
        if ($m.Success) {
            # Leaving the section without having seen the key: insert it there.
            if ($cur -eq $section -and -not $done) { $out.Add("$key=$value"); $done = $true }
            $cur = $m.Groups[1].Value
        } elseif ($cur -eq $section -and -not $done) {
            $k = [regex]::Match($l, '^\s*([^;=\s]+)\s*=')
            if ($k.Success -and $k.Groups[1].Value -eq $key) {
                $out.Add("$key=$value")
                $done = $true
                continue
            }
        }
        $out.Add($l)
    }
    if ($cur -eq $section -and -not $done) { $out.Add("$key=$value"); $done = $true }
    if (-not $done) { $out.Add("[$section]"); $out.Add("$key=$value") }
    return $out.ToArray()
}

# The two-PC test is over Steam. Anything else cannot leave this machine.
$iniLines = Set-IniKey $iniLines 'net' 'transport' 'steam'

# --- the host's SteamID, so the guest needs no room code -------------------
#
# The room code changes every time the host restarts the game (the lobby id
# increments: 109775242893225821, ...94486749, ...95229575 across three launches),
# so a kit that ships a code is stale the moment the host reopens the game, and
# the friend has to edit the INI each time.
#
# [steam] peer_steamid does not change. The guest connects straight to that
# account, and mod.cpp:265 uses it before the code path, so an empty [room] code
# is correct. The "only friend playing" scan stays as the fallback.
#
# Both sides do NOT set this: on the host an empty value means "accept any friend
# playing", which is what we want, so only the guest's INI carries it.
#
# The value is a PARAMETER, not a constant: it is a real person's SteamID, and a
# hardcoded one in a public repository is somebody's account identifier sitting in
# the source for no reason. Pass it when building your own kit:
#
#   .\scripts\pack-test-kit.ps1 -HostSteamId 7656119XXXXXXXXXX
#
# Left empty, the kit still works: [room] code= stays empty too, and the mod falls
# back to the "only friend playing Crimson Desert" scan described in the README.
$iniLines = Set-IniKey $iniLines 'steam' 'peer_steamid' $HostSteamId
if (-not $HostSteamId) {
    Write-Host 'No -HostSteamId given: the guest will connect via the "only friend playing" scan.'
    Write-Host 'Pass -HostSteamId <SteamID64> to pin it to one account instead.'
}

# The master switch, and it MUST be listed first of the coop keys.
#
# [coop] enabled is the one key that decides whether the other player appears at
# all: config.cpp reads it with a DEFAULT OF 0, and the mod's own template INI
# ships enabled=0, so a kit that does not force it produces a guest whose log says
# "co-op off" while the connection itself works perfectly. That is exactly what
# happened in the first real two-PC test: the session connected (rtt 44 ms, 71
# remote states received, the host's position arriving every tick) and the guest
# reported "other player: HP 1650/1650 4154 m away" -- the distance was right and
# the character was never drawn, because nothing was spawning it.
#
# Every other coop flag below only tunes behaviour inside that switch, so leaving
# it at 0 made all of them silently irrelevant.
$iniLines = Set-IniKey $iniLines 'coop' 'enabled' '1'
# Not asserted by the guard below, but the coop flags are what the test exercises.
foreach ($kv in @(@('coop', 'enemy_auto', '1'), @('coop', 'guest_hits', '1'),
                  @('coop', 'boss_safe', '1'), @('coop', 'guest_loot', '1'))) {
    $iniLines = Set-IniKey $iniLines $kv[0] $kv[1] $kv[2]
}
Set-Content -Path $kitIni -Value $iniLines -Encoding Unicode

# --- the read-me the friend actually follows ------------------------------
@'
==========================================================
 Crimson Desert Co-op - test kit (build 1.0.0.3446)
==========================================================

READ THIS FIRST - the important part
------------------------------------
This is an EXPERIMENTAL mod. It has NEVER been tested by two real
people. Back up your save before you play:

  1. Press Win+R, paste this and press Enter:
       %LOCALAPPDATA%\Pearl Abyss\CD
  2. Copy the "save" folder somewhere safe (Desktop is fine).

If anything goes wrong you restore that folder and you are back
where you started.

Also: in Steam, right-click Crimson Desert > Properties > Updates
and set it to "Only update this game when I launch it". A game
update would change the game's build and this mod would stop
loading (it refuses to run on a build it does not know, on
purpose, so it can never corrupt your save).

This is not hypothetical: the game updated by itself from 1.0.0.3424
to 1.0.0.3446 in the middle of building this mod. The mod went inert
exactly as described - it did not crash and did not touch the save -
and every address had to be measured again on the new build.

If your game is newer than 1.0.0.3446, tell me - the mod will not
work and I need to re-port it. To check: right-click
CrimsonDesert.exe > Properties > Details > File version.


HOW TO INSTALL
--------------
1. Find your game folder. In Steam: right-click Crimson Desert >
   Manage > Browse local files. You land in the game root; open
   the "bin64" folder inside it.

2. Copy these files INTO bin64:
       cdmp.asi
       cdmp.ini
       dinput8.dll   ->  RENAME it to:  winmm.dll

   (The file is called dinput8.dll in this ZIP only because that
   is the name it ships with. It MUST be renamed to winmm.dll, or
   nothing will load.)

   bin64 should then contain:  winmm.dll, cdmp.asi, cdmp.ini
                               CrimsonDesert.exe

   An audio note, because it looks alarming: the game loads its
   sound through winmm.dll, and we are replacing that file. The
   loader we ship forwards every sound function on to the real
   Windows one, so audio is unaffected. This is the normal way ASI
   mods work.

   BUT: if bin64 already has a winmm.dll, STOP and tell me -
   that means another mod is using it and one of us would win and
   the other would silently not load.

3. Start the game.
   You should see a red title and a panel in the top-left corner.
   Press F8 to toggle it.
   If you see nothing, check that a file called cdmp.log appeared
   in bin64 and send it to me.

   DO THIS FIRST, BEFORE ANYTHING ELSE - 30 seconds:
   A file called cdmp.log must appear in bin64 as soon as the game
   starts, and the panel must be there.
     - Both there? Good, the mod loaded. Carry on.
     - Not there? Stop and tell me. Do not spend time on the
       connection steps, because the mod is not loading at all.
       The usual cause is that dinput8.dll was not renamed to
       winmm.dll, or bin64 already had a winmm.dll from another
       mod. (The rename is required because the game imports
       WINMM.dll and does NOT import DINPUT8.dll - a file named
       dinput8.dll would just sit there and never load.)
   This tells us "it does not load" and "it loads but will not
   connect" apart, which are completely different problems.


HOW TO PLAY TOGETHER
--------------------
The HOST (the one whose world you play in):
  1. Open cdmp.ini and set, under [net]:
         role=host
     and leave [room] code= EMPTY.
  2. Start the game and load your save.
  3. The panel shows a line like:  Room code: 000Y4G6
  4. Read that code to your friend.

The GUEST (the one visiting):
  1. Close the game.
  2. Open cdmp.ini. Under [net] leave role=guest, and under
     [room] set:
         code=000Y4G6
     (the code your friend read out; lower case and dashes are fine)
  3. Save, start the game, load your save.
  4. The panel should say it is joining. Give it up to a minute.

If it does not connect, send me cdmp.log from bin64 - it says
exactly which step failed.


WHAT IS ALREADY TURNED ON
-------------------------
You do not need to edit anything else. The kit arrives with
these on, and the panel (F8) and cdmp.log will tell you if any
of them is not:

  * Shared loot (GUEST). Help the host kill one of their
    creatures and you get YOUR OWN drop from it, in your own
    world, without touching your quests or XP. You have to
    actually hit the creature - one you never touched gives you
    nothing, on purpose. It works within 30 m of you.
    What to look for: kill something together, then loot the
    corpse that appears on your side.

  * Boss safety (BOTH). Bosses here are scripted fights that the
    HOST's game runs. If you (guest) land the killing blow, the
    fight ends outside that script and the HOST'S QUEST GETS
    STUCK. So with this on you still do damage and still help,
    but the host lands the killing blow, and nothing lands while
    the host is in a cutscene. If the panel says the host is in
    a cutscene, just wait.
    What to look for: fight a world boss together and check that
    the host's quest completes normally afterwards.

  * A boss health bar in your panel, because the guest's game has
    no boss bar of its own (that belongs to the host's script).

WHAT IS NOT READY YET
---------------------
Joint bosses are only half there, and I would rather say so than
let you find out the confusing way:

  * You SEE the boss and you HURT it, and the host's quest is
    safe.
  * But YOUR OWN quest is NOT advanced by the kill, and the boss
    does not drop loot for you. Your world never had that boss in
    it. Making both worlds run their own copy of the fight is a
    much bigger job and it is not done. This is the same
    limitation Genshin-style co-op has, for the same reason.

So: huge help in the fight, no credit for it yet. Please do test
it and tell me what the panel and the log say - that is exactly
the information I need.


RULES WHILE TESTING (please follow these)
-----------------------------------------
- Nobody saves while the other player is in their world.
  That is the most likely way to damage a save.
- Press Ctrl+F12 at the same moment ("3, 2, 1, NOW") when I ask.
  It writes a numbered mark in cdmp.log so we can line up the two
  logs afterwards.
- Keep cdmp.log. Do not delete it. It is the whole point of the
  test.
- To uninstall: delete winmm.dll, cdmp.asi and cdmp.ini from
  bin64. That is all.
'@ | Set-Content -Path (Join-Path $kit 'LEIA-ME.txt') -Encoding UTF8

@'
==========================================================
 Crimson Desert Co-op - test kit (build 1.0.0.3446)
==========================================================

BACK UP YOUR SAVE FIRST
-----------------------
Win+R ->  %LOCALAPPDATA%\Pearl Abyss\CD
Copy the "save" folder somewhere safe.

This mod has never been tested by two real people. It is
experimental.

In Steam: Crimson Desert > Properties > Updates > set
"Only update this game when I launch it". A game update breaks
the mod (it refuses to load on an unknown build, on purpose).


INSTALL
-------
1. Steam > right-click Crimson Desert > Manage > Browse local
   files. Open the "bin64" folder.

2. Copy INTO bin64:
       cdmp.asi
       cdmp.ini
       dinput8.dll    ->  RENAME it to:  winmm.dll

   The rename is required. bin64 should then have:
       winmm.dll, cdmp.asi, cdmp.ini, CrimsonDesert.exe

   The game plays sound through winmm.dll and we replace that
   file; the loader forwards every sound function to the real
   Windows one, so audio is fine. This is how ASI mods normally
   work.

   If bin64 ALREADY has a winmm.dll, STOP and tell me: another
   mod is using it and only one of us would load.

3. Start the game. A panel appears top-left; F8 toggles it.
   No panel? Send me cdmp.log from bin64.

   FIRST, BEFORE ANYTHING ELSE (30 seconds): cdmp.log must appear
   in bin64 and the panel must be there.
     - Both there? The mod loaded. Carry on.
     - Not there? Stop and tell me - the mod is not loading at
       all, and the connection steps cannot help. Usually it means
       dinput8.dll was not renamed to winmm.dll, or bin64 already
       had a winmm.dll. (The rename is required: the game imports
       WINMM.dll and does NOT import DINPUT8.dll, so a file called
       dinput8.dll would never be loaded.)
   This separates "does not load" from "loads but will not
   connect", which are very different problems.


PLAY
----
HOST (the world you play in):
  In cdmp.ini, under [net], set:  role=host
  and leave [room] code= EMPTY.
  Start the game, load your save. The panel shows:
      Room code: 000Y4G6
  Read it to your friend.

GUEST (visiting):
  Close the game. In cdmp.ini leave role=guest and set,
  under [room]:
      code=000Y4G6
  Save, start the game, load your save. Wait up to a minute.

Not connecting? Send me cdmp.log - it names the failing step.


ALREADY TURNED ON (no editing needed)
-------------------------------------
  * Shared loot (GUEST): help kill one of the host's creatures
    and you get your own drop from it, in your own world, without
    touching your quests or XP. You must actually hit it - a
    creature you never touched gives nothing, on purpose.
  * Boss safety (BOTH): bosses here are scripted fights the HOST
    runs. If the guest lands the killing blow, the fight ends
    outside that script and the HOST'S QUEST STICKS. You still do
    damage and still help, but the host kills it, and nothing
    lands during the host's cutscenes.
  * A boss health bar in the panel: the guest's game has none.

NOT READY YET
-------------
Joint bosses are half there: you see the boss and you hurt it,
and the host's quest is safe - but YOUR quest is not advanced and
the boss drops nothing for you, because your world never had that
boss. Making both worlds run their own copy of the fight is a much
bigger job and is not done.


RULES
-----
- Nobody saves while the other player is in their world.
- Ctrl+F12 at the same moment when asked (numbered mark in the
  log, so we can line up both logs).
- Keep cdmp.log.
- Uninstall: delete winmm.dll, cdmp.asi, cdmp.ini from bin64.
'@ | Set-Content -Path (Join-Path $kit 'README.txt') -Encoding UTF8

# --- checksums, so both sides can prove they have the same files ----------
# The mod reads cdmp.ini with GetPrivateProfileStringW / GetPrivateProfileIntW,
# which want UTF-16. An ASCII or UTF-8 INI does not fail loudly: the keys in it
# are simply not found and every setting silently reverts to its default. That
# would make a whole test session worthless, so check it before packing.
$iniPath = Join-Path $kit 'cdmp.ini'
$head = [System.IO.File]::ReadAllBytes($iniPath)
if ($head.Length -lt 2 -or $head[0] -ne 0xFF -or $head[1] -ne 0xFE) {
    throw ("cdmp.ini is not UTF-16 LE (first bytes: {0}). The mod reads it with the wide " +
           "INI API, so every key would be silently ignored.") -f (($head[0..1]) -join ',')
}
# A setting the test depends on must actually be in the file we ship. The loot
# keys are listed together because shared loot needs ALL of them: without
# enemy_auto the relay tracks no copies, and without guest_hits the guest never
# counts as having helped the kill -- either one missing and the feature silently
# does nothing while still reading as "on".
#
# 'enabled=1' is FIRST because it is the one that was missing and it is the master
# switch for the whole feature: config.cpp defaults it to 0 and the mod's template
# INI ships 0, so the first real two-PC kit went out with co-op off. The guest
# connected perfectly and never saw the host, and this list -- which was supposed
# to catch exactly this class of mistake -- did not look at it.
$iniText = Get-Content $iniPath -Encoding Unicode -Raw
foreach ($key in 'enabled=1', 'transport=steam', 'enemy_auto=1', 'guest_hits=1',
                 'boss_safe=1', 'guest_loot=1', "peer_steamid=$host_steam_id") {
    if ($iniText -notmatch [regex]::Escape($key)) { throw "cdmp.ini is missing '$key'" }
}

# The guide is generated below, so it can only be missing if that block was
# removed -- but it is the first thing the friend opens, so assert it is there.
if (-not (Test-Path (Join-Path $kit 'LEIA-ME.txt'))) { throw 'LEIA-ME.txt is missing' }

# What the guest checks to know he installed THIS kit and not an older one.
#
# Printing both the build id (what the panel shows) and the file hash (what Windows shows)
# turns "which ZIP do I have" into a two-second check, in the guide and in INSTALL.md.
#
# Be accurate about what a mismatch MEANS, because this comment used to overstate it: it
# claimed the mod refuses to spawn when the build ids differ. It does not. check_build()
# in client_session.cpp records a warning that the HUD displays, and nothing in the spawn
# path consults it. Keeping both sides on one build is still what makes a test controlled,
# and the number is worth printing for that reason -- but a mismatch is not a switch, and
# saying it was would send the next person looking in the wrong place.
#
# Defined here, before both documents, because each of them interpolates these values.
$build_id_upper = if ($built) { $built.ToUpper() } else { '(unknown)' }
$asi_hash = (Get-FileHash (Join-Path $kit 'cdmp.asi') -Algorithm SHA256).Hash
$steam_line = if ($HostSteamId) { $HostSteamId } else { '(vazio: conecta no unico amigo jogando)' }

# The agent-facing install document.
#
# The guest is having an AI coding agent do the install, and the other texts in this
# kit are written for a person: they say "copy these files into bin64" without a path
# to copy from, and describe the rename in prose. INSTALL.md is the mechanical
# version -- exact PowerShell, the build-version check that has to happen BEFORE
# installing, the winmm.dll conflict check, and the SHA256 to verify afterwards.
#
# It lives in kit/coop/ and is copied here rather than generated, because it is
# mostly prose and belongs in a file that can be reviewed and diffed on its own.
# It is stamped with this kit's build id and hash at pack time so the numbers in it
# can never drift from the binary being shipped.
$install_src = Join-Path $root 'kit\coop\INSTALL.md'
if (-not (Test-Path $install_src)) { throw "Missing $install_src" }
$install_text = Get-Content $install_src -Raw -Encoding UTF8
$install_text = $install_text.Replace('{{BUILD_ID}}', $build_id_upper).Replace('{{ASI_SHA256}}', $asi_hash)
if ($install_text -match '\{\{') { throw 'INSTALL.md still has an unstamped placeholder' }
# A stamp that silently expanded to nothing would produce a document telling the agent
# to verify against an empty string, which passes any check. Assert it landed.
if ($install_text -notmatch [regex]::Escape($asi_hash)) { throw 'INSTALL.md did not get the hash' }
$install_text | Set-Content -Path (Join-Path $kit 'INSTALL.md') -Encoding UTF8

# The research task for the guest's agent.
#
# The host crashes 0.4 s after the other player's character is injected, and the fix is a
# reverse-engineering job on the guest's copy of the game -- which is the one machine we
# cannot measure from here. INVESTIGATION.md carries the exact crash transcript, the lead
# (crash containment failed to install on 3446), four candidate causes with the cheapest
# experiment first, the tool invocation for each, and the three traps that cost real time
# in this port. Copied, not generated: it is mostly prose and its job is to be read and
# argued with, so it belongs in a file that diffs cleanly.
$investigation_src = Join-Path $root 'kit\coop\INVESTIGATION.md'
if (-not (Test-Path $investigation_src)) { throw "Missing $investigation_src" }
$investigation_text = Get-Content $investigation_src -Raw -Encoding UTF8
$investigation_text = $investigation_text.Replace('{{BUILD_ID}}', $build_id_upper).Replace('{{ASI_SHA256}}', $asi_hash)
if ($investigation_text -match '\{\{') { throw 'INVESTIGATION.md still has an unstamped placeholder' }
$investigation_text | Set-Content -Path (Join-Path $kit 'INVESTIGATION.md') -Encoding UTF8

# The hang-diagnosis scripts go in the kits too, because the next real test is the one
# that has to produce evidence, and the host is the one who has to run them.
#
# They matter more than they look. The host's game does not crash, it HANGS - four
# AppHangTransient events and no APPCRASH, so there is no crash dump and never was. A
# hang leaves the process alive and stalled, which is a capture window a crash does not
# offer, and capture-hang.ps1 -Watch uses it: it keeps a complete dump on disk WHILE the
# game runs so that when the hang comes the evidence is already written.
#
# dump-threads.ps1 reads the result. There is no cdb, no windbg and no procdump on this
# machine, so it walks the MINIDUMP structures directly.
$diag = Join-Path $kit 'diagnostico'
New-Item -ItemType Directory -Force -Path $diag | Out-Null
foreach ($s in 'capture-hang.ps1', 'dump-threads.ps1') {
    $src = Join-Path $root "scripts\$s"
    if (-not (Test-Path $src)) { throw "Missing $src" }
    Copy-Item $src $diag -Force
}
if (-not (Test-Path (Join-Path $diag 'capture-hang.ps1'))) { throw 'diagnostico/capture-hang.ps1 is missing' }
if (-not (Test-Path (Join-Path $diag 'dump-threads.ps1'))) { throw 'diagnostico/dump-threads.ps1 is missing' }

$lines = foreach ($f in 'cdmp.asi', 'dinput8.dll', 'cdmp.ini') {
    $h = (Get-FileHash (Join-Path $kit $f) -Algorithm SHA256).Hash
    '{0}  {1}' -f $h, $f
}
$lines | Set-Content -Path (Join-Path $kit 'SHA256SUMS.txt') -Encoding ASCII

# --- the Portuguese quick-start -------------------------------------------
#
# The friend is Brazilian and the English LEIA-ME is not what he will read. This
# is written here, by the packer, so a repack cannot lose it: an earlier kit was
# rebuilt and the guide simply vanished, because it had been added to the output
# folder by hand and this script wipes that folder on every run.
@"
==========================================================
  MOD CO-OP CRIMSON DESERT - GUIA RAPIDO (PORTUGUES)
==========================================================

VOCE E O CONVIDADO (QUEM VAI VISITAR O MUNDO DO AMIGO).

----------------------------------------------------------
PASSO 1 - BACKUP DO SEU SAVE (1 MINUTO, FACA ISSO)
----------------------------------------------------------

  1. Aperte Win+R, cole isto e aperte Enter:
        %LOCALAPPDATA%\Pearl Abyss\CD
  2. Copie a pasta "save" para a Area de Trabalho.

Se algo der errado, voce restaura essa pasta e volta ao normal.

----------------------------------------------------------
PASSO 2 - INSTALAR (3 arquivos)
----------------------------------------------------------

  1. No Steam: botao direito em Crimson Desert > Gerenciar >
     Procurar arquivos locais. Abra a pasta "bin64".

  2. Copie estes 3 arquivos PARA DENTRO de bin64:

        cdmp.asi
        cdmp.ini
        dinput8.dll   ->  RENOMEIE para:  winmm.dll

     O terceiro PRECISA ser renomeado para winmm.dll. Se ficar
     "dinput8.dll" ele nao carrega e nada funciona.

     Se a pasta bin64 JA TIVER um winmm.dll, PARE e me avise.

----------------------------------------------------------
PASSO 3 - NAO PRECISA EDITAR NADA
----------------------------------------------------------

  O cdmp.ini ja vem pronto. Confira so que tem:

        [net]    role=guest
        [steam]  peer_steamid=$steam_line
        [coop]   enabled=1
        [room]   code=            <- VAZIO, de proposito

  [coop] enabled=1 e o interruptor principal: e o que faz o
  personagem do seu amigo APARECER no seu mundo. Se ficar 0,
  voces conectam mas voce NAO ve o boneco dele.

  [room] code fica vazio: o mod acha o anfitriao sozinho pelo
  SteamID acima, entao voce nao precisa de codigo novo cada vez
  que ele abre o jogo.

----------------------------------------------------------
PASSO 4 - ABRIR O JOGO E CONFERIR
----------------------------------------------------------

  1. Abra o Crimson Desert e carregue seu save.
  2. Painel no canto superior esquerdo (F8 mostra/esconde).
  3. Deve aparecer:
        Network: connected to '<nome do anfitriao>' (XX ms)
     Depois:
        Other player: HP xxxx/xxxx   XX m away

  4. SE O PAINEL NAO APARECER: veja se cdmp.log foi criado em
     bin64. Se nao existe, o mod nao carregou -- quase sempre
     porque o arquivo nao foi renomeado para winmm.dll.

  "Room code: (no code: room: idle)" e NORMAL no seu lado:
  quem cria a sala e o anfitriao, nao voce.

----------------------------------------------------------
CONFIRA A VERSAO (a causa mais comum de nao funcionar)
----------------------------------------------------------

  A primeira linha do painel diz qual versao voce instalou:

        Crimson Desert Multiplayer 0.2.0 (build XXXXXXXXX)

  O build TEM QUE SER:  $build_id_upper

  Se aparecer outro numero, voce esta com um ZIP antigo e o
  co-op NAO funciona: o mod compara a versao ao conectar e
  RECUSA criar o personagem quando elas diferem. O sintoma e
  exatamente esse -- voce VE a distancia no painel, porque a
  troca de posicao funciona, mas nunca ve o boneco.

  Foi o que aconteceu no teste anterior: anfitriao 2BE49E66,
  convidado 1B7B429D, tudo conectado e nenhum personagem.

  Para conferir o arquivo em si: botao direito no cdmp.asi >
  Propriedades > Hash do arquivo. SHA256 esperado:

        $asi_hash

----------------------------------------------------------
COMO SABER SE ESTA FUNCIONANDO
----------------------------------------------------------

  Conectar NAO e o mesmo que funcionar. Chegue PERTO do seu
  amigo e olhe:
    - A distancia fica pequena (10-30 m)?
    - Voce VE o personagem dele andando no mundo?

  As duas coisas precisam ser sim. Se a distancia acompanha
  seus movimentos mas voce nao ve o boneco, me avise.

----------------------------------------------------------
REGRAS DURANTE O TESTE
----------------------------------------------------------

  1. NINGUEM salva enquanto o outro estiver no mundo. Essa e a
     forma mais provavel de estragar um save.
  2. Nao apague o cdmp.log: ele e o objetivo do teste.
  3. Se o anfitriao pedir, aperte Ctrl+F12 junto com ele.

----------------------------------------------------------
PARA DESINSTALAR
----------------------------------------------------------

  Apague winmm.dll, cdmp.asi e cdmp.ini de bin64.

----------------------------------------------------------
O QUE JA ESTA LIGADO
----------------------------------------------------------

  * EXPLORACAO: voces se veem e andam juntos. Teste isso 1o.
  * LOOT COMPARTILHADO: ajude a matar um inimigo do anfitriao e
    voce ganha o SEU drop, sem mexer nas suas missoes ou XP.
    Precisa ter batido no inimigo; vale ate 30 m.
  * SEGURANCA DO CHEFE: voce causa dano e ajuda, mas o golpe
    final e sempre do anfitriao -- se voce matar, a missao dele
    trava. Voce ve a barra de vida do chefe no painel.

----------------------------------------------------------
O QUE AINDA NAO FUNCIONA (honesto)
----------------------------------------------------------

  Chefes em conjunto estao pela METADE: voce ve e machuca o
  chefe, mas a SUA missao nao avanca e ele nao dropa loot para
  voce. Seu mundo nunca teve aquele chefe.

----------------------------------------------------------
MENSAGENS QUE VOCE PODE VER
----------------------------------------------------------

  "Different mod versions: both of you update"
     Os cdmp.asi sao diferentes: um dos dois nao instalou o
     arquivo deste mesmo ZIP. Os DOIS precisam usar este ZIP.

  "Camera: camera block sentinel mismatch"
     Inofensivo. Diagnostico que o patch do jogo moveu de
     lugar. Custa so o nome flutuante na tela.

----------------------------------------------------------
RESUMO
----------------------------------------------------------

  1. Backup do save
  2. 3 arquivos em bin64 (renomear dinput8.dll -> winmm.dll)
  3. Nao editar nada
  4. Abrir o jogo e ver se o painel diz "connected"
"@ | Set-Content -Path (Join-Path $kit 'COMECE-AQUI-PORTUGUES.txt') -Encoding UTF8

# --- zip ------------------------------------------------------------------
$zip = Join-Path $dist 'cdmp-3446-test-kit.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $kit '*') -DestinationPath $zip

$asiHash = (Get-FileHash (Join-Path $kit 'cdmp.asi') -Algorithm SHA256).Hash
Write-Host ''
Write-Host "Kit : $kit"
Write-Host "Zip : $zip  ($([math]::Round((Get-Item $zip).Length / 1MB, 2)) MB)"
Write-Host "cdmp.asi SHA256: $asiHash"
Write-Host ''
Write-Host 'Send the ZIP to your friend. BOTH of you use this same ZIP: the mod'
Write-Host 'compares a build id on connect and warns if they differ (it does not block).'
