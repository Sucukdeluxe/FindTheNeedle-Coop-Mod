# Find The Needle co-op mod

Private maintenance fork, version `0.19.6-local.6`, based on upstream 0.19.5.
Includes automatic building reconciliation, guest quest completion, and fixes
for conveyor edits, cargo pickup, prop ownership and machine settings.
Normal shop and construction transactions are checked and executed by the host.
Existing saves remain compatible; demolition and reversal work without first selecting
a construction type, and host-confirmed platform cuts are replicated to guests.
Loose floor hay is retained when the host disables automatic cleanup, including
overflow cleanup; guests use the host policy without changing their saved preferences.
Tools are personal: Q drops a physical tool and removes it from that player’s inventory.
The host saves individual inventories and resolves competing purchases and pickups.
Quest money and building gifts are granted only by the host, including after resync.
See `mods/multiplayer/ANLEITUNG-DE.txt` for the patched installation notes.

Adds co-op multiplayer to the Find The Needle demo. Several players dig the
same haystack, share the money and see each other's buildings.

Connections go through Steam's relay network, so there is no port forwarding
and no IP addresses to exchange. The host invites from the Steam friends list.

Unofficial mod, not affiliated with the game's developer. It contains no game
files, only its own scripts and a CC0 player model. Spanish version of this
file: [README.es.md](README.es.md).

![Two players in the same yard](screenshots/coop.png)

## Requirements

* Find The Needle demo (free on Steam), build V26 or newer
* Windows 64-bit
* The same mod version on every machine
* The game has to be launched from Steam, or the invites will not work

## Install

No installer to run: copy a folder, add two lines to a text file.

1. Download the zip from [Releases](../../releases) and unzip it.
2. Copy the `mods` folder next to `FindTheNeedle.exe`. In Steam: right-click
   the game, Manage, Browse local files.
3. Open `override.cfg`, in that same folder, with any text editor and add:

   ```ini
   [autoload]
   MPMod="*mods/multiplayer/mp.gd"
   ```

   If the file already has an `[autoload]` section, only the second line is
   needed.
4. Launch from Steam. There is a MULTIPLAYER entry in the main menu.

If you would rather not edit the file, `tools/install-helper.bat` (also
attached to each release) does that one step for you. It is not inside the
download because Nexus quarantines uploads that contain scripts.

To uninstall, remove that line and the `mods/multiplayer` folder, or run
`tools/uninstall-helper.bat`. Mod settings and personal inventory data remain in the game’s user directory.

Game updates replace `override.cfg`, so add the lines again after each one.

## Playing

Host: MULTIPLAYER, CREATE GAME, INVITE FRIENDS, then start or load a save as
usual. Everyone else joins by accepting the Steam invite. If their game is
closed, Steam starts it and takes them in.

There is a direct-IP mode under "IP connection (advanced)" as a fallback.

| Key | Action |
|-----|--------|
| F2 | Multiplayer panel |
| Y | Chat |
| F8 | Resync the world |
| F6 | Test menu |

F6 opens the debug menu the game already has: money, items, unlocks and the
tech tree, plus buttons to take money away. It is there to set a session up or
to try something out. The game marks any run that used it, so it stops
counting for the leaderboards.

## What is synced

* The haystack. Everyone digs the same pile.
* Buildings, placed and demolished.
* Money, debt, hay sold, needles found, the collection.
* The tech tree.
* Uncovered needles. They show up for everyone and can only be handed in once.
* New hay loads, which resync every client.
* Player positions, names and the tool in hand.
* Loose items: buckets, sacks, bales, wads. You see what the others pick up,
  carry, drop and throw, and you can pick up their things yourself.
* What is riding on the belts.
* Loose straw on the ground, so everyone digs into the same mess.
* How the machines move, their smoke and lamps, and their settings.
* The straw and the needle in your bare hands, drawn in your farmer's fist.

## Languages

The interface follows the game's own language setting. English, Spanish,
German, French, Italian, Czech, Polish, Russian, Turkish, Japanese, Korean and
Chinese are included, in `mp_i18n.gd`. Anything else falls back to English.
Tool names are not translated by the mod: they go through the game's own
translations, so they read the same as in the rest of the UI.

## Known limitations

* Machines run on the host only, so the same hay cannot be counted twice.
  Clients see them move, smoke and light up, and their settings match, but the
  work itself happens on one machine.
* Remote shovel and fork loads use a visual model, not individual replicated strands.
* Money, research and buildings are shared. Tool inventories are personal.
  A physical tool must be dropped before another player can pick it up or sell it.
  Existing shared equipment seeds each player’s personal inventory once.
* Only the host saves. Clients never write to their own save files.
* The online leaderboard is disabled while the mod is loaded.
* Shop and building transactions wait for host confirmation. A changed price
  or insufficient shared balance rejects the purchase. Other economic events
  still use the existing state-delta synchronization.
* Who holds a loose needle is shared; where one lies can differ a little
  between players until someone picks it up.

## Troubleshooting

No MULTIPLAYER entry: the game updated and replaced `override.cfg`. Add the
two lines again.

