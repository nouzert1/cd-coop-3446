# Two-PC test (host + guest)

First serious session with a second player. It comes from the protocol in `docs/research/pendiente-robustez.md` §7,
adapted to what already works (phases 0-3 of `docs/PLAN-PENDIENTES.md`).

- **A** = host, with `cdmp.ini.anfitrion` (host profile) renamed to `cdmp.ini`.
- **I** = guest (the second player), with the `cdmp.ini` from the zip (the guest one).
- Duration: about 60 minutes, talking over voice chat.
- **Before each step, A presses Ctrl+F12** (a mark in the log) and says the number out loud
  ("mark 7: I travels"). If anything odd happens, both press Ctrl+F12 and write it down.
- **Nobody saves the game** during the whole test.

## 6 Oct session with a second player (in order of priority)

Section A already worked with Shadow (5 and 6 Oct). In this session:

1. **Tree with the rope** (the most important; fixes `cd34fd0` and `89508c8`). Both next to the
   same tree (it has to be loaded on both PCs: stay close).
   - **T1** A: grapple, pull until the tree bends and let go to fly off. On I: does A's copy
     grapple, bend the tree and fly off? Does the blue marker disappear on letting go?
   - **T2** A: repeat it 3 times on the same tree and 2 on another. On I: does it work every time or only the
     first?
   - **T3** I does the same and A watches.
2. **Combat** (section C, not yet tested with two PCs; with today's fixes to hits on the
   copies): C1, C2 and C3 above all.
3. **Life cycle** (section B, not tested either): B1, B3 and B4.
4. If there is time left, **A switches weapon** from the quick slot and keeps hitting: on I, does A's
   copy switch weapon too?

Ctrl+F12 at each step and at each odd thing, as always. Nobody saves.

## 0. Preparation (both)

1. Back up `%LOCALAPPDATA%\Pearl Abyss\CD\save` to another folder.
2. **The same zip on both.** Copy to `bin64`: `winmm.dll`, `cdmp.asi` and `cdmp.ini` (A: the
   host one, renamed).
3. Each one sets their `player_name`.
4. If on entering you get the red warning "Different mod versions", stop: one of you
   does not have the right zip.

### Connecting with the room code (this is the normal way now)

The profiles use `transport=steam`, and there is a `[room] code=` key. Nobody
needs to look up a SteamID64 or open a port.

- **A (host):** leave `code=` **empty**. A creates the room and the panel (F8)
  shows a line like `Room code: 000Y4G6`. Read it out.
- **I (guest):** put A's code in `[room] code=`. Lower case and dashes are fine
  (`00oy-4g6` works). Everything goes through Steam.

Then:

1. A starts the game and loads the save first. Wait for A's code to appear.
2. I starts the game and loads the save. Give it up to a minute.
3. `cdmp.log` on the guest says `Room: looking for the host of room …`, then
   either `room … found; connecting to the host` or `not found yet; keep the
   host's game open and the lobby alive, we keep trying`. That last line means
   the lookup is still running, not that it failed.

Before anything else, both confirm the mod loaded at all: **`cdmp.log` exists in
`bin64` and the panel is there.** If not, stop - the connection steps cannot
help, and the cause is almost always `dinput8.dll` not renamed to `winmm.dll`.

## A. Connection and the basics (10 min)

| Step | Who | What | What to look at |
|---|---|---|---|
| A1 | A and then I | Open the game and load the save | Panel (F8): "connected to …" |
| A2 | Both | Fast travel to the same point | The other player's copy appears within a few seconds |
| A3 | Both | Walk, run, jump, climb, glide for 2 min | That the copy does not teleport or sink |
| A4 | Both | **Swim** for 1 min (never tested) | Does the copy swim, float or disappear? |
| A5 | I | Change a piece of equipment and draw the weapon | I's copy on A reflects it |
| A6 | Both | Call the horse, mount, ride together and dismount | That the copy mounts and dismounts correctly |

