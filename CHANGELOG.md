# Changelog

## 0.19.6-xRangerDE.54

Reduce late bucket and pouring costs, lower precise needle-location pricing and smooth the sale-price curve while preserving purchased levels.

- Bucket upgrades cost 10,000 in total, pouring upgrades 12,000, and precise needle location 7,500.
- Sale ranks 5–8 now cost 250, 300, 350 and 365; all 20 ranks still cost 12,885 and retain the same effects.
- Credit only recorded overpayments. Existing .53 refunds are deducted, and repeat loading cannot pay them again. Existing ranks, saves, shared money and personal inventories are preserved.
- Include the existing multiplayer add-ons in the optional Multiplayer-Addons ZIP. All players must use this version.

Validated with 397 focused checks of the production GDScript in an isolated Godot test project, covering prices, old-save refund histories, repeated loads, serialized balances and host/guest guards. No game executable, Steam session or native multiplayer session was launched for this release.

## 0.19.6-xRangerDE.53

Rebalance expensive late upgrades, extend sale-price progression and credit recorded overpayments without resetting purchased ranks.

- Use fixed total budgets for 17 upgrade ladders, including 75,000 for vacuum capacity, 50,000 for suction, 120,000 for grinding, 80,000 for arm speed and 40,000 for splitter/merger speed. Remove the extra native late-rank surcharge from those ladders. Existing-rank prices never increase.
- Extend sale-price progression to 20 ranks, each adding five percentage points to the base price, up to twice the base value. Preserve the original first five ranks and their prices.
- On loading an older save, credit the recorded excess paid for affected ranks once. Only the host or single-player applies the credit; repeat loads and guest joins cannot duplicate it. Gifted ranks and purchases without a recorded paid amount are not assigned an estimated refund.
- Save the credit marker together with the balance and retain all purchased ranks and world progress. No separate migration of live save files is required during installation.

Validated with targeted native Demo V62 headless tests for prices, receipts, save/reload and simultaneous multiplayer purchases. Existing .52 fixes remain included. Steam/WAN reliability and rendered GPU performance are not newly validated by this release.

## 0.19.6-xRangerDE.52

Preserve loose hay when automatic cleanup is disabled and stabilize personal-tool pickup.

- Apply the host’s cleanup policy to loose-strand reclamation, draining and stranded-hay folding. Recover fallen strands instead of silently returning them to the pile. Explicit floor sweeping and enabled automatic cleanup remain available.
- Expand an exhausted straw pool in small batches while cleanup is disabled, preserving existing hay and allowing the new output to spawn.
- Retain dropped-tool materials through native removal to prevent a rendering-resource error during pickup.

Targeted native Demo V62 headless tests cover Q/drop/pickup with a host and two guests, repeated input, separate tool inventories, cleanup disabled/enabled, pool exhaustion and fallen hay. These checks do not establish complete crash recovery, Steam/WAN reliability or rendered GPU performance.

## 0.19.6-xRangerDE.51

Keep temporarily held straw available while the vacuum finishes placing it on the floor.

- Respect the existing, finite native hold timer before classifying loose straw as lost. Previously, a brief dip below the floor could return individual strands to the pile before they were collected into the poured heap.
- Preserve normal lost-straw handling after the hold expires or is released, without extending timers or changing collision masks.

Validated with native Demo V62 headless pouring on raycast-checked floor locations and targeted hold, expiry and transport regressions. The broader authoritative guest-inventory work and near-empty-pile extraction audit remain in progress; this release does not claim complete crash recovery, Steam/WAN validation or rendered GPU performance.

## 0.19.6-xRangerDE.50

Preserve host and single-player vacuum contents in world saves, and prevent partial saves during shared cleanup.

- Store vacuum fill and the matching transfer reservation in the same native save snapshot as world cargo and receipts. Restore only the matching slot, world and save generation.
- Resolve restored reservations once, including transfers already received by a hopper, without duplicating the saved hay.
- Defer a save while shared cleanup is pending. Save once after a complete result, and retain the previous file after an incomplete result.
- Require a successful host/local save before leaving through the pause menu. Guest exit remains independent of host saving.
- Preserve incompatible recovery data rather than silently overwriting it. Prestige starts without the previous world’s vacuum checkpoint.

Validation includes native V62 headless process termination/restart, save rollback and targeted transfer, cleanup and multiplayer regressions. Guest-process-crash recovery is not complete: guest vacuum inventory and unconfirmed cleanup data still need a persistent authoritative inventory protocol. Steam/WAN and rendered GPU performance remain unverified.

## 0.19.6-xRangerDE.49

Correct multiplayer lifecycle and delivery-status handling, with native V62 headless validation.

- Replicate delivery arrival and departure countdowns so guests see the host status.
- Avoid repeated missing-metadata errors when aiming at ordinary objects or handling a stale lift rider.
- Complete shared cleanup safely when leaving a session, preserving unconfirmed guest reports and releasing the local action lock.
- Send lobby updates only to connected peers and coalesce disconnect notifications.
- Guard shutdown callbacks when the scene tree is already detached.

Validation uses actual Demo V62 host/two-guest instances, native BeltRunCore, isolated saves and injected loopback packet loss/duplication, together with targeted regression tests. Steam/WAN multiplayer and rendered GPU performance remain unverified. Pending vacuum and cleanup transfers are not guaranteed durable across a complete process crash.

## 0.19.6-xRangerDE.48

Add prestige map changes, safer scanner dismantling and shared hay cleanup for Demo V62.

- Allow scanners containing needles to be dismantled. Release each unclaimed needle onto the floor once, while preserving active player ownership.
- Expand lift and hay-stair speed to ten ranks, up to 400%. Keep existing purchased ranks. Reduce all yard-vacuum upgrade prices by 20%, with an 80,000 maximum per rank.
- Replace the hopper with an original industrial steel model, a matching catalog image and a readable HUD status card.
- Show remaining buried needles on the delivery board and in Next Load details.
- Add Prestige through Next Load. After an empty haystack and six collected needle types, the host or single-player can preview the sale and choose Standard, Large, Huge or Mountain. Buildings and saleable goods are converted to money; tools, unlocks and purchased upgrades remain. Each new cycle requires its new needle types again. Save backups are created before the change.
- Route shared floor cleanup and normal new-load orders through host validation. Deduplicate cleanup acknowledgements and retain a visible waiting state when a connected peer has not confirmed.
- Reject delayed world messages from an earlier map generation instead of applying them to the new map.

Validation uses standalone GDRE/Godot: native pile-generation routines, isolated inventory and save-failure tests, UI/layout checks, and local host/two-guest ENet tests including delayed and repeated packets. The game and Steam were not started. Full V62 gameplay, current GPU performance and two-PC Steam/WAN testing are not part of this verification. Complete process-crash durability of pending vacuum/cleanup transfers remains unverified.

All players must install this version together. Existing saves and bought upgrades are retained; Prestige changes a save only after its explicit in-game confirmation.

## 0.19.6-xRangerDE.47

Fix the overhead-camera key conflict and make the loading hopper usable in single-player.

- Give unmodified F7 priority over V62's native bug-report action when selecting the building camera. Ctrl+F7 retains the debug report; unrelated customized F7 bindings remain protected. Select a part with B before enabling the camera.
- Keep arrow-key panning separate from building-height changes. PageUp/PageDown retain height control.
- Add an original model-based hopper image to both catalog layouts and the hotbar, with a cached transparent texture.
- Enable hopper construction, M unloading, buffered belt output, dismantling and persistence in single-player. Local transactions keep the same cost, capacity and placement checks, without opening a lobby. Shared network behavior remains host-authoritative.
- Preserve hopper contents when opening or leaving a hosted lobby. Cancel queued local actions safely if the session changes before execution.

Validation: 41 hotkey checks use V62's actual default bindings and native debug-input method, reproducing the old failure first. 1,023 single-player checks and 13 icon/UI checks passed, along with the existing camera, hopper and transfer suites. A local host and two guests passed 319 checks with packet loss/duplication and conserved 33,550 strands. All 77 product scripts passed offline bytecode compilation. Tests used standalone GDRE/Godot with explicit native dependency doubles; the game and Steam were not started. Full V62 gameplay, GPU performance and two-PC Steam/WAN testing remain outside this verification.

Both players need this release when playing together. Existing saves and previously purchased upgrades are retained. The previous caveat about pending vacuum transfers across a complete process crash still applies.

## 0.19.6-xRangerDE.46

Repair needle ownership and add buffered hay unloading, transport upgrades and an overhead building mode for Demo V62.

- Route loose needle pickup, scanner withdrawals and cabinet deposits through host-owned identities. Normalize repeated scanner references, reject stale recreation requests and preserve separate needles of the same type. Existing cabinet stock is not removed based on uncertain provenance.
- Recover raw physical hay behind the press and on directly connected wrapper decks; retain quantities and needle state. Apply early guest pelletizer edits and repair splitter/merger jam detection without bypassing filters or blocked outputs.
- Add an original loading hopper: 2,500 to build, 50,000 strands of storage, M to unload the vacuum at a free level belt input. Output waits for capacity. Direct belt portions can be upgraded from 100 to 1,000 for 25,000 total.
- Extend arm speed to rank 20; add four lift and stairs speed ranks and ten splitter/merger speed ranks. The six new arm ranks and ten distributor ranks each cost 100,000 total.
- Add F7 overhead building: pan with WASD/arrows, zoom with the wheel, and return with F7/Escape. Host validation reconstructs the cursor ray and checks the 24 m building area and prices. Existing F7 bindings remain available.
- Add a shared Double Jump unlock for 2,500 in Fitness after Spring Heels. Release and press jump again in mid-air; land to restore the extra jump. Menus, ladders and equipped jetpack controls remain protected.
- Show remaining buried needles in Next Load details, cache unchanged machine part mappings, and initialize transactions correctly when hosting from an already loaded world or reopening a lobby.

