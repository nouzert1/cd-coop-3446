# Builds the ZIP for the two-PC test and writes the folder the friend needs.
#
#   .\scripts\pack-test-kit.ps1
#
# Output: dist\cdmp-3424-test-kit\  and  dist\cdmp-3424-test-kit.zip
#
# The ZIP is identical for both players, which matters: the mod compares a build
# id on connect and shows "Different mod versions" if they do not match, so both
# sides MUST come from the same ZIP.

param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo')]
    [string]$Config = 'RelWithDebInfo'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bin = Join-Path $root "build\bin\$Config"
$dist = Join-Path $root 'dist'
$kit = Join-Path $dist 'cdmp-3424-test-kit'

if (-not (Test-Path "$bin\cdmp.asi")) { throw "Build first: $bin\cdmp.asi not found" }
if (Get-Process CrimsonDesert -ErrorAction SilentlyContinue) {
    Write-Warning 'The game is running; the build id is read from source so this is fine, but close it before deploying.'
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

# --- the read-me the friend actually follows ------------------------------
@'
==========================================================
 Crimson Desert Co-op - test kit (build 1.0.0.3424)
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

If your game is already newer than 1.0.0.3424, tell me - the mod
will not work and I need to re-port it.


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
 Crimson Desert Co-op - test kit (build 1.0.0.3424)
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
$iniText = Get-Content $iniPath -Encoding Unicode -Raw
foreach ($key in 'transport=steam', 'enemy_auto=1', 'guest_hits=1', 'boss_safe=1', 'guest_loot=1') {
    if ($iniText -notmatch [regex]::Escape($key)) { throw "cdmp.ini is missing '$key'" }
}

$lines = foreach ($f in 'cdmp.asi', 'dinput8.dll', 'cdmp.ini') {
    $h = (Get-FileHash (Join-Path $kit $f) -Algorithm SHA256).Hash
    '{0}  {1}' -f $h, $f
}
$lines | Set-Content -Path (Join-Path $kit 'SHA256SUMS.txt') -Encoding ASCII

# --- zip ------------------------------------------------------------------
$zip = Join-Path $dist 'cdmp-3424-test-kit.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $kit '*') -DestinationPath $zip

$asiHash = (Get-FileHash (Join-Path $kit 'cdmp.asi') -Algorithm SHA256).Hash
Write-Host ''
Write-Host "Kit : $kit"
Write-Host "Zip : $zip  ($([math]::Round((Get-Item $zip).Length / 1MB, 2)) MB)"
Write-Host "cdmp.asi SHA256: $asiHash"
Write-Host ''
Write-Host 'Send the ZIP to your friend. BOTH of you use this same ZIP: the mod'
Write-Host 'compares a build id on connect and refuses to pair if they differ.'