## B. Life cycle (15 min)

| Step | Who | What | What to look at |
|---|---|---|---|
| B1 | A | Fast travel far away and come back | On I, A's copy disappears and comes back, without looping flickers |
| B2 | I | The same | Same, on A |
| B3 | I | Open the map or the inventory for 30 s and close it | On A, does I's copy jump or speed up when coming back? |
| B4 | I | Die (for example, a high fall) and respawn | On A, I's copy dies, respawns and moves |
| B5 | A | Die and respawn | Same, on I |
| B6 | I | Exit to the main menu, wait 20 s and load again | On A, the copy leaves and comes back |
| B7 | I | **Close the game** and enter again | They reconnect by themselves |

## C. Combat (20 min)

Look for a small group of enemies (2-4). Note: I also sees the enemies from their own save in
the same place (they are not removed yet). If you can, pick a group that I has already killed in their save.

| Step | Who | What | What to look at |
|---|---|---|---|
| C1 | A | **Ctrl+F7** and start fighting | I sees the copies of A's enemies move and attack |
| C2 | I | Hit a copy until it dies | On A, the real enemy staggers, loses health and dies, with loot for A |
| C3 | I | Let the enemies hit them | I loses health and staggers with each hit; do they attack often or almost never? |
| C4 | I | Let A's enemies kill them | I dies with their normal animation and respawns |
| C5 | A | Fast travel in the middle of combat | On I, the copies disappear |
| C6 | I | Fast travel in the middle of combat and come back | That no frozen copies are left |

## C2b. Shared loot - "each takes their own" (15 min)

This is the feature where I gets their own drop from a creature A's world owns.
It needs `enemy_auto=1`, `guest_hits=1` and `guest_loot=1`; the kit's profiles
set all three. **A** does not need `guest_loot` (the enemies are already theirs).

| Step | Who | What | What to look at |
|---|---|---|---|
| L1 | A | Find 2-4 plain enemies. Confirm I's panel and A's panel both show the relay on | If `cdmp.log` says shared loot can never fire (`enemy_auto=0`), stop and fix the profile |
| L2 | I | **Hit one of the copies at least once**, then let A finish it | The point: a creature I never touched must give I nothing, by design |
| L3 | I | Look for a corpse near where the copy died, and loot it | I gets **their own** drop. On A, A gets theirs. Two separate drops from one kill |
| L4 | I | Check the quest log and XP before/after | I's own quests must be **untouched**. Loot and XP from the twin, no quest advance |
| L5 | I | Kill one copy **alone**, without A touching it | On A the real enemy must not die; the twin only exists for kills A's world also had |
| L6 | Both | Note the other player's distance when it fires | Only within 30 m of I, or I gets nothing (with a line in the log saying why) |