Both players must use this release. Existing V62 saves can be loaded; keep a backup before upgrading. Hopper operation requires an active lobby. The Multiplayer Addons ZIP includes the existing optional add-ons; the base ZIP does not change renderer settings.

Validation: all 74 product scripts passed the offline bytecode compilation check. Targeted standalone GDRE/Godot tests covered native method contracts, camera geometry and actual physics rays, concurrent purchases, needle lifecycle, blocked output, and local host/two-guest packet loss and duplication. The new camera tests passed 286 controller/geometry checks and 30 integrated host/build checks; Double Jump passed 57 checks. Test doubles explicitly replace unavailable full-game dependencies.

The game and Steam were not started for this revision. Full V62 gameplay, two-PC Steam/WAN, new GPU/FPS measurements and complete process-crash durability of pending vacuum transfers are not verified. These are targeted fixes and features, not a guarantee that every possible bug is eliminated.

## 0.19.6-xRangerDE.45

Synchronize robotic-arm operating status from the host.

- Guests receive the host's alert, waiting reason, clear state, panel messages, power state, throughput and nearby-belt count. Local guest power calculations cannot replace an accepted host state.
- Show a pending status before the first snapshot rather than a guessed local power fault. Real host power failures and blocked belts remain visible.
- Preserve arm reach, collection behavior, material quantities and existing saves. No guest production is enabled. Both players need the same version.

Validation: 174 isolated checks passed using native status functions with explicit dependency fixtures. A separate local host and two guest processes received 25 state updates each with zero diagnostic mismatches, including the final clear state. Tests used standalone GDRE/Godot; the full game and Steam/WAN were not started or tested.

## 0.19.6-xRangerDE.44

Fix vacuum upgrade cards remaining capped at 27 capacity and 6 suction ranks.

- Initialize from the native three-rank catalog and retry after in-place catalog rebuilds. Support either load order with the existing Tool Upgrades add-on.
- Show all 41 capacity ranks up to 50,000 strands and 20 suction ranks up to 1,000 strands per second. Keep purchased ranks and saved contents unchanged.
- Disable the native late-rank surcharge for these two cards so the actual purchase price stays at or below 100,000. Preserve the three native base prices and any existing first six base prices.
- Let the native catalog append units once instead of duplicating them in upgrade values.

Validation: 271 checks using the decoded native catalog shape and cost/display functions, 315 existing capacity/save/purchase checks, and 6 checks using the actual optional add-on in both load orders passed. Dependencies were isolated in a standalone GDRE/Godot project; the full game and Steam/WAN were not started or tested.

## 0.19.6-xRangerDE.43

Make scanner drawer withdrawals host-authoritative.

- Guests request a specific needle and wait for the host grant before creating a held needle. Request deduplication and ownership reservations prevent concurrent or repeated withdrawals.
- Replicate drawer contents with reliable epoch- and sequence-checked snapshots instead of generic machine fields. Refresh open drawer cards after changes and route bulk dispensing through the host.
- Return unacknowledged grants after hand failure or disconnect; retain them in scanner save data while pending.

Validation: 23 isolated contract checks and 15 checks across a standalone test host and two guests passed with delayed, dropped and duplicated packets. Native scanner, hand and world dependencies were explicit test doubles. Full V62 gameplay and Steam/WAN validation remain outstanding; the game was not launched.

## 0.19.6-xRangerDE.42

Extend vacuum capacity and suction upgrades with bounded prices.

- Preserve capacity effects through rank 27 and add 14 ranks of 2,500 strands, reaching 50,000 at rank 41. Suction keeps ranks 0–6 and rises through rank 20 to 1,000 strands per second.
- Keep the first six native prices and scale later vacuum prices smoothly to a maximum of 100,000 per rank. Previously purchased ranks remain unchanged; no refunds or free ranks are applied.
- Install capacity rules before world loading so saved vacuum contents are not truncated to the old capacity. Extend the existing native upgrade cards without requiring the optional tool-upgrade add-on. Purchases continue through the existing host-authoritative handler.

Validation: 315 isolated checks passed, covering legacy effects, both full price curves, card rebuilding, German/English labels, the actual tech overrides and concurrent requests through the existing host purchase handler. Native dependencies were represented by explicit test doubles; full V62 gameplay and Steam/WAN were not run.

## 0.19.6-xRangerDE.41

Show optional Autonomous Mice to guests and increase vacuum M-dump batches.

- Replicate the host mouse poses, model transforms, animation and visibility. Guest replicas are cosmetic and do not simulate needle pickup, physics or persistence. Full snapshots recover late joins and removed replicas; epoch and sequence checks reject stale state. Both sides need the mouse model from the add-on package.
- Empty up to 2,000 vacuum strands per 0.1-second step as native tufts, keeping the 100-strand tuft limit. Container capacity and pending cargo limit output; conveyors wait for a previous tuft to land. Failed creation does not debit the vacuum, and ordinary manual pouring remains unchanged.

Validation: 85 isolated mouse-model checks, 58 checks across a test host and two guests with packet loss, and 78 vacuum contract checks passed. These ran in a standalone GDRE/Godot test environment, not the game. Full V62 gameplay, physical landing and Steam/WAN validation for these changes remain outstanding.

## 0.19.6-xRangerDE.40

Restore valid pulper water connections and distinguish splitter operation from building changes.

- Commit a pending pulper tap only when a built water-pipe endpoint reaches it. Recover missing taps on the native drum connection surface when loading a host world or rebuilding water connections. No pipe relocation, extra purchase or save-format change is required.
- Compare all available splitter routes in the building topology digest instead of its transient active outlet. Missing routes, invalid destinations and broken fixed connections remain detectable.

Validation: 61 native water-connection checks and 393 checks with a local host plus two guests passed. The tests cover six saved splitters, alternating routes, real missing connections, water-tap recovery, unconnected previews and packet delay/loss. All 50 production scripts compile in V62. No new Steam/WAN test was performed.

## 0.19.6-xRangerDE.39

Prevent raw hay from bypassing the compressor after loading an existing yard.

- Restore raw belt records beyond the intake stop to the intake queue without changing their quantity, sequence or needle state.
- Keep raw hay behind an independent compressor outlet gate, including large transport steps and refreshed belt connections. Native end-of-belt restrictions remain in effect.
- Reclaim raw records and unheld physical hay stranded on a direct conveyor route from a compressor to a wrapper when the compressor can accept them. Finished bales, held tools and unrelated routes are not consumed.

Validation: 50 production scripts compile in V62. 840 targeted native-runtime checks passed, covering full buffers, repeated recovery, four rotations and 200 queued loads. A separate 45-second simulation of the reported saved yard produced 27 bales with no raw records on the four press output belts; its pre-existing stranded bundle was also recovered. These are local headless tests, not a new Steam/WAN validation.

## 0.19.6-xRangerDE.38

Show robotic-arm loads and income per minute to guests.

- Replicate transient claw-straw geometry, colors and poses separately from static machine parts. The guest creates a cosmetic mesh without collectible bodies or production logic.
- Split geometry into bounded reliable chunks, order load generations and poses independently, reject invalid data and recover the current load on full snapshots. Late packets cannot restore released cargo.
- Use the host’s current rolling sales rate for the native guest income-per-minute display. Balance synchronization alone did not populate the guest’s local sales history. The rate returns to zero when sales expire and never credits money.


Validation: 50 production scripts compile in V62. A local host and two guests passed 69 checks with delayed, duplicated and dropped packets. The test checks exact mesh data, movement, release, full-snapshot recovery, invalid data, matching income rates, expiry and unchanged balances.

## 0.19.6-xRangerDE.37

Preserve robotic-arm loads during synchronization and route lift tufts through cargo records.

- Use read-only building snapshots for synchronization, topology checks and transaction targets. Native arm serialization otherwise refunds and clears the virtual load, leaving an empty animated grab. Actual save-time crediting is preserved.
- Let the host take eligible, settled guest-owned props when selected by a robotic arm; held, moving and claimed items remain excluded.
- Transport physical hay tufts through the lift’s existing record path and convert already carried tufts, retaining their amount and needle state under output backpressure.

- Attach the native compact-row metadata label to its row while keeping it hidden. Previously these orphan labels survived world teardown.
- Install the compatibility hook before the native technology panel builds its controls, preserving its initialized properties and existing behavior.
- Keep visible row geometry, titles, costs and host-checked purchase behavior unchanged. Existing saves remain compatible; all players need the same mod version.

## 0.19.6-xRangerDE.36

Serialize guest world loading and stop synchronization before world teardown.

- Stop the old synchronization subtree before releasing it. Machine updates and rescans reject missing or replaced world references, preventing the reproduced native `get_script()` null-receiver crash.
- Queue the newest complete world transfer while a native world is still loading. Never start overlapping native loads or acknowledge an obsolete world generation.
- Keep temporary-save and profile protection active until an abandoned guest world is removed, including disconnects, host menu transitions and failed temporary-save writes.
- Resume a requested session switch after the previous guest world has been removed.
- Preserve existing save formats, personal tools and host-checked transactions. Every player needs this version.

Validation: all 45 multiplayer scripts compile in the native V62 engine. Five three-process local suites pass 1,273 checks (124 repeated world loading, 145 lifecycle/abort, 216 purchases, 607 quest synchronization and 181 rebuilt production-chain checks) with packet loss, duplication and delay. A targeted teardown reproduction passes 8 checks after previously crashing at the same native fault address as a local historical dump. The original historical GDScript call site is still unknown.

