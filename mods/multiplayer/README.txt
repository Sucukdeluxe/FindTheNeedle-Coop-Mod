FIND THE NEEDLE CO-OP MOD  v0.19.6-xRangerDE.41
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

Keys:  F2 panel   Y chat   F8 reconcile the running world   F6 test menu

F6 opens the debug menu the game already has (money, items, unlocks, tech).
It is meant for setting up a session or trying things out. The game marks a
run that used it, so it no longer counts for the leaderboards.

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