"Steam not available": the game was launched from the .exe instead of Steam.

A friend cannot join: check that both of you run the same mod version. The
panel shows it.

Building layouts are reconciled automatically. F8 is also available for an
explicit in-place reconciliation. Everyone must use the same mod version.

The game crashes: send the newest crash log from
`%APPDATA%\Godot\app_userdata\Haystack Incremental\crashes\` together with
`mp_trace.log` from the folder above it (or `mp_trace.prev.log` if the game was
opened again since). The trace only lists which messages the mod received and
when, so we can see what was being handled when it went down.

Anything else: open an [issue](../../issues) with the log from
`%APPDATA%\Godot\app_userdata\Haystack Incremental\logs\`.

## How it works

The demo ships as one encrypted Godot `.pck`, which the mod never touches.

Godot reads `override.cfg` next to the executable at startup. The installer
registers `mp.gd` there as an autoload, so the mod is a handful of `.gd` files
living outside the game.

The demo has no Steam API, so the mod loads the
[GodotSteam](https://godotsteam.com) GDExtension at runtime with
`GDExtensionManager.load_extension()` and initialises Steam under the demo's
app id. That provides lobbies, invites and `SteamMultiplayerPeer`.

To let someone join, the host serialises its world in the same format the game
uses for saves, sends it compressed, and the client loads it with the game's own
loader into a scratch slot.

Syncing after that is incremental. The haystack is a height field and each peer
sends the vertices it changed. Buildings are diffed against the game's
`to_array()` and rebuilt through its own loader. Money and counters travel as
deltas. Shop and building actions use a host transaction queue with native
validation, sequence numbers and cached receipts. Clients replicate the
resulting world changes after approval.

Everything is applied by walking the live scene tree and calling the game's own
methods.

## Repository layout

```
mods/multiplayer/     what ships in the release
  mp.gd               session, lobby flow, RPCs
  mp_world.gd         world sync (haystack, buildings, state, needles)
  mp_steam.gd         GodotSteam loading, lobbies, invites
  mp_ui.gd            panel, chat, notifications
  mp_avatar.gd        the other players' figures
  mp_i18n.gd          UI strings per language
  tool_poses.cfg      hand-placed held tools (optional, made with tool_poser)
  models/             farmer model (CC0)
  steam/              GodotSteam GDExtension (prebuilt)
dev/avatar_calib.gd   live avatar height tuning, not shipped
dev/tool_poser.gd     place held tools on the farmer by hand, not shipped
dev/tool_poser.bat    starts the game with the tool poser
dev/models/           tooling used to prepare the model
docs/                 Nexus page copy
```

Nothing is compiled. Edit a file, restart the game.

Remote players are an animated farmer, `mods/multiplayer/models/farmer.glb`,
loaded at runtime with `GLTFDocument`. The overalls and the hat band take the
player's colour, the head follows where they look, the legs bend when they
crouch, and the clip (Idle_Neutral, Walk, Run) follows their speed. If the file is
missing or fails to load, an older figure made of primitives stands in. The
`.glb` is the original pack trimmed to those three clips with
`dev/models/slim_glb.py`, which takes it from 1.3 MB to 500 KB.

Tool models hang off the avatar's hand. Each one is scaled to its real length
(`TOOL_LENGTHS`) along its longest axis and turned so the working end points
away from the hand. Set `flip_tool` on an avatar to turn a model 180 degrees
while testing a new one. A tool with an entry in `tool_poses.cfg` skips that
guess and uses the saved position, rotation and length instead.

Regression and network test harnesses are kept locally and are not included in
the repository or distribution packages.

`dev/avatar_calib.gd` puts a farmer in front of you that copies your look and
crouch, so you can tune `MODEL_HEIGHT` and `CROUCH_DROP` with the arrow keys
and save them with F9. How to enable it is at the top of the file.

`dev/tool_poser.gd` swaps the main menu for an empty stage with a farmer
holding the tool you pick (1-6). Drag the move (W) or rotate (E) gizmo on the
tool, or use the sliders on the right, and preview looking up and down,
walking, crouching or a turntable. The camera orbits, pans and flies like in
the Godot editor. C switches to an optional crouch pose, for tools that should
sit differently when crouched; without one they keep the standing pose. F9
writes `tool_poses.cfg` into the mod folder. The keys are
listed at the top of the file. `dev/tool_poser.bat` starts the game with it and
puts `override.cfg` back when you close the game.

Entry 7 is the wheelbarrow. The gizmo moves and turns it from the farmer's
feet, and the farmer grabs both handles as you go. The grips are found on the
model; if they're off, click a white dot (or press G) and drag it. It saves to
`[wheelbarrow]` in the same file, and without one the mod uses its own default.

## Credits

Mod by AleDev11. Find The Needle by
[FindTheNeedleDev](https://x.com/haydeveloper).
Farmer model from the [Ultimate Modular Men Pack](https://quaternius.com/packs/ultimatemodularcharacters.html)
by Quaternius, CC0. [GodotSteam](https://godotsteam.com) is MIT. Steamworks SDK
is Valve's.

MIT licence, see [LICENSE](LICENSE).