A rendered offscreen test runs eight native press → wrapper → scanner → curve → sale chains at 2560×1440 using D3D12 Forward+ on an RTX 5090. All 12,000 input strands become 200 wrapped bales and are sold with exact payout; 1,746 checks pass. Three 20-second distant-overview windows average 228.2, 259.2 and 267.8 FPS, with 99th-percentile frame times of 7.96, 6.60 and 6.91 ms. This is an isolated scene with no full yard, player input or network load, not a full-game FPS guarantee.

Two-PC Steam/WAN testing and reproduction of every historical save layout remain open. Native reload diagnostics and resource warnings at process shutdown remain; these results do not prove complete bug freedom.

## 0.19.6-xRangerDE.35

Make technology replication host-authoritative and validate loose-straw ownership.

- Reject guest-published technology ranks and remove the legacy refund path that could credit money without a purchase.
- Apply valid host rank reductions as well as upgrades, keeping the technology tree consistent.
- Accept loose-straw movement and deletion only from the recorded owner.
- Confirm straw positions with periodic reliable snapshots and reject older movement sequences, so missed final motion can recover automatically.
- Reject malformed straw additions, invalid transforms or rotations, and oversized update batches.
- Retain the host-checked purchase flow and existing save format. Every player needs the same mod version.

Validation: 45 GDScripts compile in the V62 engine. Three isolated local processes pass 69 ownership/technology/reliable-position checks, 216 purchase checks, 607 quest-synchronization checks and 178 floor-hay checks, with injected packet loss, duplication and latency.

The existing three-process press → wrapper → scanner → curve → selling-stand regression also passes all 181 checks, including rebuilds and resynchronization.

The historical guest crash without a matching trace, two-PC Steam/WAN play and full visible gameplay frame times remain unverified. Native dummy-renderer diagnostics during reload/tool handling and resource warnings at shutdown remain; these controlled tests do not establish complete bug freedom.

## 0.19.6-xRangerDE.34

Synchronize drone collection and status through the host.

- Let a host-controlled drone collect settled hay placed by a guest after ownership, movement and carry-state validation.
- Keep held tools, moving props, conveyor riders and pending player claims out of the automatic collection path.
- Replicate drone phase, route/wait status, trip count, delivered strands and drop-full state to guests with strict value validation.
- Preserve cargo through resync and drone demolition; existing saves and third-party add-ons remain unchanged.

Validation: 45 current GDScripts compile in the V62 engine. Three isolated local game processes pass 104 drone checks with packet loss and duplication, including guest hay collection, carrying, resync, exact delivery, a second guest load and demolition with 77 strands preserved. The existing three-process press → wrapper → scanner → curve → selling-stand regression remains 181 checks with 0 failures.

The historical crash without a matching guest trace and two-PC Steam/WAN play remain unverified. Native shutdown resource warnings remain; this release does not claim complete bug freedom.

## 0.19.6-xRangerDE.33

Route T-junction changes through the host and restore their internal conveyor connections.

- Execute role selection, automatic/manual mode and splitter/joiner conversions through the existing validated, deduplicated host transaction queue.
- Rebuild affected internal connections after applying authoritative settings, including scoped native rebuilds.
- Keep the panel pending until the confirmed configuration revision arrives. Preserve revisions through native automatic type changes, and release pending controls when leaving the lobby.
- Treat legacy role fields as context only. Reject stale priority or pin packets instead of letting them restore an older role layout.
- Preserve existing saves and personal tools. Every player needs this version; third-party add-ons remain outside the public ZIP.

Native transport testing covers 35 splitter/joiner cases, three rotations, blocked outputs and resumption, priority routing and smart filters. All 84,000 input strands were collected. Physical conveyor riders are included in the material and ownership checks.

Three actual local game processes also passed 181 production-chain checks. With packet loss, duplication and latency, both scanner tiers and 90/135-degree curves delivered all 720 input strands through pressing, wrapping, scanning and sale, including junction rebuilds and guest resynchronization. No raw-hay leak or duplicate guest sale occurred in those layouts.

Three local game processes passed 215 additional T-configuration checks covering actual panel signals, simultaneous changes, duplicate requests, delayed priority packets and lobby cleanup. Native lifecycle checks passed 19 assertions, including configuration revisions, offline controls and conservation of 46 strands across type swaps. The lifecycle fixture freezes materialized bodies and is not a fall or transport test.

The original historical layouts, the guest crash without a trace, and two-PC Steam/WAN play remain unverified. Native shutdown resource warnings remain. This maintenance preview does not guarantee complete bug freedom.

## 0.19.6-xRangerDE.32

Ignore expired machine and conveyor callbacks after objects are removed or replaced.

- Resolve delayed press/wrapper setup through weak references before accessing the machine. Valid newly placed machines still receive their production guards.
- Retain the original network item identity during deferred belt handoff. Discard callbacks for deleted, detached or replaced objects.
- Clear stale boarding markers when the item no longer rides the belt, so a later removal cannot be mistaken for a conveyor transfer.
- Keep existing save formats, personal tools and optional add-on support. Every player needs the same version.

Native lifecycle tests reproduce 40 invalid-object callback errors in the previous implementation and none with the fix. Thirteen checks cover valid setup, preserved stock, previews, shutdown, removed riders and changed item identities.

Three actual local game processes passed 181 checks with 30,752 proxied packets, including 601 dropped and 602 duplicated packets. Both scanner tiers, 90-degree and 135-degree turns, physical hay from both guests, live junction rebuilds and guest resynchronization preserved all 720 input strands through pressing, wrapping, scanning and sale. No raw-hay leak or duplicate guest sale occurred in these fixtures. All 43 multiplayer scripts compile in the installed V62 engine.

The historical guest crash without a trace and two-PC Steam/WAN play remain unverified. Native shutdown resource warnings remain. This maintenance preview does not guarantee complete bug freedom.

## 0.19.6-xRangerDE.31

Prevent guests from selling mirrored hay twice and restore host collection of guest-delivered items at the selling stand.

- Run selling-stand cargo consumption and payment only on the host, including during guest world loading. Keep the native stand presentation active.
- Transfer released guest-owned items inside the stand intake to the host for native collection. Held items remain with their player.
- Replicate hay-sale scale, sack and till effects as sequenced cosmetic events. Reject stale-world or duplicate events without adding money, consuming cargo or creating extra collectible coins.
- Preserve existing saves, personal tools and optional add-on support. Everyone needs the same version; third-party add-ons are not included in the public ZIP.

Validation: all 43 scripts compile with V62. Native before/after and visual tests pass 50 checks. Eighteen press/wrapper/scanner/selling-stand routes pass 3,525 checks across both curve directions at 45°, 90° and 135°, three rotations and both scanner tiers. All 432 wrapped bales, representing 25,920 strands, reach the real sale collector with the expected payout after five simulated minutes of blocked output per case. A final 135° run with the cosmetic channel enabled passes another 194 checks.

Three real local game processes pass 84 network checks with injected loss, duplication and delay (6,859 packets, 134 dropped and 127 duplicated). Guest delivery, mirrored cargo, exact shared balances, removal on every peer and hay-sale visual events are covered; all three processes exit successfully.

The original historical layouts, the reported guest crash without a trace, and two-PC Steam/WAN play remain unverified. Native shutdown resource warnings remain. The new visual channel covers hay sales; tool-sale and needle-scrap receipts are not yet mirrored. This is a maintenance preview, not a guarantee of complete bug freedom.

## 0.19.6-xRangerDE.30

Prevent shop purchases from creating overlapping physical objects.

- Check the purchased item's native solid collision shapes against nearby obstacles and props. Try bounded nearby positions when the original drop point is occupied.
- Reserve accepted positions for purchases in the same physics frame. Publish item-added and changed signals only after successful placement.
- Remove unplaced provisional objects and refund their full price. Keep personal-tool inventory purchases and save formats unchanged.
- Retain the V62 compilation, menu, conveyor and production fixes from earlier maintenance versions.

Validation: all 42 scripts compile; 23 native shop-placement checks and 216 transaction checks across three local processes pass. Network tests include packet loss, duplicates, concurrent purchases, insufficient space and world reloads. The native contact-limit warning was reproduced without the mod using 63 overlapping buckets; it does not occur in the corrected purchase run. This does not remove the engine's finite physics limits.

Additional native transport validation passes 1,860 assertions across eight full press/wrapper/scanner chains, delivering 192 wrapped bales and all 24 injected needles. Physical input is admitted only when the inlet has space. A separate overfill case confirms that the native game deliberately ejects a newly dropped tuft from an occupied inlet; this revision does not change that behavior. Lift/stairs validation passes 281 single-body checks, 76 mixed-load checks and 5,780 material-ledger checks, including ten-section lifts, blocked outputs and resumption.

The exact historical save layouts, the reported guest crash without a trace, and two-PC Steam/WAN play remain unverified. Native shutdown resource warnings remain. This is a maintenance preview, not a guarantee of complete bug freedom.

## 0.19.6-xRangerDE.29

Fix V62 script compilation and restore the multiplayer menu after initial language selection.

- Correct three Variant-related boolean declarations and use PackedInt32Array-compatible rollback for press and wrapper needles. The current V62 engine now compiles all 42 multiplayer scripts.
- Preload the full shipped script set so startup validation covers previously omitted modules.
- Retry menu integration when the native menu becomes available after language selection, without repeatedly reconnecting an existing button.
- Avoid accessing an already detached scene tree during conveyor and machine shutdown. A native before/after test removes both mod-generated null-tree errors.
- Retain existing save formats and personal tools. Every player needs the same version. Third-party add-ons remain separate from the public ZIP.

Validation includes 36 offline regression suites, 1,065 native press/wrapper release assertions, 509 native transport and intake assertions, and a real rendered menu check. Isolated physical curve tests delivered all 20,064 strands in 24 objects across 45°, 90° and 135° turns. The intake checks cover raw cargo records and physical bodies after rebuilding the machines. These are controlled fixtures, not every historical save layout.