If I gets nothing, `cdmp.log` says which condition failed ("we are too far from
it", the variant is excluded, or the rate limit). Send that line - it names the
cause.

## C2c. Boss safety (15 min)

The rule: **the guest must never land the killing blow on a boss.** A boss is a
scripted stage that A's client runs; a guest kill ends it outside the script and
A's quest sticks behind the arena barrier. With `boss_safe=1` (default), I still
does damage and still helps.

| Step | Who | What | What to look at |
|---|---|---|---|
| J1 | A | Go to an **open-world** boss (`*_bossencounter_*`), not a quest/story boss | The safest first target: no barrier, no `noDie`, no loading screen |
| J2 | Both | Fight it. I attacks hard | The boss's health drops from I's blows. I's panel shows a **boss bar** (the guest has no native one) |
| J3 | I | Try to land the killing blow (hit it when it is nearly dead) | **A must get the kill.** `cdmp.log` on A says the boss "survived the finishing blow and is left alive for the host to finish" |
| J4 | A | Kill it | The fight ends **normally**: the boss dies, the quest advances, **no barrier is left up** |
| J5 | Both | If a cutscene starts, keep hitting | Nothing lands either way while A is in the cinematic; I's panel says to wait |
| J6 | A | After the fight | **The host's quest is not stuck.** This is the whole point of the feature |

**What is expected to be missing:** I's own quest is **not** advanced by the kill
and the boss drops **nothing** for I, because that boss never existed in I's
world. That is a known limit, not a bug - do not report it as one. Both worlds
running their own copy of the fight is a much bigger job.

## D. Load (10 min)

| Step | Who | What | What to look at |
|---|---|---|---|
| D1 | Both | Large camp (8 or more enemies), 2 min of fighting with Ctrl+F7 | Stutters, lag, copies that do not appear |
| D2 | Both | City with lots of people, 2 min | Stutters or lag of the other player's copy |

## E. Enemy zone (phase 5, 20 min)

Within 150 m of A, I stops seeing **their own** hostile enemies and sees only the copies of
A's; beyond 170 m their own come back. Design: `docs/research/fase5-suprimir-enemigos-invitado.md`.
Before this, the one-PC test in `docs/PRUEBAS-COOP.md` (zone in dry run) must have gone well.

- **Preparation.** Back up the saves **on both**. `[sniffer] record=1` on both.
  - I: in their `cdmp.ini`, `[coop] suppress=1` (the kit ships `dry`, which only writes to the log).
  - A: nothing (it needs `enemy_auto=1` and `[dev] enemy_relay=1`, which the kit already ships).
- **Place:** the Bleed Bandits camp near (−10.284, 640, −3.383)
  (`cd_m11_m04_monster_beacon_01_0003`) or `Node_Her_EmbernestBeacon` (−10.201, 623, −3.481).
- In I's panel (F8) a line shows: "Host's enemies (150 m zone)" inside the zone and
  "Your enemies" outside.

| Step | Who | What | What to look at |
|---|---|---|---|
| E0 | Both | With `suppress=dry` on I: go to the camp together | Nothing changes. I's log: `Suppress: zone ON`, `WOULD DROP`, `WOULD SWEEP`; A's log: `the guest's enemy zone ON` and `WOULD copy N`. The two sets must match. Then I sets `suppress=1` and restarts the game |
| G1 | Both | Arrive at the camp together | I sees only A's copies, no duplicated bandits. I's log: `zone ON`, `dropped load`, `removed group`; A's log: `copying every zone enemy` and `sending enemy … (zone)` for the whole camp |
| G2 | I | Move 200 m away from A and come back | Beyond 170 m (5 s): the copies leave and I's bandits come back (`zone OFF (host far away), restoring N`, `restored group`, after 2 s `login +CF 1`). On coming back within 150 m they are hidden again |
| G3 | I | Fight their own bandits far from A; A approaches | The zone waits (up to 60 s) for the fight to end: `kept 0x… fighting you`. Afterwards they are hidden and the copies remain |
| G4 | A | Close the game | I turns off the zone (`link lost`) and gets their enemies back |
| G5 | I | Save with the zone on, exit and load that save **without the mod** | The camp is normal (only if G1-G4 went well; with a backup of the saves) |

If something goes wrong (enemies that do not come back, the game complains): I sets `suppress=0`, or moves about
250 m away and comes back (the server reloads their enemies), or goes through a loading screen. If
`Suppress: BREAKER` shows up in the log, the zone turns itself off until the game is restarted.

## What each one sends at the end (one zip per player)

- From `bin64`: `cdmp.log` and, if the game was restarted, `cdmp.1.log`, `cdmp.2.log`…;
- the session's `cdmp_packets_<date>.bin` (the packets `.log` is not needed);
- their `cdmp.ini`;
- the list of marks with what they saw at each one ("M7: A's copy stood still for 5 s");
- video or screenshots, if any;
- if the game closed by itself: the exact time.

## The session is good if

- There are no game crashes or hangs.
- A and B pass without having to restart the game.
- In combat: at least one of A's real enemies killed by I, and I wounded and staggered by
  A's enemies.
