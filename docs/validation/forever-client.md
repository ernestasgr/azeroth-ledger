# Forever client capability check

For [Validate persistence, WoWUnit and required capabilities in the target Forever client](https://github.com/ernestasgr/azeroth-ledger/issues/9). Record observations from the actual client. Do not treat an installed build, Mainline API declaration, or mocked test as an in-client pass.

## Known local installation

On 25 September 2026, the local `World of Warcraft/_classic_beta_` installation's `.flavor.info` said `wow_classic_beta`. The root `.build.info` listed active product `wow_classic_beta`, version `1.60.1.70009`. The game was not running. `GetBuildInfo()`, interface version, runtime behavior, and whether this is the intended Forever character environment are unverified. Before preparation, the AddOns directory was empty, and no Forever capability test had been run.

The temporary probe and upstream WoWUnit are now installed in that beta's AddOns directory. WoWUnit was copied from Jaliborc/WoWUnit commit `45f9273818f1377340d624172e7a7e9cc2f247a0`, whose TOC declares version 12.1. Installation is preparation, not a test pass.

## Live results, 25 September 2026

The user ran the probe in the target beta and reported these startup lines:

```text
Forever probe build: 1.60.1 70009 Sep 23 2026 16001
Forever probe Lua: Lua 5.1 project: 1
Forever probe marker: test-20260925
Forever probe WoWUnit group registered
```

After `/reload`, `/fp status` again printed the same build, Lua, project and marker values. The user reported both `ForeverCapabilityProbeSmoke` tests passing in WoWUnit. An account SavedVariables file also contained `test-20260925`. On a second character on the same account, the probe again showed the marker. It remained present after returning to the first character and after exiting and restarting the client completely. The user reported no Lua error popup during these checks. This passes the live reload, cross-character and full-restart SavedVariables gates, and the genuine in-client WoWUnit smoke gate, on build 70009. Acquisition event traces and native UI capabilities remain unrun or unreported.

On loading the opt-in event tracer, build 70009 rejected registration of `PLAYERREAGENTBANKSLOTS_CHANGED`. The command `/fpt status` worked and showed a stopped trace with zero records. The unsupported event has been removed from the probe's next revision; no loot trace had yet been captured at this point.

Two subsequent ordinary corpse-loot traces were saved on build 70009. The raw SavedVariables trace contains a character name and GUID; the findings below intentionally omit them.

- In the first trace, `LOOT_OPENED(false, false)` preceded a receipt message for item 2672, bag updates, two `LOOT_CLOSED` events, then a receipt message for item 7074 and more bag updates. A receipt can therefore arrive after `LOOT_CLOSED`; the close event also repeated. The recorded chat messages identified the player but did not establish a corpse GUID.
- In the second trace, `LOOT_OPENED(false, false)` was followed by two `LOOT_CLOSED` events and then two identical receipt messages for item 4865 (`Ruined Pelt`) at the same elapsed timestamp, with different chat line IDs. Bag updates followed. The user estimated the stack changed from five to six, but the starting count was uncertain. This is evidence of duplicate-looking receipt messages, not yet proof that one or two units entered the bags. A controlled before/after bag snapshot is needed before setting the reconciliation rule.
- In a controlled third trace, bag snapshots showed item 4865 increasing from **6 to 8**, with every other recorded bag item total unchanged. One `CHAT_MSG_LOOT` reported `Ruined Pelt x2`. `LOOT_CLOSED` was again emitted twice before the receipt message, followed by bag updates. The snapshots and message agree on two acquired units for this case. The earlier two-message case remains ambiguous because it lacked a reliable starting bag count.
- In a fourth ordinary corpse trace, `GetLootSourceInfo` returned a Creature GUID and quantity **1** for the loot slot containing item 4865. The loot receipt message came after two `LOOT_CLOSED` events. This verifies a per-slot source GUID for this case; the raw GUID is kept local, and a readable mob name was not established by the trace. The probe's saved `tooltipEnabled` value was `false` after the UI check.

The user then selected `Gardening Pants` from a choice-reward quest. `QUEST_LOOT_RECEIVED` reported quest ID **92463**, the full item link for item **263409**, and quantity **1**. `QUEST_TURNED_IN` followed about 0.03 seconds later; `CHAT_MSG_LOOT` reported `You receive item` and bag updates followed. Before/after bag snapshots showed item 263409 absent then present with quantity **1**. Other quests and ordinary loot occurred in the same capture, so the explicit quest event and item-specific bag change are the basis for attribution. This proves a choice-reward path on build 70009, with multiple notification channels for one acquisition; a fixed-reward quest and cancelled/declined quest remain untested.

The user also ran `/dump` on build 70009: `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnCategory`, `TooltipDataProcessor.AddTooltipPostCall`, `DressUpItemLink`, and `GetLootSourceInfo` each returned `function`. This confirms availability by name only; registration, callbacks, preview and usable source values require the live checks below.

The probe then registered an in-game AddOns Settings category and item tooltip post-call hook without error. The user switched the probe checkbox off, reloaded, observed that it stayed off in the Settings menu, then switched it back on; `/fpu status` subsequently reported `true`, as expected. With the probe tooltip line enabled, the user hovered a bag item twice and a chat-linked item; each tooltip showed exactly one `Forever capability probe` line and no Lua error appeared. Ctrl-clicking a wearable item opened the native dressing room and displayed it. These pass the tested Settings, item tooltip and basic wearable-preview cases on build 70009. Uncached items, repeated asynchronous tooltip rebuilds, non-wearable previews and other native UI edge cases remain untested.

## Prepare the run

1. Check that `ForeverCapabilityProbe` and `WoWUnit` are visible and enabled at character selection. The probe's provisional TOC declares interface `16001`; if the client reports another interface, record it and update the probe TOC before testing.
2. The installed WoWUnit is a separate upstream copy at the commit noted above. Its TOC declares version 12.1 and interface 16001, but that declaration is not a client test.
3. Use a disposable character or ordinary test items. Enable Lua error display (`/console scriptErrors 1`) and record the game build, locale, character/realm aliases, enabled addon versions, and test date. Redact account and character names in any shared trace.
4. Capture the probe's startup chat lines. Also run `/dump GetBuildInfo()`, `/dump WOW_PROJECT_ID`, and `/dump _VERSION`. Record all return values. If `/dump` is unavailable, record the probe's build line and the exact error.

## Persistence gate

1. In game, run `/fp mark <unique-token>` and `/fp status`; record the exact marker shown.
2. Run `/reload`, then `/fp status`. The same token must be restored by the client, not merely written to a file.
3. Log out, switch to another character on the same WoW account, run `/fp status`, then return to the first character and check again. Record both results.
4. Exit the client completely, confirm its process has stopped, restart it, and run `/fp status`. Record the result and any Lua errors.
5. Optionally inspect the account SavedVariables file for the marker after a clean logout, but file presence alone is not a pass. If any step fails, retain the before/after trace and mark this gate failed; do not adopt a loader patch or external storage workaround without a separate decision.

## WoWUnit gate

With WoWUnit and the probe enabled, confirm the probe prints `WoWUnit group registered`. Open WoWUnit's in-game test panel and record both `ForeverCapabilityProbeSmoke` tests as passing, or the exact load/assertion error. Verify the loaded WoWUnit version and whether the installed package required TOC or load-order changes. A registered group without visible execution is not a pass. If WoWUnit is unavailable, record that separately from persistence.

## API and UI trace matrix

For each row, capture the relevant event trace with payloads and sequence, one successful action and the listed control case, on the recorded build. Record whether item links or fields are delayed, duplicated, localized, secret/inaccessible, or absent. Include bag/bank quantities before and after. Keep raw links for intrinsic variant inspection. Do not infer a source from proximity alone.

| Capability | Successful case | Control or ambiguity case |
| --- | --- | --- |
| Loot | Loot one corpse and one item container; capture `LOOT_OPENED`, `CHAT_MSG_LOOT`, bag changes, and any source GUID/name | Group award and area loot from two corpses; check self-versus-party and ambiguous source |
| Quest | Complete fixed and choice rewards; capture quest ID, link, quantity, chat, and bag changes | Abandon or decline a quest; check that no acquisition is inferred |
| Crafting | Craft one item and a short batch; capture recipe/result evidence and output quantities | Cancel crafting before success; check duplicate notifications |
| Vendor | Buy one item and one stack; capture success evidence and inventory delta | Full-bag failed purchase, sale and buyback |
| Trade | Complete an incoming item trade with an identified counterparty | Cancel a trade and receive the same item from another source nearby in time |
| Mail | Retrieve one attachment and a stack; record sender and item evidence | Open without taking; retrieve an item mailed by an alt |
| Bank/equipment | Scan bag and bank, transfer both directions, then equip/unequip | Close bank and relog an alt; record which storage remains unreadable and scan freshness |
| Item data | Observe an uncached item link and request metadata | Record failed/delayed callbacks and whether the original link survives |
| Native UI | Register a temporary Settings category, add one item tooltip line, preview one wearable link in dressing room | Repeat tooltip rebuild, use an uncached link and a non-wearable item; record API or template gaps |
| Location | Discover one item outdoors and one inside a dungeon | Compare stable map/instance identifiers with localized names |

Use `/eventtrace` if present; otherwise use a temporary event logger that records event names, argument types/values, timestamps and inventory snapshots. Some payloads may reject inspection; record the error rather than coercing a secret value. An event name alone does not prove successful acquisition, quantity, source or ordering.

The probe includes an opt-in event logger for this purpose. After the updated probe files are copied into the AddOns directory and the client is reloaded, run `/fpt clear` to discard saved test traces, `/fpt start loot` (replace `loot` with a short scenario name), `/fpt snap before`, perform one case, `/fpt snap after`, then `/fpt stop` and `/reload` to flush the records to the probe's account SavedVariables file. Keep one scenario name per case. The logger records selected event names, elapsed client time and printable arguments, retaining at most 500 records. The snapshot records total stack quantities in bags 0–4 by item ID; it does not prove bank or equipment state. The logger records `<inaccessible>` if an argument cannot be stringified. The raw trace may contain other players' names; redact those before sharing. Unsupported event registrations print a diagnostic at startup and should be reported.

The next probe revision also records `LOOT_SOURCE_SLOT` when a loot window opens, using the actual slot link and `GetLootSourceInfo` return values. For native UI, it registers a temporary **Forever Capability Probe** category under in-game AddOns settings with one SavedVariables-backed checkbox. Toggle it, run `/fpu status`, reload, and confirm the value remains. Run `/fpu tooltip on`, hover an item in a bag or chat link, and check that a single `Forever capability probe` line appears without an error or repeated lines. Run `/fpu tooltip off` afterward. Preview one wearable item with the native dressing room and report whether it opens and displays the model. These actions test behavior beyond the `/dump` function checks.

## Report back to the ticket

For each gate, state **pass**, **fail**, or **unrun**, the build and locale, the exact steps, observed output, and any reproduction trace or screenshot. Keep uncertainty explicit. The issue remains open until persistence, genuine in-client WoWUnit execution, required recording signals, and native UI facilities are evidenced on the intended build.