Three real local game processes passed 72 personal-tool checks, 216 transaction checks and 607 quest checks covering all 46 quest steps. Their loopback links had 2% configured packet loss, 2% packet duplication and injected delay. Quest conditions were driven by controlled test actions rather than a full manual playthrough.

Rendered benchmark validation passed 81 checks with 24, 240 and 1,200 cargo records, preserving counts and quantities. The detailed-hay fix costs additional GPU work; this controlled offscreen test is not a gameplay-FPS guarantee.

The dense simultaneous-purchase fixture also reached the native physics contact limit. This revision does not claim to remove that overload limit.

Some engine shutdown resource warnings were reproduced in an unmodified native world and remain outside this fix.

The historical guest crash without a trace and two-PC Steam/WAN play remain unverified. This maintenance preview does not guarantee complete bug freedom.

## 0.19.6-xRangerDE.28

Protect physical hay cargo while it is waiting inside a hay lift or hay stairs.

- Keep owned cargo out of the loose-straw recycling pool, including when an output stays full longer than the native hold timer.
- Exclude carried hay tufts from automatic prop cleanup. Protection requires a live carrier and a matching cargo entry; stale ownership markers do not keep abandoned items forever.
- Restore original hold metadata after each recycling operation and preserve the live body pool when the multiplayer patch is installed or removed.
- Keep existing save formats and optional add-on support. All players must use this version; third-party add-ons are not included in the public ZIP.

Validation: 36 offline regression suites passed. New tests include 3,000 randomized recycling scenarios with 62,701 bodies and 1,000 backpressure scenarios with 9,974 cargo records. The original recycling bug is reproduced by executing translated native methods. These tests use explicit engine and pool adapters, not a running game. No game, Godot or GDRE runtime was started.

Rendered transport physics, GPU/FPS performance, the historical guest crash without a trace and two-PC Steam/WAN play remain unverified. This maintenance preview does not guarantee complete bug freedom.

## 0.19.6-xRangerDE.27

Synchronize moving cargo on hay stairs and remove stale lift cargo after joining a host.

- Remove native saved-game cargo copies on guests before showing authoritative lift and stair cargo. Keep physical carried objects intact and do not spawn fallback items during this cleanup.
- Include hay stairs in the existing cargo snapshot channel and exclude their native cargo meshes from generic machine animation.
- Keep the previous snapshot when a carrier is missing or ambiguous, retry after the building is available, and report repeated mismatches through automatic diagnostics.
- Ignore deferred guest cleanup after disconnecting or becoming the host. Existing save data and host cargo are preserved.

All players must use this version. Optional third-party add-ons remain outside the public ZIP.

Validation: 34 accepted offline regression suites. The new carrier suite performs 40,080 checks across 2,000 mixed lift/stair scenarios with 32,044 mirrored cargo records, covering saved-game duplicates, late building arrival, ambiguous identities, empty snapshots, physical objects and session changes. Tests execute translated production methods with explicit engine and rendering adapters. No game, Godot or GDRE runtime was started.

Rendered transport physics, GPU/FPS performance, the guest crash without a trace, and two-PC Steam/WAN play still require runtime verification. This maintenance preview is not a guarantee of complete bug freedom.

## 0.19.6-xRangerDE.26

Keep cargo on its original conveyor when a T-splitter lane transfer is rejected.

- Accept the record on the receiving lane before removing it from the source. A rejected transfer no longer depends on reboarding the source or spawning a physical fallback item.
- Lock the cargo identity at both ends during transfer, protecting against recursive transfer and materialization callbacks. Resolve final removal by identity after queue changes.
- Retain existing saves and optional add-on compatibility. All players must use this version; third-party add-ons remain outside the public ZIP.

Validation: 33 offline regression suites passed. The new transfer suite runs 530,107 checks across 144,000 transfer attempts and 2,000 stress cycles, including rejected admission, callback reentry, shifted queue indices and preservation of amounts and identities. Tests execute translated production methods with explicit engine/native adapters.

REA inspection confirms that the native tick advances directly imported BACK records and promotes eligible records to its free-moving group. No additional movement patch was justified by that branch. The game, Godot and GDRE were not started.

Rendered transport physics, GPU/FPS behavior, the guest crash without a trace, and two-PC Steam/WAN play remain unverified. This maintenance preview does not guarantee complete bug freedom.

## 0.19.6-xRangerDE.25

Keep conveyor cargo intact when creating a physical item fails.

- Create the physical item before removing its conveyor record. Failed or already-discarded items leave the original record untouched.
- Guard recursive requests for the same record and resolve the final removal by its identity if callbacks changed queue positions. Remove a provisional item if a callback has already consumed the original record.
- Preserve complete cargo state in the corrected offline native adapter and recheck 600,000 snapshot rows, including custom state.

Correction to the earlier native-core analysis: the insert function copies its state argument through Godot's variant_new_copy API. The decompiler omitted that argument from its displayed signature. The claim that the core discards this state was incorrect; native host record IDs remain the pickup identity.

All players must use this version. Existing saves remain compatible. Optional third-party add-ons are not included in the public ZIP.

Validation: 32 offline regression suites passed. The new item-creation suite includes 50,073 checks and 2,000 stress cycles, covering failed creation, failed native rollback, queue changes during callbacks and recursive requests. Tests run translated production methods with explicit engine/native/transport adapters. REA and assembly were used to inspect the native state-copy path; the game, Godot and GDRE were not started.

Actual rendered transport physics, GPU/FPS behavior, the guest crash without a trace, and two-PC Steam/WAN play still need runtime validation. This maintenance preview is not a guarantee of complete bug freedom.

## 0.19.6-xRangerDE.24

Preserve unfinished press and wrapper batches when saving or creating a multiplayer world snapshot.

- Return an unreleased press batch to the serialized stock without changing the running machine.
- Put an unreleased wrapper bale at the front of the serialized queue with its original amount and needle. Avoid recording the same needle as an orphan as well.
- Leave released batches out of the machine's saved inventory so loading cannot duplicate an existing output product.
- Keep the native save format and existing save compatibility; a restored unfinished batch restarts its production cycle.

All players must use this version. Optional third-party add-ons remain separate from the public package.

Validation: 31 offline regression suites passed. The new production persistence suite runs 92,002 checks, including 8,000 randomized save/load cases and 10,000 blocked-output cycles. It reproduces the previous loss using the decoded native serializers and exercises the actual new overrides via a Python AST adapter. No game, Godot or GDRE runtime was started.

The rendered scanner/curve/sale transitions, exact reported press incident, GPU/FPS behavior, guest crash without a trace, and two-PC Steam/WAN play still need runtime validation. This maintenance preview does not establish complete bug freedom.

## 0.19.6-xRangerDE.23

Preserve authoritative conveyor cargo on guests and prevent local materialization at machine outlets.

- Match cargo snapshots to the owning building and complete conveyor curve, rather than a nearby pair of endpoints. Keep the previous snapshot when a route is missing or ambiguous, and retry after rebuilding.
- Import confirmed cargo without running the normal new-item admission test. Preserve product kind, amount, needle, spacing, lateral position, height, speed and host record identity; update native draw events and clocks.
- Prevent active guests from materializing machine-belt records into local physical duplicates. Host and single-player behavior remains native.
- Use native host record IDs for guest belt pickup. Pickup uses the native record identity independently of custom state.
- Invalidate queued cargo and pickup identities when a building update starts.

All players must use this version. Existing saves are retained. Optional third-party add-ons remain separate from this public package.

Validation: 30 accepted offline suites, including 600,000 cargo rows across 30 randomized bulk cycles, 1,203,145 snapshot assertions and 784 materialization/pickup checks. REA/Ghidra inspected the installed native belt core. Tests use translated production methods with explicit engine/native/transport adapters; no game, Godot or GDRE runtime was started.

Still unverified: rendered conveyor and machine physics, the exact reported scanner/press incident, GPU/FPS behavior, the guest crash without a trace, and two-PC Steam/WAN play. This maintenance preview is not a guarantee of complete bug freedom.

## 0.19.6-xRangerDE.22

Synchronize power-line editing and power groups through authoritative host commands.

- Route wire connections, cuts, group names, priorities, membership and group switches through the existing sequenced host queue. Duplicate requests do not repeat native mutations.
- Reject conflicting stale actions and references to replaced buildings. Independent connection and group-field edits can proceed without a global revision conflict.
- Apply reliable power snapshots to existing objects, including empty link/cut lists and exact group assignments. Wait for building and grid updates before applying a complete snapshot.
- Keep wire-mode feedback pending until the host responds, preserve newly opened modes when old responses arrive, and prevent guest-only automatic rewiring after reach upgrades.
- Include persistent power-state mismatches in the local synchronization diagnostic. Native availability restrictions for power groups remain in effect.

All players must use this version. Existing saves are retained. Optional third-party add-ons remain separate from the public package.

Validation: 27 offline regression suites passed, including 10,310 power-core checks, 3,648 UI-bridge checks and 7,200 simulated queued host transactions. A snapshot with 2,000 poles and 2,000 machines produced one rebuild; repeating it produced no additional rebuild. Tests execute translated production methods with explicit native, engine and transport stubs. No game, Godot or GDRE runtime was started.

Still unverified: actual scanner/curve/sale physics and pipe flow, rendering performance, the reported guest crash without a trace, and two-PC Steam/WAN play. This maintenance preview does not establish complete bug freedom.

## 0.19.6-xRangerDE.21

Preserve Pulper pipe anchors across multiplayer build requests and synchronize confirmed pipe fittings.

- Keep the exact valid pending origin fitting while the host prepares the next water-pipe placement step. Mode changes, different anchors and cancellation still reset the preview.
- Send build cancellation through the same host queue, including cancellation while a placement is still in flight. Remove temporary fittings when a multiplayer build tool leaves the scene.
- Exclude pipe fittings and their children from generic machine animation.
- Replicate committed Pulper fittings from the host without replacing the machine or touching its material stock. Repeated snapshots preserve existing fitting objects and local pending previews.

