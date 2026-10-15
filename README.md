# Find The Needle co-op mod

Maintained by **xRangerDE**. Community maintenance fork of [AleDev11’s co-op mod](https://github.com/AleDev11/FindTheNeedle-Coop-Mod), version `0.19.6-xRangerDE.54`, based on upstream 0.19.5. This build targets **Find The Needle Demo V62**.

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

- **F7 building camera:** select a building first, then toggle the overhead view. WASD or arrows pan, Shift pans faster, the wheel zooms, left click places and right click cancels the current step. F7 or Escape restores the previous view. Building remains subject to host validation and a 24 m area around the actual player. F7 takes priority over the native debug-report binding. Ctrl+F7 still opens the report; other customized F7 actions are respected. Use PageUp/PageDown to change building height while arrow keys pan.
- **Loading Hopper:** a new 2,500-cost structure in the conveyor/build catalog. Place it at a free, level conveyor input. Aim at it with the yard vacuum and press **M** to transfer up to its 50,000-strand capacity. It feeds only when the belt accepts cargo. Empty it before dismantling. Hopper operation works in single-player and multiplayer.
- **Larger Belt Portions:** 100 → 200 → 300 → 500 → 1,000 strands per portion for direct M output and hoppers. Four upgrades cost 25,000 in total. A blocked belt retains the hay in the vacuum or hopper.
- **Arm speed:** 20 total ranks; all 20 ranks cost 80,000 combined. Already purchased ranks are preserved.
- **Lift / stairs speed:** ten ranks up to four times their base transport speed, in addition to the belt motor. Existing ranks are preserved.
- **Splitter / merger speed:** ten ranks up to 250% internal speed, 40,000 combined. Applies to normal, compact, U, smart and T variants. Filters and blocked exits still apply.
- **Double Jump:** one shared 2,500 purchase in Fitness after Spring Heels. Release jump after taking off, then press again for one extra airborne jump. Landing restores it. An equipped jetpack retains its own control behavior.
- **Next Load details:** remaining buried needles and the number of represented types are shown on the delivery board and in its detail window.

Existing vacuum upgrades reach 50,000 capacity across 41 ranks and 1,000 strands/second at suction rank 20, with the complete capacity ladder costing 75,000 and the complete suction ladder costing 50,000. Outside direct belt/hopper transfers, M retains its existing physical-output behavior. The separate `drop_all.gd` is not needed.

The hopper has an industrial steel model and a matching image in the building catalog and hotbar. Its stock and controls appear in a readable HUD card. Single-player uses local checked transactions for construction and vacuum transfer, without opening a network session.

## Prestige and scanner dismantling

Use the delivery board’s Next Load sheet, then **Prestige · New map**. The host (or single-player) can preview the sale and select Standard, Large, Huge or Mountain once the physical haystack is empty and all six needle types have been collected. Buildings and saleable goods are converted to money, while tools, unlocks and purchased upgrades are retained. A new cycle requires its six needle types again. A backup is written before the map changes.

Scanners can be dismantled with needles inside. Unique unclaimed needles are placed on the floor; a needle already held by a player is not spawned again.

## Synchronization fixes

Needle pickup, scanner withdrawals and cabinet deposits now use host-owned identities. Repeated or competing requests cannot spend the same identity twice. Duplicate scanner references are normalized; separate needles of the same type remain separate. Historical cabinet stock is not deleted based on guesses about its origin.

Press recovery also covers raw physical riders beyond its intake and raw hay on a directly connected wrapper deck. Guest pelletizer changes are queued before the first host baseline can overwrite them. Splitter/merger jam detection compares actual cargo movement, while keeping native filtering and backpressure.

Robotic-arm operating status, claw loads and income/minute come from the host. Water-tap recovery, personal tool inventories, shared quests and purchases, host-side selling, mouse visuals and prior conveyor/lift corrections remain included. Stable machine hierarchies reuse cached part mappings; changed hierarchies rebuild them.

## Verification and limits

Validation combines isolated GDRE/Godot tests with actual Demo V62 headless instances using the native BeltRunCore extension. Separate host and guest save directories protect existing saves. Local multiplayer tests cover scanner inventory, competing and repeated purchases, personal tool transfers, vacuum/hopper quantities, production routes and the complete prestige save/reload. Packet loss and duplication are injected on loopback; Steam multiplayer is not started.

These results do **not** establish GPU frame rates, a two-PC Steam/WAN session, or freedom from every possible bug. Headless runs cannot measure rendered graphics performance. The supplied older game copy identifies as V33 and was not used as the V62 compatibility baseline. Host and single-player saves now include the vacuum fill and matching transfer reservation in the same snapshot as the world. Loading restores that snapshot once, including an uncommitted reservation or a transfer already received by a hopper. A save is deferred while shared floor cleanup is pending, and pause-menu exit waits for a successful save. Full guest-process-crash recovery is still incomplete: guest vacuum contents and unconfirmed local cleanup reports require an authoritative persistent inventory protocol. Unsaved progress after a host crash still rolls back to the last successful save.

Only the host saves the shared world. Tools remain personal. Machines simulate on the host, with guest visual replication. Keep both installations on the same release and back up a save before changing mod versions. Do not downgrade a save containing new hoppers without a compatible backup.

## Credits and source

Original multiplayer mod: [AleDev11](https://github.com/AleDev11/FindTheNeedle-Coop-Mod). Farmer model: Quaternius, CC0. GodotSteam: MIT. Steamworks SDK: Valve Corporation. The hopper mesh is original procedural geometry in this fork. Game binaries, decoded game sources, private saves and local test fixtures are not distributed in this repository.
