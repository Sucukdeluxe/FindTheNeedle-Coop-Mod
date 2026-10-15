FIND THE NEEDLE CO-OP MOD  v0.19.6-xRangerDE.58
==================================

Unofficial mod. Every player needs the game (the free Steam demo) and this
same mod version. Spanish version of these notes: LEEME.txt

The connection runs over Steam's relay network: no port forwarding, no IP
addresses. The host invites from the Steam friends list.

INSTALL (two steps, no installer to run)
----------------------------------------
1. Close the game and back up the existing mod and saves. Copy the "mods" folder next to FindTheNeedle.exe.
   In Steam: right-click the game, Manage, Browse local files.

2. Open "override.cfg" (same folder as FindTheNeedle.exe) with Notepad and
   add these two lines at the end, then save:

[autoload]
MPMod="*mods/multiplayer/mp.gd"

   If the file already has an [autoload] line, just add the MPMod line
   under it.

3. Start the game FROM STEAM. The main menu now has MULTIPLAYER.

To uninstall: delete the MPMod line from override.cfg, and delete the mods/multiplayer
folder. Personal inventory metadata remains in the host save.

Game updates replace override.cfg, so add the two lines again after each one.

PLAYING
-------
Host: MULTIPLAYER, CREATE GAME, INVITE FRIENDS, then start or load a save as
usual. The others accept the Steam invite. If their game is closed, Steam
opens it and takes them in.

Keys:  F2 panel   Y chat   F7 overhead building   F8 reconcile   F6 test menu

F6 opens the debug menu the game already has (money, items, unlocks, tech).
It is meant for setting up a session or trying things out. The game marks a
run that used it, so it no longer counts for the leaderboards.

NEW BUILDING AND MOVEMENT OPTIONS
---------------------------------
F7 opens the overhead camera directly. Press B to select a part. WASD/arrows pan,
wheel zooms, F7/Escape returns. Host validation and a 24 m build area apply.
Loading Hopper: 2,500 to place freely or at a belt input. M unloads the vacuum;
throw loose hay into the opening or use a robotic arm. E configures output and
capacity. New hoppers start at 10,000 and upgrade to 100,000. Existing hoppers
retain 50,000. Four/eight-port mergers unlock with Smart Splitter. Insert them
into a straight, level conveyor or place them freely. Connected cargo and paid
belt material are preserved. Native rail/roller meshes and materials replace
the old model; port labels sit outside the transport lane.
Band portions upgrade from 100 to 1,000 (25,000 total). Arm speed has 20 ranks;
lifts/stairs and distributors have separate speed cards.
Double Jump costs 2,500 in Fitness after Spring Heels. Release and press jump
again in mid-air. Landing restores the extra jump; the unlock is shared.
This revision includes actual V62 headless host/two-guest tests on loopback.
Steam sessions and rendered GPU performance remain unverified.

LANGUAGES
---------
The mod follows the language you set in the game. English, Spanish, German,
French, Italian, Czech, Polish, Russian, Turkish, Japanese, Korean and
Chinese are included.

WHAT IS SHARED
--------------
  - The haystack. Everyone digs the same pile.
  - Buildings, placed and demolished.
  - Money, debt, hay sold, needles found, the collection.
  - The tech tree; upgrade purchases are validated and charged by the host.
  - Shared quest progression; the host grants quest money and gifts once.
  - Personal tools saved per player. Q drops the tool and removes it from that inventory.
  - Uncovered needles. Everyone sees them, and they count once.
  - New hay loads, which resync every client.
  - Player positions, names and the tool in hand.
  - Loose items: buckets, sacks, bales, wads. You see what the others pick
    up, carry, drop and throw, and you can pick their things up yourself.
  - What is riding on the belts.
  - Loose straw on the ground, so everyone digs into the same mess.
  - How the machines move, their smoke and lamps, and their settings.
  - The straw and the needle in your bare hands, in your farmer's fist.

KNOWN LIMITATIONS
-----------------
  - Machines run on the host only, so the same hay cannot be counted twice.
    Clients see them move, smoke and light up, and their settings match, but
    the work itself happens on one machine.
  - Remote shovel and pitchfork loads use a visual representation, not an exact
    copy of every physical strand.
  - Tool pickup and drop wait for host confirmation. One physical tool has one owner.
    Existing shared equipment seeds each player’s personal inventory once.
  - Only the host saves. Clients never write to their own saves.
  - The online leaderboard is disabled while the mod is loaded.
  - Shop, upgrade and building transactions are checked by the host. Other money
    events retain the existing state-delta synchronization.
  - Loose floor hay is retained when the host disables automatic cleanup.
  - Who holds a loose needle is shared; where it lies can differ a little
    between players until someone picks it up.

CREDITS
-------
  Farmer model: Ultimate Modular Men Pack by Quaternius, CC0.
  GodotSteam (GDExtension), MIT, https://godotsteam.com
  Steamworks SDK, (c) Valve Corporation.
  Source: https://github.com/AleDev11/FindTheNeedle-Coop-Mod

Visual fix: loose hay on belts keeps its detailed geometry at distance. Normal
perspective still makes distant objects smaller. Large visible belt networks
can require more GPU work. This maintenance preview needs further two-PC testing.

Physical shop purchases use nearby free space and same-frame reservations.
If no space is available, the purchase is fully refunded before replication.

SAVE RECOVERY
Host/single-player saves include vacuum fill and its pending M-transfer reservation
with the world. Shared cleanup defers saving until completion. Pause-menu exit
requires a successful host/local save. Complete guest-process-crash recovery is
still incomplete; this release does not promise lossless recovery of unsaved progress.

BALANCING .53
Sale price has 20 ranks at five percentage points each, reaching twice the base price. Existing ranks are preserved. Recorded overpayments for repriced upgrades are credited once when the host or single-player loads the save; gifted ranks and purchases without a recorded price are not estimated. The credit is saved together with the balance. Vacuum capacity costs 75,000 total, suction 50,000, arm speed 80,000 and distributor speed 40,000.