All peers must install this version. Existing saves are retained; optional third-party add-ons remain separate.

Validation: 24 offline regression suites, including 6,141 targeted fitting/anchor checks and randomized add/remove sequences. Selected production methods run through Python adapters with explicit native and engine stubs. No game, Godot or GDRE runtime was started.

Still unverified: actual scanner/curve/sale physics, physical pipe flow, rendering performance, the reported guest crash without a trace, and two-PC Steam/WAN play. Mutable power-line and power-group editing still needs a separate authoritative command path. This maintenance preview is not a guarantee of complete bug freedom.

## 0.19.6-xRangerDE.20

Keep multiplayer routing settings consistent and prevent guest-only cargo spills during conveyor rebuilds.

- Do not materialize replicated belt records on guests when a native route rebuild clears the old path. Host and single-player spill behavior is retained.
- Apply T-junction geometry before dependent routing values. Send coupled settings together and defer conflicting stale confirmations as a group.
- Synchronize silo discharge/resume rates, pelletizer head direction, and T-joiner output/manual settings through their native setters.
- Preserve existing belt gates, switch boxes, and power-tag memberships during partial building restoration. Include water-tee and tilted pipe-junction geometry in building comparison.

All peers must install this version. Existing saves are retained; optional third-party add-ons remain separate.

Validation: 22 offline regression suites, including 5,400 native splitter setter permutations, 5,000 randomized settings roundtrips, and rebuild cases with up to 20,000 cargo records. REA/Ghidra inspected the current native belt core. Selected production/native methods run through Python adapters with explicit engine, geometry, and network stubs. No game or engine was started.

Remaining work includes mutable pulper taps and power-link/group editing, actual scanner/curve/sale physics, the guest crash without a crash trace, rendering performance, and two-PC Steam/WAN validation. This maintenance preview is not a guarantee that all bugs are resolved.

## v0.19.6-xRangerDE.19 (maintenance preview)

Keep the host's hay and bale visuals visible to guests while they travel inside a hay lift.

- Include native lift cargo in the same authoritative snapshot as conveyor records. Preserve product type, strand count and the host's position, rotation and compression.
- Create and reuse client stand-ins without running a second lift simulation or changing inventories. Remove completed, replaced and demolished lift visuals; retry unavailable visuals on a later snapshot.
- Keep lift cargo out of generic machine animation packets. Reject malformed lift data before applying either half of the transport snapshot; defer both halves together during rebuilding and loading.
- Use stable visual identities even when native lifted items have no conveyor sequence ID.

All peers must use this version. Existing saves are retained. Third-party add-ons remain separate.

Validation: 18 existing offline regression suites plus new lift snapshot/lifecycle tests, including 4,507 synthetic transits. The current native belt-core DLL was inspected with REA/Ghidra for quantity updates, spacing checks and handoff failure handling. Tests translate selected production methods with engine and rendering stubs. No game or engine was launched; native physics, actual rendered motion, FPS and two-PC Steam/WAN remain unverified. This is not a guarantee that every reported issue is resolved.

## v0.19.6-xRangerDE.18 (maintenance preview)

Improve transport isolation, production retries and the first multiplayer interaction.

- Keep belt decks, their collision subtrees and fixed belt-port markers out of machine animation packets, including stale cached updates.
- Check actual internal machine/lift paths and downstream links in building diagnostics.
- Synchronize lift travel direction and head rotation. Route lift reshaping through the host transaction queue; reject stale conflicting requests and retain native cargo-transfer and placement checks.
- Restore press/wrapper filters after a filter or deck is replaced. Hold raw tufts at the wrapper without capturing needle objects.
- Preserve a production batch and its needles when native prop creation fails. Confirm output through the native success signals before accepting completion; keep native behavior if that signal contract is unavailable.
- Wait for cooperatively prepared construction previews before executing a host-authorized building transaction. Handle timeout, disconnect and retries without a second charge.
- Restore player input once after joining, respecting window focus, loading, pause and open menus. Preserve capture state across nested multiplayer overlays.

Existing saves and personal inventories are retained. Every peer must use the same version.

Validation: offline GDScript grammar checks and source-translated regression tests with explicit engine stubs. The currently installed V62 scripts and scanner/wrapper/press model ports were inspected statically. The current lift method was exercised through 124,387 handoff attempts, including full outputs and retries, without losing or duplicating tested payloads. Duplicate and conflicting lift edits, all direction/rotation combinations, and invalid lifecycle states are covered. No game, Godot or GDRE runtime was launched. These tests do not verify current native physics, FPS, two-PC Steam/WAN play, or the exact reported scanner/lift alignment in gameplay. This remains a maintenance preview.

The optional private Production Speed add-on receives separate compatibility fixes for derived multiplayer scripts and typed cargo filters; automatic side-ejection is removed. Third-party add-ons are not included in this public ZIP.

## v0.19.6-xRangerDE.17 (maintenance preview)

Add an integrated M-key vacuum dump and preserve more machine connection data during replication.

- Automatically pour from the equipped vacuum with bounded output, cancellation and full-target backpressure. Use physical straw for container delivery, reserve in-flight capacity and avoid merging into another peer's heap. The standalone Drop All script is no longer needed.
- Include lift port reach, riser height, machine tier and conveyor seat markers in building comparison; retain seat markers when creating replicated straight belts.
- Install press/wrapper protection after native node setup and final placement, skip previews, and reject deferred installation after shutdown.
- Preserve existing save data. All peers need the same version.

Validation uses GDScript grammar checks and direct production-method translation with explicit native/engine stubs. It covers input, bounded output, conservation, full targets, ownership, connection keys and machine lifecycle, plus the existing offline transaction, drone, transport and diagnostic suites. No game, Godot or GDRE runtime was launched.

The specific V62 scanner/lift alignment and raw hay report are not reproduced in native gameplay. Native physics, two-PC Steam/WAN behavior and the previously reported guest crash remain unverified.


## v0.19.6-xRangerDE.16 (maintenance preview)

Shop retrieval, personal tools and quest action tracking now use confirmed host transactions more consistently.

- Route shop “Bring to me” through the host. Reuse existing objects, release their old belt attachment, and skip carried, machine-claimed, detached or deleted objects.
- Clear stale inventory deltas and outstanding tool action locks when the session changes. Record guest tool unlocks on the host at grant time.
- Credit confirmed drop and retrieval actions to their quest even when inventory changes occur between observation frames. Duplicate transaction replies do not repeat this credit.
- Reject technology purchases while the world is transitioning or the requesting player is still loading.
- Update installation note versions. Existing save data and renderer settings are unchanged; install the same version on all peers.

Validation: 796 offline assertions cover transaction retries, concurrent purchases, refunds, item pickup/sale races, retrieval ownership, session changes, upgrades and propagation of all 46 quest IDs. Existing drone, conveyor, snapshot and diagnostic regression suites also pass. All 34 mod scripts and the generated belt patch pass grammar checks. Selected production methods run through a Python AST adapter with engine and transport stubs; no game or engine was launched.

This is a maintenance preview. Native quest completion, real physics and graphics performance, two-PC Steam/WAN play and the reported guest crash are not confirmed by these offline tests. Guest crash logs are still needed to establish the crash cause.

## v0.19.6-xRangerDE.15 (maintenance preview)

- Apply host-confirmed drone work areas, drop points, modes and filters on guests without running local placement rejection or route planning. New commands are still validated by the host.
- Reject invalid drone fields and malformed or non-finite machine animation packets before applying them. Repeated packet problems feed the existing local diagnostics.
- Stop applying animation and effect updates to detached, queued-for-deletion or replaced machine parts. A cached shader no longer overwrites a material subsequently changed by the game.
- Preserve existing saves, personal tool inventories, machine buffers and renderer settings. Every peer must install the same version.

Validation: 493 new offline assertions plus the existing press/conveyor, snapshot and diagnostic regression suites. All 34 mod scripts and the generated belt patch passed grammar checks. Selected production GDScript methods were executed through a Python AST adapter with explicit engine stubs. No game, Godot or GDRE engine was started.

The reported guest crash is not confirmed fixed: only host logs are available, without the guest crash stack. Native physics, graphics performance, complete quest/purchase playthroughs and two-PC Steam/WAN testing remain outstanding. This is a maintenance preview, not a guarantee of crash-free gameplay.

## v0.19.6-xRangerDE.14 (maintenance preview)

- Hold physical raw hay at the press intake until the native consumer takes it, including tufts that are temporarily missing from collision queries.
- Accept and hold raw tuft records at the press. Hold unsupported tuft records at the wrapper rather than allowing them through.
- Retain an owned, live belt rider when a handoff to an existing connected belt fails, including near-view and shared-deck junctions. Full or incompatible destinations back up the line instead of dropping the rider. Open/unconnected ends retain native behavior.
- Postpone press/wrapper output when its prop manager is unavailable, keeping the batch pending.
- Apply reversible machine hooks to existing and newly built processors while preserving buffers, needles and cycle state.
- Validate 1,217 new offline assertions, existing snapshot/diagnostic regressions, and grammar for all mod scripts plus the generated belt patch. Engine APIs are stubbed in the offline adapter; no game or engine was launched. Actual trajectories, throughput and two-PC multiplayer still require runtime verification.

## v0.19.6-xRangerDE.13 (maintenance preview)

