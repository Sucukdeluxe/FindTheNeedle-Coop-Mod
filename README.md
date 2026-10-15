# Find The Needle co-op mod

Maintained by **xRangerDE**. Community maintenance fork of [AleDev11’s co-op mod](https://github.com/AleDev11/FindTheNeedle-Coop-Mod), version `0.19.6-xRangerDE.62`, based on upstream 0.19.5. This build targets **Find The Needle Demo V62**.

Every player needs the game and the same mod version. Use the Multiplayer Addons ZIP if you also use the packaged Production Speed, Tool Upgrades and Autonomous Mice add-ons. Never share your personal `mp_settings.cfg`, saves or diagnostic logs as part of an installation package.

## Balanced prices and legacy credit

Bucket capacity upgrades now cost 10,000 in total, faster pouring 12,000, and precise needle location 7,500. Sale ranks 5–8 cost 250, 300, 350 and 365. Existing ranks are never reduced or charged again.


Sale price now has 20 ranks, each adding five percentage points to the base price (up to ×2). All purchased upgrade levels are preserved. The 20-rank sale-price ladder has a monotonic price curve and still costs 12,885 in total. Seventeen upgrade ladders use fixed total budgets and no additional native late-rank surcharge.

When loading an older save, recorded overpayments for the repriced ranks are credited once, deducting refunds already received in .53 to the shared balance. Only the host or single-player performs this calculation. The credit marker and balance are stored in the same save snapshot; guest joins and repeat loads cannot pay it again. Gifted ranks and purchases without a recorded paid amount are not assigned an estimated refund. Existing saves are not modified by copying the mod files; the credit applies on the next load and is retained when the game is saved.

## Install

1. Close the game and keep a backup of the existing mod and saves.
2. Copy the ZIP’s `mods` folder beside `FindTheNeedle.exe`.
3. Keep your existing `override.cfg` settings. Under `[autoload]`, ensure `MPMod="*mods/multiplayer/mp.gd"` is present. The add-on package includes its own installation notes for its additional autoloads.
4. Start through Steam. The host opens a lobby and loads the existing save; friends join through Steam invitations.

The base ZIP does not replace `override.cfg`. See [German instructions](mods/multiplayer/ANLEITUNG-DE.txt) for detailed controls.

## New controls and upgrades

- **Building controls:** hold R and move the mouse horizontally for free rotation; tap R for the original steps. F6 reverses the belt being drawn. Ctrl+G toggles parallel placement beside a straight, level conveyor. Connection and collision checks still apply. In F7 view, hover a machine and press E for its existing settings.
- **House building:** walls snap to exposed platform edges in native wall modules. Roofs align with wall tops and eaves. Optional charcoal, cream, red and green wall/window/door variants retain the native materials and save their color.
- **Sale stations:** press E at a sale station to move an empty station. Four upgrade ranks unlock up to five total sale stations; extra compact scales cost 500 each and use the same prices and shared account. Moving a loaded or unsettled station is blocked. The original stand remains available in old saves.
- **Direct arm connections:** arms can deliver directly into merger/splitter paths and take cargo from their paths. Manual links survive saves and resynchronization. The native merger scheduler preserves continuous center movement and scales with transport upgrades.
- **Right-click hopper intake:** while aiming at the hopper, right-click to transfer carried raw hay from your hand, shovel, pitchfork, sand shovel or vacuum. Partial transfers leave the unaccepted remainder in its source; embedded needles stay attached until the complete corresponding load enters. M remains available for the vacuum.
- **F7 building camera:** toggle the overhead view directly, then use B to select a building. WASD or arrows pan, Shift pans faster, the wheel zooms, left click places and right click cancels the current step. F7 or Escape restores the previous view. Building remains subject to host validation and a 24 m area around the actual player. F7 takes priority over the native debug-report binding. Ctrl+F7 still opens the report; other customized F7 actions are respected. Use PageUp/PageDown to change building height while arrow keys pan.
- **Loading Hopper:** a 2,500-cost structure. Place it freely or at a belt input. Press **M** while aiming at it to transfer vacuum contents, throw loose hay into the opening, or use a robotic arm. **E** controls output and portions from 100 to 1,000 (limited by belt upgrades), and purchases per-hopper capacity from 10,000 to 100,000. Existing hoppers keep their 50,000 capacity and contents. Full hoppers retain the unaccepted remainder.
- **Four/six/eight-port mergers and splitters:** two independent paid unlock chains, each 4 → 6 → 8 after Smart Splitter. Unlock prices are 1,500 / 4,000 / 8,000; each structure then costs 2,000 / 3,500 / 5,000 to build. A merger combines 3/5/7 inputs into one output; a splitter routes one input to 3/5/7 outputs, skipping blocked exits. Insert directly into a straight, level conveyor or place freely. Existing belt material is credited and cargo retained; a blocked insertion leaves the original belt unchanged. Existing mergers remain functional. New construction needs the new unlock. **E** selects the merger output or splitter input only when empty. Numbered side plates, native rollers and animated directional tread sectors identify the connections.
- **Larger Belt Portions:** 100 → 200 → 300 → 500 → 1,000 strands per portion for direct M output and hoppers. Four upgrades cost 25,000 in total. A blocked belt retains the hay in the vacuum or hopper.
- **Arm speed:** 20 total ranks; all 20 ranks cost 80,000 combined. Already purchased ranks are preserved.
- **Lift / stairs speed:** ten ranks up to four times their base transport speed, in addition to the belt motor. Existing ranks are preserved.
- **Splitter / merger speed:** ten ranks up to 250% internal speed, 40,000 combined. Applies to normal, compact, U, smart and T variants. Filters and blocked exits still apply.
- **Double Jump:** one shared 2,500 purchase in Fitness after Spring Heels. Release jump after taking off, then press again for one extra airborne jump. Landing restores it. An equipped jetpack retains its own control behavior.
- **Next Load details:** remaining buried needles and the number of represented types are shown on the delivery board and in its detail window.

Existing vacuum upgrades reach 50,000 capacity across 41 ranks and 1,000 strands/second at suction rank 20, with the complete capacity ladder costing 75,000 and the complete suction ladder costing 50,000. Outside direct belt/hopper transfers, M retains its existing physical-output behavior. The separate `drop_all.gd` is not needed.

The hopper has an industrial steel model and a matching image in the building catalog and hotbar. Its native hay surface follows the stored amount and stays inside the sloping walls. A brief intake effect runs only on a stock increase; restored contents and repeated snapshots do not replay it. The effect is visual only and creates no collectible hay. Its stock and controls appear in a readable HUD card. Single-player uses local checked transactions for construction and vacuum transfer, without opening a network session.

## Guest vacuum recovery

Vacuum fill and pending direct-transfer reservations are stored in `user://mp_vacuum_guest.0.dat` and `user://mp_vacuum_guest.1.dat`. These are private local recovery files; do not distribute them with the mod. Unchanged fill does not cause disk writes. Failed journal reads or writes lock the vacuum and report the problem instead of clearing the recovery data.

## Prestige and scanner dismantling

Use the delivery board’s Next Load sheet, then **Prestige · New map**. The host (or single-player) can preview the sale and select Standard, Large, Huge or Mountain once the physical haystack is empty and all six needle types have been collected. Buildings and saleable goods are converted to money, while tools, unlocks and purchased upgrades are retained. A new cycle requires its six needle types again. A backup is written before the map changes.

Scanners can be dismantled with needles inside. Unique unclaimed needles are placed on the floor; a needle already held by a player is not spawned again.

## Synchronization fixes

Needle pickup, scanner withdrawals and cabinet deposits now use host-owned identities. Repeated or competing requests cannot spend the same identity twice. Duplicate scanner references are normalized; separate needles of the same type remain separate. Historical cabinet stock is not deleted based on guesses about its origin.

Press recovery also covers raw physical riders beyond its intake and raw hay on a directly connected wrapper deck. Guest pelletizer changes are queued before the first host baseline can overwrite them. Splitter/merger jam detection compares actual cargo movement, while keeping native filtering and backpressure.

Robotic-arm operating status, claw loads and income/minute come from the host. Water-tap recovery, personal tool inventories, shared quests and purchases, host-side selling, mouse visuals and prior conveyor/lift corrections remain included. Stable machine hierarchies reuse cached part mappings; changed hierarchies rebuild them.

## Synchronization performance

Unchanged hayfield height buffers now skip the per-vertex GDScript scan after an exact comparison. Changed and restored heights still use the existing delta publication. An isolated native comparison measured 451 microseconds versus 2 microseconds median per unchanged-field call; this is a routine-level CPU measurement, not a total frame-rate result.

The local checks include 1,200 conveyor records, a guest process crash and rejoin, and production through a press, wrapper, scanner and 90-degree bend to sale. Downward-lift tests cover eight item kinds, backpressure and a junction rebuild. Guest vacuum contents now use the recovery journal described below.

## Verification and limits

Validation combines isolated GDRE/Godot tests with actual Demo V62 headless instances using the native BeltRunCore extension. Separate host and guest save directories protect existing saves. Local multiplayer tests cover scanner inventory, competing and repeated purchases, personal tool transfers, vacuum/hopper quantities, production routes and the complete prestige save/reload. Packet loss and duplication are injected on loopback; Steam multiplayer is not started.

These results do **not** establish GPU frame rates, a two-PC Steam/WAN session, or freedom from every possible bug. Headless runs cannot measure rendered graphics performance. The supplied older game copy identifies as V33 and was not used as the V62 compatibility baseline. Host and single-player saves now include the vacuum fill and matching transfer reservation in the same snapshot as the world. Loading restores that snapshot once, including an uncommitted reservation or a transfer already received by a hopper. A save is deferred while shared floor cleanup is pending, and pause-menu exit waits for a successful save. A guest process restart now restores its last committed vacuum fill from a local journal scoped to the player profile and world. Open direct belt/hopper transfers are reconciled against host receipts before the vacuum is unlocked. The journal uses two checked generations and ignores incomplete writes. Keep the same local profile and host world when reconnecting. Recovery of unconfirmed local cleanup reports and rollback of a host to an earlier world snapshot remain outside this fix. Unsaved progress after a host crash still rolls back to the last successful save.

Only the host saves the shared world. Tools remain personal. Machines simulate on the host, with guest visual replication. Keep both installations on the same release and back up a save before changing mod versions. Do not downgrade a save containing new hoppers without a compatible backup.

## Credits and source

Original multiplayer mod: [AleDev11](https://github.com/AleDev11/FindTheNeedle-Coop-Mod). Farmer model: Quaternius, CC0. GodotSteam: MIT. Steamworks SDK: Valve Corporation. The hopper shell is original procedural geometry in this fork; its feeder and cabinet detail reference installed game resources at runtime. Game binaries, decoded game sources, private saves and local test fixtures are not distributed in this repository.

The optional [Production Speed Update](https://www.nexusmods.com/findtheneedle/mods/9), [Collection Tool Upgrades](https://www.nexusmods.com/findtheneedle/mods/11) and [Autonomous Mice](https://www.nexusmods.com/findtheneedle/mods/7) originated with BadHippo. Their additional production/tool ranks and autonomous mouse behavior are separate from this fork's multiplayer integration and balance changes. The main ZIP does not include those add-ons. The integrated M-key transfer does not require the separate [Vaccuum Drops All](https://www.nexusmods.com/findtheneedle/mods/24) by Pruplexedv6.
