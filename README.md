# Find The Needle co-op mod

Maintained by **xRangerDE**. Community maintenance fork of [AleDev11’s co-op mod](https://github.com/AleDev11/FindTheNeedle-Coop-Mod), version `0.19.6-xRangerDE.36`, based on upstream 0.19.5.

World teardown now stops the old synchronization components before they can run
another update. Machine rescans reject missing or replaced world references,
preventing the reproduced native `get_script()` null-receiver crash.

Guest world transfers now wait for an in-progress native load to finish and then
apply the newest complete world. The host only accepts readiness for the latest
sent generation. Leaving during a load keeps the temporary save directory and
profile protection until the borrowed world has been removed. A requested session
switch from an already loaded guest world resumes automatically after cleanup.

Technology updates now come only from the host. Legacy guest rank messages cannot
change research or credit refunds. Loose-straw moves and removals are accepted only
from their recorded owner; invalid transforms and oversized packets are rejected.
Periodic reliable snapshots recover missed final movement, and sequence checks
prevent older packets from overwriting newer straw positions.

T-junction roles, automatic/manual mode and splitter/joiner conversions now run
through the host transaction queue. Clients rebuild their internal connections
after confirmed role changes. The panel waits for the confirmed configuration
revision, and stale priority packets cannot restore an older role layout.
Pending controls are released when leaving the lobby.

Native splitter and joiner transport tests cover 35 cases, three rotations,
blocked outputs, resumption, priority routing and smart filters. All 84,000 input
strands were collected, including cargo converted into physical conveyor riders.
The fixture checks both material totals and physical ownership.

Pending machine setup and conveyor handoff callbacks now ignore objects that
have already been removed. Conveyor handoffs retain the original item identity
and clear stale boarding markers, so a later removal is not mistaken for a
transfer onto a belt.

Drohnen sammeln jetzt auch ruhendes Heu, das ein Mitspieler abgelegt hat. Der Host übernimmt den Besitz erst nach der vollständigen Kandidatenprüfung; getragene, bewegte, auf Förderbändern liegende oder von anderen Aktionen beanspruchte Gegenstände bleiben ausgeschlossen. Flugphase, Wartezustand, Routenstatus, Trips und Ladungsstand werden an Gäste gespiegelt, sodass Anzeige und tatsächlicher Flug übereinstimmen.

The selling stand now processes cargo and payments only on the host. Guests keep
the native stand presentation but cannot consume mirrored belt cargo or sell it
a second time. The guard also applies while a guest world is loading. Released
items placed directly in the stand by a guest are transferred to the host for
native collection; items still held by a player remain theirs. Hay-sale scale, sack and till effects
are sent separately as sequenced cosmetic events, without crediting money or
spawning collectible coins on guests.

Shop purchases now check the item's actual collision shapes before publishing it.
If the usual drop point is occupied, the host looks for nearby free space.
Same-frame purchases reserve their accepted spaces; a purchase with no free
position is removed before replication and refunded in full. Personal tools
still use the existing inventory path.

The V62 compilation and initial-language menu fixes remain included. All 45
multiplayer scripts compile with the current V62 executable.

Physical cargo waiting inside a lift or hay stairs is protected from recycling
and prop cleanup by its current carrier ownership. Original temporary hold
metadata is restored after each recycling operation.

Hay stairs now share the authoritative moving-cargo channel with hay lifts.
Guests discard stale native cargo copies loaded from the host save before applying
current cargo visuals. Missing or ambiguous carrier mappings wait for the next
build update instead of applying a partial snapshot.

T-splitter lane transfers retain the original cargo until the receiving lane accepts it.
A rejected transfer does not send cargo through a fallible reboarding or floor-spawn
fallback. Recursive transfers of the same cargo are blocked at both ends.

Failed physical item creation now leaves the conveyor record intact. Recursive
requests cannot consume the same record twice, and callback-driven queue changes
are resolved by record identity.

Saving during an unfinished press or wrapper cycle now retains its material.
The native loader receives the unfinished batch in the normal stock or queue;
already released products are not added again. Bale amounts and needle ownership
remain attached to their original queue entries.

Power-line connections, cuts and power-group edits now use host-checked commands.
Reliable snapshots update existing poles and group assignments, including deleted
connections. Delayed actions cannot modify a replacement building or overwrite a
newer change to the same connection or group field. Power-group controls remain
subject to the game's native availability rules.

Pulper pipe construction retains its pending origin between host requests; build
cancellations reach the host in the same queue. Confirmed fittings are synchronized
without replacing the machine, and excluded from generic machine animation.

Route changes now keep dependent machine settings together. Guest-side route rebuilds
do not spawn physical copies of mirrored cargo. Partial building updates retain
existing gates, switch boxes and power-group assignments. Silo output rates,
T-joiner outputs and pelletizer head direction are synchronized.

Machine animation no longer moves belt decks, their collision subtrees or fixed belt-port markers.
Building diagnostics compare internal machine/lift routes and downstream links as well.
Lift direction and head rotation are synchronized; reshaping goes through the host
transaction queue with native cargo transfer and placement checks.
Failed native prop output keeps its production batch and needles for retry. Host
construction requests wait for cooperatively prepared previews; joining restores
player input once after loading, respecting focus, pause and open menus.

Press **M** with the yard vacuum equipped to empty it automatically. Press M again,
use a mouse button, change tools or open a menu to cancel. Output is limited to
64 strands per 0.1 seconds and waits when the aimed belt or container is full.
Container output uses physical straw instead of changing a guest's local stock.
The old standalone `drop_all.gd` is not required.

Building reconciliation now includes lift port reach, riser height, machine tier
and conveyor seat markers. Replicated straight belts preserve their machine-seat
marker. Press/wrapper protection is installed after their native setup and when
a build preview is finalized. Native V62 tests cover scanner/feeder alignment after saving and loading,
lift record transport under backpressure, and press/wrapper release methods.
Native tests also cover 18 full press → wrapper → scanner → selling-stand
routes with left/right 45°, 90° and 135° curves, three rotations and both
scanner tiers. All 442 wrapped bales (25,920 strands) were sold with the
expected payout after five simulated minutes of blocked output per case.
The exact original reported save layouts still need reproduction.

The ZIP does not replace `override.cfg`; retain your existing renderer and other mod settings.
Includes automatic building reconciliation, guest quest completion, and fixes
for conveyor edits, cargo pickup, prop ownership and machine settings.
Settled props receive reliable position confirmation with stale-update rejection.
Dropping a local item preserves other players’ carried-item ownership.
Normal shop and construction transactions are checked and executed by the host.
Existing saves remain compatible; demolition and reversal work without first selecting
a construction type, and host-confirmed platform cuts are replicated to guests.
Loose floor hay is retained when the host disables automatic cleanup, including
overflow cleanup; guests use the host policy without changing their saved preferences.
Conveyor overflow cleanup also follows the host’s automatic-cleanup setting, and
clients do not independently delete conveyor cargo above their local limit.
Tools are personal: Q drops a physical tool and removes it from that player’s inventory.
The host saves individual inventories and resolves competing purchases and pickups.
Quest money and building gifts are granted only by the host, including after resync.
Shop retrieval is also performed by the host and skips carried or machine-claimed
objects. Confirmed drop/retrieval actions feed quest tracking directly. A session
change clears stale inventory deltas and pending tool action locks. Technology
purchases are rejected while the world or requesting player is loading.
Loose hay on conveyors now retains its detailed shape at distance. Belt batching and
draw-distance culling remain active. This can increase GPU work on large visible
conveyor networks; physical quantities, collisions and transport are unchanged.

Automatic diagnostics record repeated conveyor, prop, building, hay and machine
synchronization discrepancies and stalled transaction, inventory and state
acknowledgements. Reports stay local in `user://mp_diagnostics.jsonl`, with one
previous log retained. Short loading/building transitions are ignored; confirmed
findings and recovery are logged with category and count only. The diagnostic
layer does not alter saves, retry purchases or force a world reload.

Guests apply host-confirmed drone settings without local placement rejection or route
planning. The host continues to validate new commands. Machine animation packets
are checked before application, and stale parts/materials cannot receive cached
animation or effect updates. A later teardown test reproduced a native
`get_script()` null-receiver crash with the same native fault signature as the
local historical dump. The teardown fix prevents that reproduced path; the
original historical GDScript call site cannot be recovered from that dump.

**Maintenance preview:** the current V62 engine compiles all 45 scripts. The
selling-stand fix passes 50 native authority/ownership/presentation checks and
84 checks across three real local processes under packet loss, duplication and
delay. The previous shop-placement fix remains included. Its
shop-placement checks pass 23 native assertions and 216 transaction checks with
three local processes under injected packet loss, duplication and delay. They
cover occupied space, simultaneous purchases, refunds and world reloads.

Native production tests pass 1,860 assertions across eight chain runs, delivering
192 complete wrapped bales and recovering all 24 injected needles. Physical
feeding waits for enough space at the inlet. Deliberately dropping another tuft
onto an occupied inlet invokes the game's native "No room" ejection; that behavior
is not changed by this revision. Lift and stairs tests pass 281 single-body and
76 mixed-load checks, plus 5,780 material-ledger checks, including a ten-section
lift, blocked outputs and resumption.

These controlled scenes do not reproduce every original save layout or the
historical guest crash. Native shutdown resource warnings remain, and two-PC
Steam/WAN testing is outstanding. The previous offscreen benchmark showed
additional GPU cost for detailed hay; no gameplay-FPS guarantee is implied.
Use the same mod version on every peer.

Raw hay now waits at the press intake for consumption, including newly created
physical tufts that are temporarily absent from collision queries. The press
accepts tuft records as raw hay. The wrapper holds unsupported tuft records at its
input instead of passing them through. A failed handoff to an existing connected
belt retains the current rider for retry, including near-view and shared-deck
junctions. Full or incompatible destinations can therefore back up the line.
Open, unconnected ends retain native behavior. Missing output managers postpone
product release instead of marking a batch delivered. Existing buffered material,
needles and processing state are preserved when machine hooks are restored.

Belt snapshots wait for local building reconstruction before they are applied.
Invalid snapshots leave the current mirror intact. Session shutdown restores only
the mirror holds owned by the mod, preserving native machine intake holds. The
experimental endpoint reversal from `.12` has been removed: it could move cargo
onto a path with the wrong transport direction.

See [German installation notes](mods/multiplayer/ANLEITUNG-DE.txt).


Adds co-op multiplayer to the Find The Needle demo. Several players dig the
same haystack, share the money and see each other's buildings.

Connections go through Steam's relay network, so there is no port forwarding
and no IP addresses to exchange. The host invites from the Steam friends list.

Unofficial mod, not affiliated with the game's developer. It contains no game
files, only its own scripts and a CC0 player model. Spanish version of this
file: [README.es.md](README.es.md).

![Two players in the same yard](screenshots/coop.png)

## Requirements

* Find The Needle demo (free on Steam), V62 / Steam build 25867630 for this revision. Older builds have not been validated with these native API hooks.
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

* The new selling-stand visual channel covers hay sales. Tool-sale and
  needle-scrap receipts are not yet mirrored through this channel.

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