- Preserve native machine intake holds on shutdown; release only holds installed by the multiplayer mirror and leave subsequent native filter changes intact.
- Defer conveyor snapshots during loading and building reconstruction, retain the newest valid snapshot, and discard pending data when its world or session is gone.
- Validate the snapshot structure and finite transport values before replacing mirrored cargo. Reject truncated payloads without clearing existing cargo.
- Remove the speculative endpoint reversal introduced in .12; positional mirroring did not establish correct transport direction.
- Stop packaging a host-specific override.cfg, preserving each installation's renderer and other mod configuration.
- Validate script grammar and selected production methods via a local Python adapter with engine stubs. No game or engine was launched for this revision. Native machine processing, curve/selling physics, guest crashes and graphics performance still need runtime verification.

## v0.19.6-xRangerDE.12 (superseded preview)

- Removed the over-broad .11 selling-outlet rewrite, but introduced an experimental endpoint reversal and a renderer override.
- Correction: the previously reported 20,018 checks did not test native curves, capacity or machine processing. The isolated JavaScript model differed from the shipped GDScript and its reported count represented records rather than executed assertions. It does not establish that the reported transition or loose-hay issue was fixed.
- The endpoint workaround and packaged renderer override are removed in .13. No confirmed cause of the reported guest crash has been established.

## v0.19.6-xRangerDE.11 (withdrawn)

- Withdrawn because the selling-outlet rewrite could alter unrelated nearby belts. Its isolated model was insufficient evidence for a native transition fix.

## v0.19.6-xRangerDE.10 (maintenance preview)

- Add local automatic diagnostics for repeated conveyor cargo, prop, building, hay and machine-setting discrepancies.
- Detect stalled transaction, inventory and shared-state acknowledgements with per-request timers.
- Debounce transient mismatches, record recovery, rate-limit notifications and cap diagnostic log size with one previous log retained.
- Keep reports limited to categories, counts and relative timestamps; diagnostics do not write gameplay state or trigger purchases or world reloads.
- Validate syntax and isolated diagnostic logic without launching the game; new live multiplayer validation remains outstanding.

## v0.19.6-xRangerDE.9 (maintenance preview)

- Prevent native conveyor overflow cleanup from deleting cargo above the belt limit while the host has automatic cleanup disabled.
- Keep conveyor overflow cleanup authoritative on the host; clients retain cargo until the host updates it.
- Preserve native conveyor behavior, saved state and cleanup when enabled; restore the original scripts when world synchronization shuts down.

## v0.19.6-xRangerDE.8 (maintenance preview)

- Reliably confirm the final position of settled props, so a dropped movement packet does not leave hay above a wheelbarrow until the next periodic census.
- Reject older movement updates and updates from a previous ownership epoch; retain this protection across repeated owner confirmations and reset it when a player leaves.
- Preserve another player’s carried-item protection when a local player drops an item.
- Retain remote container comparison state across periodic censuses, preserving detection of host-side changes.
- Apply dependent splitter settings in the correct order so entry and lane updates do not silently reset the chosen priority.

## v0.19.6-xRangerDE.7 (maintenance preview)

- Keep detailed loose-hay geometry on conveyors at distance, preventing the visible thinning caused by native far-detail models.
- Preserve native batching, draw-distance culling, cargo quantities, collision and transport. Dense visible conveyor layouts can require more GPU work.
- Publish the maintenance fork with installation notes and explicit test limitations.

## v0.19.6-local.6 (maintenance fork)

- Corrected stale carried-state bookkeeping after a real Q drop, so released tools and wheelbarrows are no longer left marked as held.
- Added host authority promotion for host-side wheelbarrow/container mutations and baseline tracking for remote container states.
- Verified guest and host wheelbarrow fill/empty, carry handoff, conveyor pickup, splitter stress and full source regressions under packet loss, duplication and delay.

## v0.19.6-local.5 (maintenance fork)

* Replace permanent shared equipment with personal tool inventories. Native drop
  and throw actions remove the owner’s tool and produce one physical item.
* Resolve tool purchases and competing pickups on the host; retain separate
  inventories in the host save across resync and rejoining. Seed old shared
  equipment once per player when migrating an existing world.
* Avoid saving an equipped remote toy shovel as extra loot, and discard stale
  prop creation from a guest world while that guest is reloading.
* Match pickup range to native reach upgrades.
* Restrict native quest money and gift creation to the host directly, preventing
  guest reward reactivation when authoritative gift state replaces a snapshot.
* Keep loose floor hay when automatic cleanup is disabled, including the native
  tuft-count and prop-count overflow passes that previously bypassed that option.
* Use the host's cleanup setting and timer for every owner in a co-op session,
  including late joiners and live setting changes.
* Preserve each guest's local preferences and restore the native prop-manager
  script when multiplayer ends. Manual cleanup and explicit item consumption
  continue through the game's native logic.

## v0.19.6-local.4 (maintenance fork)

* Fix demolition and conveyor reversal immediately after loading an existing save,
  when no construction type is selected or a previously selected type is unavailable.
* Validate edits against their actual target and native demolition restrictions,
  independently of construction previews, unlocks and placement costs.
* Preserve unrelated in-progress construction previews and return edit-specific
  failure messages instead of reporting a failed purchase.
* Apply host-confirmed platform replacements on guests even while supported objects
  remain in place; keep occupancy checks on new demolition requests.
* Keep native save data and stored construction refunds compatible without migration.

## v0.19.6-local.3 (maintenance fork)

* Validate normal shop purchases, physical-item sales, construction, demolition
  and arm upgrades on the host before changing money or world objects.
* Recompute native building previews, collision checks, unlocks, gifts and prices
  on the host; reject prices above the initiating player's preview.
* Serialize transactions across physics frames and deduplicate request retries
  using session epochs, per-player sequences and cached receipts; keep purchase
  sequence numbers across full guest world reloads.
* Reject client-authored building replication and unpaid arm tier changes.
* Share gifts and purchase history, refund failed item creation, and prevent
  duplicate sales or repeated payment for shared tools and same-tier upgrades.
* Preserve the initiating player's native building tutorial counters and keep
  cancelled previews from being restored by a late confirmation.

## v0.19.6-local.2 (maintenance fork)

* Share collected tools across the co-op session and preserve them during resync.
* Confirm loose-item and tool pickup through the host; reject older ownership
  confirmations and prevent delayed updates from restoring deleted items.
* Reconcile F8 in place, preserving the guest world, held items and pending money.
* Validate upgrade purchases on the host and charge a concurrent same-rank purchase
  only once.
* Distribute movement and state updates fairly across large item populations.
* Repair locally missing items without treating them as globally deleted.
* Synchronize drone controls, work areas and drop points, plus robotic-arm pickup
  order, links and tier setters; protect edits from older host snapshots.
* Synchronize saved board pictures and erasure, with bounded chunk assembly and
  periodic refresh.
* Show a visual hay load on remote spades and pitchforks.
* Let guest-owned containers take host hay through confirmed ownership transfer.
* Restart state acknowledgements after a guest loads a new world and prevent the
  old world from reporting readiness during the transition.
* Correct lamp switch reads and clearing empty drone targets.


## v0.19.6-local.1 (maintenance fork)

* Reconcile divergent conveyor layouts automatically without reloading the world.
* Forward guest quest completions to the host’s native quest and reward logic.
* Apply conveyor changes to the requested segment, deduplicate repeated additions,
  preserve line identifiers and avoid coarse position-key collisions.
* Keep direction changes on existing belts and prevent clients from spawning
  duplicate cargo when mirrored belts are reversed or removed.
* Let the host resolve belt-record pickup before handing the item to the guest.
* Reject stale movement, state and deletion messages from former prop owners.
* Refresh prop movement and state periodically, including stationary items.
* Synchronize compact/T splitter settings and copy mutable setting snapshots.
* Transfer guest hay entering a host-owned container to its local simulation.
* Preserve tracked straw when the scan reaches its per-frame or overall limit.
* Use supported Steam RPC channels and reject replayed shared-state deltas.


## v0.19.5

* Hay tufts a guest drops on a belt go through splitters and on to the
  end. A belt takes most items out of the prop list and the guest hands
  them to the host, but a tuft stays an item riding the belt, so it only
  rode the guest's own belt, which just mirrors the host's. At a splitter
  it went off the path and back to the start over and over. The guest now
  hands a tuft to the host as soon as its belt catches it, and the host's
  belt carries it like the host's own (reported by xxKipxkipxx).
* Hay the host put on a belt no longer stops when a guest with a spade
  stands next to it. The spade take-over from 0.19.4 also took tufts
  riding a belt, and froze them there. It only takes loose ones now, and
  only while digging.

## v0.19.4

* Hay tufts the other player dropped (the little piles a full spade leaves)
  can be picked up now, by hand and with a spade. A new tuft has no
  collision layer until its own physics tick finds no straw inside it, and
  that tick is off on the other player's copy, so the copy never got its
  layer back and nobody but its maker could aim at it. The copy gets its
  layer right away now. A spade also takes the copy over when it is in
  reach, since a spade passes over a frozen or claimed wad.
* The crash trace (`mp_trace.log`) is much lighter. The messages that come
  in many times a second (moves, belt and machine updates) are counted on
  the once a second line instead of one line each, and the per machine
  lines are gone. It filled its 4 MB in about 18 minutes before.
* Loose straw a guest throws by hand into a hopper, or onto a belt that
  feeds a machine, is taken since 0.19.3 (#17), checked again in a
  two-player test.

## v0.19.3

* The guest crash within minutes of joining (reported in #15 by oogienl,
  thank you) is fixed since 0.19.2: an `as` cast on a machine part the game
  had already freed, in `_fx_of()`. A two-player session over Steam on
  0.19.2 ran with no crash.
* Machines a host puts up no longer stay a half-built green hologram on the
  guest's screen. While a machine is being built, the game swaps its
  materials for the build hologram, and the mod read and copied that as the
  machine's own, so the guest got the hologram's values and the game never
  put the real material back. The build hologram is now left alone.
* Loose straw a guest throws into a machine's hopper is taken now. On the
  host it was a frozen copy, and a machine will not eat a frozen straw. The
  host now makes it a real straw of its own and its machine eats it once.
* What is drawn on a paint board shows on everyone's board. A finished
  stroke, an erase or a wipe goes to the others, and a player who joins
  gets the boards as they are. A board showing a drawing from a player's
  own sketchbook is left alone, since the sketchbook is personal.

## v0.19.2

* Over Steam, machine updates go out in small pieces. Both guest crashes
  caught with the new trace came right after the host's big machine update
  arrived (up to 9 KB in one message), and it has never happened over a
  direct connection. Each machine's moves, lights and effects are now split
  into messages of about a kilobyte. A direct connection is unchanged.
* The trace now says which machine was being updated, and marks each frame
  that went by, so after a crash it shows whether the last message had
  finished.
* F6 (the debug menu) no longer fills the log with thousands of
  "debug_menu doesn't exist" errors on the 29 September game build.

## v0.19.1

* Free buildings from missions no longer multiply. Taking down a gift (a
  power pole, a rake or a cabinet) hands it back, and the game did that on
  the other player's side as well, so every dismantle made one more free
  building. Only the player who takes it down gets it back now.
* A crash trace for the guest crash over Steam, which still happens and
  leaves nothing useful in the game's crash log. The mod now writes
  `mp_trace.log` next to the game's crash logs: every message it receives,
  and when the heavier jobs (buildings, belts, the world) start and end, one
  line each, flushed as it goes. After a crash its last lines say what was
  being handled. It stays on the player's PC and holds no chat or names; the
  previous run's file is kept as `mp_trace.prev.log`.
* Checked against the game update of 29 September (V41): nothing the mod
  uses has changed.

## v0.19.0

* A guest no longer crashes when it quits the game. Godot takes the scene tree
  down from the last node to the first, so the world went before the mod had
  undone what it changes on a guest (straw copies put back into the physics
  world by hand, frozen copies of items, stopped machines). The mod now keeps
  itself last and cleans up first.
* The haystack is the host's. A guest's digs go to the host, which settles
  them into its own pile and sends the result to everyone. Every 4 seconds the
  host also sends a checksum per block of the pile, and a guest asks for any
  block that drifted. Two players digging, or a slide running differently on
  each side, used to leave different piles for good, until F8.
* A needle two players grab at the same moment goes to one of them. The host
  decides who holds each loose needle and the other player's copy leaves their
  hand. Both used to keep it, and it could be handed in twice. A guest who
  leaves while holding a needle drops it where they last stood instead of
  taking it with them.
* Missions pay once, on the host. A guest's own director paid a step too when
  it saw it finish, and that reached the host as more money.
* Two players buying the same tech rank at the same moment pay for it once:
  the host gives the second payment back.
* A new hay load a guest pays for is given back if the host cannot take it
  (the landing spot is blocked, for one).
* A guest's building no longer empties the host's list of buildings the demo
  holds back, which dropped them from the host's save, and enclosed belts keep
  their covers. The game's loader clears those along with the building lists.
* The farmer holds the right needle for every type. Past the 15th type the
  needle in the hand was read back through a 4-bit mask and came out wrong.
* A machine's smoke and glow no longer show on every machine of its kind on a
  guest (a shared material gets its own copy first). Machine updates too big
  for one packet go out reliably instead of being lost whole, a machine key a
  guest does not know no longer walks every machine again for every packet,
  and the state kept for demolished machines is let go.
* Items made after an F8 resync no longer take over older items: their ids
  carry on from the highest one already in the yard.
* Guests get the host's pile shape (the dome) with the world instead of
  shaping it again from the seed.
* An F8 resync on a guest no longer drops what it spent or earned since the
  last state tick.
* The contract board compares which contracts are done, not how many.
* Nothing is written into the game folder any more. The Steam app id goes in
  through the environment instead of a steam_appid.txt next to the exe. Steam
  callbacks run once a frame (they ran twice), and ENet takes eight players in
  total, like Steam.
* Career stats are left alone during a session, so nobody is credited with the
  whole team's hay, money and needles; the profile is read back from disk when
  the session ends. The online leaderboard is off for as long as the mod is
  loaded, as the README says, and the player name no longer runs a registry
  query at startup when Steam is up.
* Belt contents go out when they changed, and every 2 seconds, instead of four
  times a second.
* A machine a guest places is stopped straight away, not on the next build
  tick, and removing a building looks for that very building before the
  nearest one of its kind.
* `dev/mp_sync_test.gd`: two-player checks for the above, host and guest on one
  PC.
## v0.18.1

* A guest's game could crash while the host was building. The game keeps its
  straw in a pool: a straw that gets used up (a bucket or the vac takes it, a
  belt or a machine eats it) leaves the world and the same body comes back
  later as a different straw. The mod held on to its copies of the host's
  straw through that, kept moving them, read their position once they were
  out of the world (the "!is_inside_tree" errors in the crash logs), and when
  the host's straw went away it handed the body back to the pool again, while
  a belt, a hand or a machine was using it as something else. Building moves
  and clears a lot of straw, which is why it showed up then. The mod now lets
  go of a straw body the moment the game takes it out of the world.

## v0.18.0

* Hay a guest drops on a belt now gets there. The guest's own belt took the
  item and the host's next belt snapshot wiped it, so it was gone before any
  machine could see it. The guest now hands it to the host at the spot where
  it landed, the host's belt carries it, and the machine at the end takes it
  like any other hay.
* Contracts are run by the host only. Every player used to run their own:
  their own truck on their own timer, their own count of what was loaded, and
  a finished order paid on the guest too, which reached the host as more
  money, so the bonus came twice. The guest's truck, its load and the board
  now follow the host's. A guest's bale loaded into the truck also counted
  over and over, because the host asked the guest to send it back after
  loading it; it is now gone for everyone once the truck takes it.
* Steam games go through Steam's relays only. The crash some players get a
  while after joining, or when building, was traced by one of them to an
  assert in Steam's direct peer-to-peer code (m_pTransportICE), which takes the
  whole game down; that code is now switched off. Relays add a few ms and keep
  players' IP addresses private.
* Steam's send buffer is 8 MB instead of 512 KB. The world goes to a guest in
  one go, and a big yard did not fit, so Steam refused the rest of it.

## v0.17.0

* Hay a guest loads into a machine finally counts. A machine skips a frozen
  body that is not riding a belt, and a copy of somebody else's item is
  exactly that, so a guest could fill a generator all day and nothing burned.
  The host now takes over an item that is sitting in a machine's mouth and
  lets the machine's own code swallow it. It burns once, on the host, and
  everyone sees the fuel move. An item somebody is carrying is left alone.

## v0.16.0

* Guests can work the machines from their own panels. Switching a machine on
  or off, the throw distance on a rake or a pelletizer, a launcher's aim and
  power, which way a splitter sends things, an arm's tier and what it accepts,
  a scanner's tier, a work lamp's brightness: change any of those as a guest
  and the host now hears about it and the machine actually does it. Only the
  settings travel. Fuel, stock and output stay the host's to count, so the
  same hay still cannot pay twice. Hay a guest feeds into a machine by hand is
  still not taken; that is the other half and it is not in yet.

## v0.15.1

* The guest was given the short warehouse. Since the 27 Sep game build a save
  carries how long the warehouse is, and the world the host sends a guest is
  built by hand and did not include it, so guests loaded the old, shorter shed.
  The sell stand is placed from that length, so the two players had theirs 11 m
  apart: hay sent along a belt to one stand landed on bare floor at the other,
  and walking up to sell could put you inside a wall. Host and guest now build
  the same yard.

## v0.15.0

* The chat box, the chat and notification cards and the guest's "joining"
  card now look like the game's own UI. The chat box is framed like the
  lobby's rename field, with the game's Enter key in front, and sits clear of
  the hotbar. Cards are the square HUD cards, with the name in bold and the
  message in the regular face. The joining card is the lobby's save slot card
  with the current step marked by a gold edge. The multiplayer panel is
  unchanged.

## v0.14.1

* No more flood of "Peer is only set up to use 4 channels" warnings. The
  Steam connection only has channels 0-3, so every message sent on a higher
  channel logged a warning and went out on channel 0 anyway. Those messages
  use channel 0 directly now; what goes over the wire is unchanged.
* A prop, a strand of straw or a machine that the game had taken out of the
  scene for a moment (while picking it up, for example) was read as sitting
  at the origin. That filled the log with `!is_inside_tree()` errors and could
  send the copy on the other side to 0,0,0. Those are skipped until they are
  back in the scene.
* The notification feed no longer logs "does not have any 'meta' values with
  the key 'tw'" every time a message appears.
* The props, machines and straw scripts are compile-checked at startup like
  the rest, so a broken file shows up in the log straight away.

## v0.14.0

* Half of every machine's parts never arrived. The number that names a part
  is a 32-bit hash travelling in a signed 32-bit array, so any hash past the
  sign bit turned into a different number on the way and matched nothing.
  Those parts kept whatever pose they happened to be in, mixed in with the
  ones that did arrive, which is what made machines look bent. Ids are kept
  inside 31 bits now and the whole machine comes across.
* Machines are solid again on clients. They were being stopped with
  `process_mode`, and a disabled node takes its collision body out of the
  world and stops its particles, so a machine was a hole you could walk
  through with no smoke and no fire. They are stopped by their processing
  alone now, which is what takes them out of the factory's clock anyway.
* Fire, lamps and the generator's smoke reach everyone: the walk that gathers
  a machine's moving parts starts at the machine itself, since the fire and
  the smoke column are built in code and hang off it rather than off its
  model.
* You can pick things up again. A player holding straw carried an invisible
  solid wad welded to their hand, because the item put itself back on the
  prop layer after we had cleared it; your aim hit that instead of whatever
  you were pointing at, and once it was in your hands nothing else could be.
* The same thing, twice over: a pushed wheelbarrow left an invisible copy of
  itself standing wherever it had been, and a hidden tool in somebody's hand
  stayed solid. Both are out of the way now.
* An item in a hand keeps the kinematic body the game gives it instead of
  being forced static.

## v0.13.0

* A guest who accepts an invite is told what is going on. A card lists the
  five steps (connecting, the host is picking a save, receiving the yard with
  the real transfer percentage, loading, in) and a line under it says what
  they should do, which is usually nothing. It gets out of the way once they
  land, and comes back if the host walks out to the menu.
* Joining, leaving and chat no longer drop a bare line of text in the middle
  of the screen. Each one is a card in the player's own colour, they stack,
  they fade on their own, and the same message twice gets a ×2 instead of a
  second card.
* The loading screen a guest sees while entering was hard-coded in Spanish.
  It follows the game's language like everything else now.
* Machines move smoothly instead of in steps. Their parts were chasing the
  newest pose with a fixed pull, so every packet gave them a shove and they
  coasted in between. Each part now walks from where it was to where it got
  to, over the gap between packets.
* A machine's parts are all sent again every couple of seconds. Poses travel
  on a channel that does not resend what it drops, so a part that moved once
  and stopped, like an arm parking or a lid closing, could stay wrong on the
  other screen for good. It also puts right anything that started out
  differently.
* Smoke, flames and lamps show up on machines that are not yours. The
  generator's smoke is a value inside a shader and its fire is a light, not
  particles, so a frozen machine looked cold. Those are copied now as well.
* Straw somebody throws lands where it lands instead of stuttering: copies
  slide to the position they were last seen at, and they are picked up twice
  as often, so they show the moment they leave a hand.
* A fistful of straw is drawn as a small pile, the one the belts carry,
  instead of a bundle of upright strands. It was also growing with every pose
  packet that arrived, which is how it ended up the size of a bale.

## v0.12.0

* Machines no longer come out crooked on the other screen. Each moving part
  was named by its place in the machine's list of child nodes, and that list
  is not the same on both sides: the game adds and drops nodes of its own as
  it runs (alert markers, dust, range rings). One extra node and every part
  was handed the pose of another. Parts are named by where they hang now.
* A part's orientation is sent whole instead of being rebuilt from a rotation
  and a scale, which straightened out the parts that are skewed, and the
  easing works axis by axis for the same reason.
* Straw somebody else dropped can be picked up. Their copies had no collision
  at all, so your hand went through them. They are solid now, and taking one
  hands it over: theirs goes, yours becomes real, and one straw stays one
  straw.

## v0.11.0

* You can see what somebody is holding. Straw picked up by hand shows in the
  remote farmer's fist, fanned out the way the game holds it, and a needle
  shows as the needle it really is. The pose packet carries one more number
  for it; nothing else changed on the wire.
* Straw held in a hand, a bucket or on a tool is no longer also scattered on
  everyone else's floor. It travels with whatever holds it.
* Other players see you push the wheelbarrow. Your farmer holds it by both
  handles, leans into it and puts the tool away, instead of standing next to
  a barrow that floats where your first-person view has it. It has a
  hand-placed pose for standing and one for crouching, both made in the tool
  poser (entry 7). Needs this version on both sides; older ones still see
  the loose barrow.

## v0.10.0

* Machines were never really stopped on clients. The game runs them from one
  central clock that walks its own list and only skips a machine whose physics
  processing is off, which `process_mode` does not touch. Nine of the fourteen
  we thought were parked kept eating hay, filling belts and making items on
  every player's machine at once, each with its own numbers. That is what made
  one player see a machine working and the other see it idle. They are out of
  the loop now.
* Machines move on clients again. The host sends where their moving parts are,
  which parts are drawn and which particles are running, so smoke, flames and
  lamps come across too. It makes no difference whether a machine is driven by
  an animation or from code.
* Machine settings are shared: switches, splitter filters and priorities, rake
  and pelletizer throw distance, launcher aim and power, silo and press stock,
  lamp brightness, and the generator's fuel and output, which is what the
  client's power grid reads to keep the yard running.
* Loose straw is shared. The straw you dig up now lands on everyone's floor.
  The copies have no physics and cannot be picked up, so a straw can never be
  turned into hay twice.
* Nobody was paying for a new load of hay. The client's charge never left,
  because ordering a load stops its updates first, and the host then undid its
  own charge assuming the client's was on the way.
* Needles that surface on their own as the pile is dug are announced by the
  host only. Both sides popping them out gave two bodies for one needle.

## v0.9.1

* Items somebody else owns can be picked up again. Their copy was moved by
  setting its transform, which on a frozen body leaves the collision shape
  where it was: you saw the bale in front of you while its shape sat back at
  the spot where it first appeared, so the pick-up ray went straight past it.
  Copies are now moved the way the game moves a held item, telling the
  physics server as well, and they are static rather than kinematic so they
  no longer shove anyone as they follow their owner.
* A player holding the toy shovel no longer shows a second, floating one to
  everyone else. The toy shovel is a real item even while held, and its copy
  followed the holder's first-person view next to the one in the farmer's
  hand. Copies of held tools are now hidden while they are up there.

## v0.9.0

* Held tools are placed by hand. Each of the six tools has its own position,
  angle and length in the farmer's hand (`tool_poses.cfg`) instead of the
  automatic guess, which held them like spears and the toy shovel upside down.
  Five of them also have a crouch pose that the farmer eases into when
  crouching. Tools without an entry keep the automatic fit.
* `dev/tool_poser.gd` (not shipped) is the tool used to place them: an empty
  stage with a move/rotate gizmo, started with `dev/tool_poser.bat`.

## v0.8.0

* Loose items are shared. Buckets, sacks, bales and wads now exist once for
  the whole session: whoever made an item sends where it is, and picking up
  someone else's item hands it over to you. Items that a remote player owns
  are held still locally, so the yard cleaner and the machines leave them
  alone.
* Belt contents are shared. The host sends the ride list a few times a second
  and clients board it on their own belts, which keep turning in between, so
  the boxes and bales move instead of jumping.
* More machines are host-only, now that the belts and the items they make
  arrive over the wire: compressor, pulper, paper machine, briquette press,
  wrapper, silo, pelletizer, tube launcher, dump hatch and needle radar join
  the rake, the arm, the drone and the scanner. Running them on both sides
  would have turned the same hay into two bales.
* F6 opens the game's own debug menu, with buttons added for taking money
  away as well as granting it. Handy for setting up a session. The game marks
  a run that used it, so it no longer counts for the leaderboards.

## v0.7.0

* Remote players stand straight when idle. The old idle clip had the hips
  twisted and left the feet where the last step put them, so the shoes
  stretched after walking.
* Farmer height and crouch tuned in game so eyes meet at the camera height,
  standing and crouched. `dev/avatar_calib.gd` is the tool used for it.
* You can see your own body when you look down during a session: headless,
  a bit behind the camera, in your colour, with your shadow. Single player
  is unchanged.

## v0.6.0

* An optional install helper lives in `tools/` and is attached to the release,
  for anyone who would rather not edit `override.cfg` by hand. It is kept out
  of the download so the archive carries no scripts.

* No scripts in the download. The autoload line now uses a path relative to
  the game folder, so it is the same on every machine: copy the mods folder
  and add two lines to override.cfg by hand. The .bat installers are gone.
* Tested on game build V30.

## v0.5.0

* Remote players are an animated farmer (Quaternius, CC0) instead of a figure
  made of primitives. The overalls and the hat band take the player's colour,
  the head follows the look pitch, the knees bend when crouching, and the clip
  follows the real speed. The model adds 500 KB; if it is missing, the old
  figure is used.
* Held tools are scaled to a real-world length each, so the metal detector is
  no longer as long as a spade.
* The interface follows the game's language. English, Spanish, German, French,
  Italian, Czech, Polish, Russian, Turkish, Japanese, Korean and Chinese are
  included; anything else falls back to English. Tool names come from the
  game's own translations.

## v0.4.0

* Rewrote the installer as plain batch. `INSTALL.bat` and `UNINSTALL.bat` no
  longer call PowerShell with an execution-policy bypass. They are short
  scripts that add or remove one line in `override.cfg`.
* The installer now takes the current `override.cfg` as its base instead of
  restoring an old backup, so settings added by a game update survive.
* Turned the held tool models 180 degrees. Remote players were holding the
  spade and the pitchfork by the head. `flip_tool` on the avatar turns a model
  back, which helps when trying out new ones.
* Tested on game build V30.

## v0.3.0

* The panel no longer prints IP addresses, Steam IDs or lobby codes. Local
  addresses only show after pressing "Show my IPs", in the advanced section.
* Numbered steps in the panel (create game, invite friends, start playing) with
  the current one highlighted. The IP mode is folded away as an advanced option.
* Added English installer scripts next to the Spanish ones.

## v0.2.0

* Steam networking. Hosting, invites and joining go through Steam's relay, so
  there is no port forwarding and no IP addresses. The mod loads the GodotSteam
  GDExtension at runtime and initialises Steam under the demo's app id.
* Invites from the Steam overlay, from the friends list, or by accepting one
  while the game is closed.
* Player names come from Steam.
* Uncovered needles are shared. They show up for everyone and can only be
  handed in once.
* Clients spawn at the game's normal starting spot.
* Remote players got arms and hold their tool properly.
* Rebuilt the panel: centred, dimmed background, no more broken labels.

## v0.1.0

* First working co-op build over direct IP (ENet).
* Shared haystack, buildings, economy and tech tree.
* The host's world is handed to joining players through the game's own save
  format. Clients never write to their own saves.
* Remote player avatars with name tags, chat (Y) and resync (F8).
