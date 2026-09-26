# Forever client capability check

For [Check saved data, WoWUnit, and required Forever features](https://github.com/ernestasgr/azeroth-ledger/issues/9). Record observations from the actual client. Do not treat an installed build, Mainline API declaration, or mocked test as an in-client pass.

## Known local installation

Before live testing on 25 September 2026, the local `World of Warcraft/_classic_beta_` installation's `.flavor.info` said `wow_classic_beta`. The root `.build.info` listed active product `wow_classic_beta`, version `1.60.1.70009`. The game was not running at that initial inspection, so `GetBuildInfo()`, interface version and runtime behavior were still unverified. Before preparation, the AddOns directory was empty, and no Forever capability test had been run.

The temporary probe and upstream WoWUnit are now installed in that beta's AddOns directory. WoWUnit was copied from Jaliborc/WoWUnit commit `45f9273818f1377340d624172e7a7e9cc2f247a0`, whose TOC declares version 12.1. Installation is preparation, not a test pass.

## Live results, 25 September 2026

The user ran the probe in the target beta and reported these startup lines:

```text
Forever probe build: 1.60.1 70009 Sep 23 2026 16001
Forever probe Lua: Lua 5.1 project: 1
Forever probe marker: test-20260925
Forever probe WoWUnit group registered
```

The user later ran `/dump GetLocale()` and reported `enUS`. The installed build and this locale identify the live traces below; other locales remain untested.

After `/reload`, `/fp status` again printed the same build, Lua, project and marker values. The user reported both `ForeverCapabilityProbeSmoke` tests passing in WoWUnit. An account SavedVariables file also contained `test-20260925`. On a second character on the same account, the probe again showed the marker. It remained present after returning to the first character and after exiting and restarting the client completely. The user reported no Lua error popup during these checks. This passes the live reload, cross-character and full-restart SavedVariables gates, and the genuine in-client WoWUnit smoke gate, on build 70009. The item gain and native UI checks followed later in the run.

On loading the opt-in event tracer, build 70009 rejected registration of `PLAYERREAGENTBANKSLOTS_CHANGED`. The command `/fpt status` worked and showed a stopped trace with zero records. The unsupported event has been removed from the probe's next revision; no loot trace had yet been captured at this point.

Two subsequent ordinary corpse-loot traces were saved on build 70009. The raw SavedVariables trace contains a character name and GUID; the findings below intentionally omit them.

- In the first trace, `LOOT_OPENED(false, false)` preceded a receipt message for item 2672, bag updates, two `LOOT_CLOSED` events, then a receipt message for item 7074 and more bag updates. A receipt can therefore arrive after `LOOT_CLOSED`; the close event also repeated. The recorded chat messages identified the player but did not establish a corpse GUID.
- In the second trace, `LOOT_OPENED(false, false)` was followed by two `LOOT_CLOSED` events and then two identical receipt messages for item 4865 (`Ruined Pelt`) at the same elapsed timestamp, with different chat line IDs. Bag updates followed. The user estimated the stack changed from five to six, but the starting count was uncertain. This is evidence of duplicate-looking receipt messages, not yet proof that one or two units entered the bags. A controlled before/after bag snapshot is needed before setting the reconciliation rule.
- In a controlled third trace, bag snapshots showed item 4865 increasing from **6 to 8**, with every other recorded bag item total unchanged. One `CHAT_MSG_LOOT` reported `Ruined Pelt x2`. `LOOT_CLOSED` was again emitted twice before the receipt message, followed by bag updates. The snapshots and message agree on two gained units for this case. The earlier two-message case remains ambiguous because it lacked a reliable starting bag count.
- In a fourth ordinary corpse trace, `GetLootSourceInfo` returned a Creature GUID and quantity **1** for the loot slot containing item 4865. The loot receipt message came after two `LOOT_CLOSED` events. This verifies a per-slot source GUID for this case; the raw GUID is kept local, and a readable mob name was not established by the trace. The probe's saved `tooltipEnabled` value was `false` after the UI check.

The user then selected `Gardening Pants` from a choice-reward quest. `QUEST_LOOT_RECEIVED` reported quest ID **92463**, the full item link for item **263409**, and quantity **1**. `QUEST_TURNED_IN` followed about 0.03 seconds later; `CHAT_MSG_LOOT` reported `You receive item` and bag updates followed. Before/after bag snapshots showed item 263409 absent then present with quantity **1**. Other quests and ordinary loot occurred in the same capture, so the explicit quest event and item-specific bag change are the basis for attribution. This proves a choice-reward path on build 70009, with multiple notification channels for one item gain; a fixed-reward quest and cancelled/declined quest remain untested.

For a merchant purchase, item **4540** (`Tough Hunk of Bread`) was absent in the first bag snapshot and present at quantity **5** in the second. During an open merchant session, `MERCHANT_UPDATE` and one `CHAT_MSG_LOOT` receipt reporting `x5` preceded the bag change and `PLAYER_MONEY`; no separate purchase-completion event was captured in this event set. Several unrelated bag item types disappeared earlier in the same trace, with a money and bag update before the bread receipt. The user confirmed they sold gray items before buying the bread. Sale and purchase must be correlated separately. The bread purchase is observed on build 70009; failed-purchase and buyback behavior remain untested because the sold items were unavailable for buyback in this run.

For an equipment move, the user equipped and then unequipped `Gardening Pants` (item **263409**). Bag snapshots showed quantity **1 → 0 → 1**; another item appeared in the bag during the equip swap and disappeared on return. `PLAYER_EQUIPMENT_CHANGED` reported slot **7** on both moves, alongside `UNIT_INVENTORY_CHANGED` and bag updates. No receipt message appeared. This supports treating equip and unequip as ownership movement, without a new item gain.

For a bank transfer, the user deposited and withdrew one `Ragged Leather Belt` (item **1369**) while the bank was open. Saved snapshots showed its bag quantity **1 → 0 → 1** and aggregate bank quantity **0 → 1 → 0**. Both moves produced `BAG_UPDATE` for containers **0**, **-1**, and **6**, followed by `BAG_UPDATE_DELAYED`; neither move produced a loot receipt. `BANKFRAME_OPENED` and `BANKFRAME_CLOSED` bracketed the session. The bank scanner saw **32** slots at **-1** and **48** at **6** while open. After closing, container **6** reported **0** slots while **-1** still reported **32**; a closed-window scan must not be interpreted as a complete, fresh bank inventory. No Lua error was reported. The event trace also captured many unrelated `CHAT_MSG_TRADESKILLS` messages, so event count alone is not a useful measure of action count. An alt relog with bank contents has not been tested.

On a sending alt, the user mailed **3** `Refreshing Spring Water` (item **159**) to the level 1 character. The sender's bag snapshot showed **3 → 0**, with all other recorded item totals unchanged. `MAIL_SEND_SUCCESS` and `MAIL_SUCCESS` fired at the same elapsed time; money and bag updates followed. On the recipient, item 159 was already present at quantity **3**. Opening the mailbox and message without taking the attachment left it at **3**; taking the attachment raised it to **6**. `MAIL_SHOW` and `MAIL_INBOX_UPDATE` preceded the take. At the take, `MAIL_INBOX_UPDATE` and `MAIL_SUCCESS` fired, followed by one `CHAT_MSG_LOOT` receipt for x3; another `MAIL_INBOX_UPDATE` and `MAIL_SUCCESS` pair then preceded bag updates. Thus `MAIL_SUCCESS` can fire twice for one take, and an unchanged item type count does not mean no items were gained. The sender's raw trace contains unrelated trade-skill chat; the probe now filters that event outside crafting scenarios for future runs. One attachment retrieval and the open-without-taking control passed; a separate stack quantity is covered by this x3 case, but other sender/attachment types remain untested.

The user then crafted one `Bolt of Linen Cloth` (item **2996**). The before/after bag snapshots showed Linen Cloth (item **2589**) **2 → 0** and Bolt of Linen Cloth **absent → 1**. The trace recorded `TRADE_SKILL_ITEM_CRAFTED_RESULT` followed by a separate `CRAFT_RESULT_FIELDS` record with item ID **2996** and quantity **1**, then `CHAT_MSG_LOOT` and bag updates. This is a successful single-craft pass with no reported Lua error. A short batch and a cancelled craft remain untested.

## Current gate status

| Gate | Build 70009 result |
| --- | --- |
| SavedVariables across reload, second character, return and restart | Passed |
| Jaliborc WoWUnit smoke assertions | Passed |
| Blizzard UI source from installed client | Exported and inspected on the tested installation; native C implementations are outside the export |
| Ordinary corpse loot, item quantity and per-slot Creature source GUID | Passed for tested examples; duplicate-looking receipt case remains ambiguous |
| Quest reward | Choice reward passed; fixed reward and cancellation untested |
| Merchant purchase and sale | Bread stack purchase and gray-item sales observed; failed purchase and buyback untested |
| Equipment movement | Equip and unequip passed; no item receipt appeared |
| Native Settings, item tooltip and wearable dressing room | Passed for tested basic cases; uncached/rebuild and non-wearable edges untested |
| Bank transfer | One-item deposit and withdrawal passed; closed-bank container 6 became unreadable; alt relog untested |
| Mail | Alt send and x3 retrieval passed; opening without taking left bags unchanged; `MAIL_SUCCESS` repeated |
| Crafting | One Bolt of Linen Cloth craft passed with item ID/quantity payload and material/output bag deltas; batch and cancellation untested |
| Trade | Unrun; no partner was available |

The user initially reported no access to crafting, trade, mail or a bank, but later completed bank, mail and one single-craft case. The validation ticket closed with trade, a short craft batch, a cancelled craft, fixed quest rewards, failed purchases, buyback, multi-source loot, uncached item callbacks, and native UI edge cases still unrun. [The release plan](https://github.com/ernestasgr/azeroth-ledger/issues/8) requires these limits to be documented. Record `GetLocale()` with each future run and do not generalize these English-language traces to other locales without a localized check.

On a later session with bank access, the user ran `/dump` while the bank was open. On build 70009, `C_Container.GetContainerNumSlots(-1)` returned **32**; container indexes **5** and **6** initially returned **0**; `C_Bank` was a table. After the user bought additional bank space, index **6** returned **48** slots. The probe supports `/fpt bank <label>` for aggregate snapshots of container `-1` and bank indexes `5`–`11`, with slot counts retained per container. The transfer and closed-bank results are recorded above.

The user also ran `/dump` on build 70009: `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnCategory`, `TooltipDataProcessor.AddTooltipPostCall`, `DressUpItemLink`, and `GetLootSourceInfo` each returned `function`. This confirms availability by name only; registration, callbacks, preview and usable source values require the live checks below.

The probe then registered an in-game AddOns Settings category and item tooltip post-call hook without error. The user switched the probe checkbox off, reloaded, observed that it stayed off in the Settings menu, then switched it back on; `/fpu status` subsequently reported `true`, as expected. With the probe tooltip line enabled, the user hovered a bag item twice and a chat-linked item; each tooltip showed exactly one `Forever capability probe` line and no Lua error appeared. Ctrl-clicking a wearable item opened the native dressing room and displayed it. These pass the tested Settings, item tooltip and basic wearable-preview cases on build 70009. Uncached items, repeated asynchronous tooltip rebuilds, non-wearable previews and other native UI edge cases remain untested.

## Exact-installation Blizzard UI source

The user enabled the client's login-screen console and ran `exportInterfaceFiles code` on the installed `_classic_beta_` client after reporting build 70009. It completed and created `_classic_beta_/BlizzardInterfaceCode/Interface/AddOns` with **4,413 files** on 25 September 2026. This is a local export from the tested installation, not a remote branch assumed to match it. The export contains files for multiple game types; its `.toc` load conditions must be read before treating a flavor-specific file as active. The native C API implementations are not present in the exported Lua, so source declarations still require runtime checks.

- `Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua` declares `C_Container.GetContainerItemInfo` as potentially returning nothing and defines `itemID`, `stackCount`, and `hyperlink` in `ContainerItemInfo`; both container lookups declare `SecretArguments = "AllowedWhenUntainted"`. The live bag and bank scans returned the item quantities above. No inaccessible value was reported by these traces, but the declaration prevents assuming every context is readable.
- `Blizzard_APIDocumentationGenerated/MailInfoDocumentation.lua` declares `MAIL_SEND_SUCCESS`, `MAIL_INBOX_UPDATE`, and `MAIL_SUCCESS`; `MAIL_SUCCESS.itemID` is nullable. Both recipient `MAIL_SUCCESS` events in the saved x3 trace carried `nil`. `Blizzard_MailFrame/MailFrame.lua` calls `TakeInboxItem` on attachment click and reacts to `MAIL_SUCCESS`, consistent with the observed action sequence; the runtime trace supplies the actual quantity evidence.
- `Blizzard_APIDocumentationGenerated/BankDocumentation.lua` declares `BANKFRAME_OPENED`, `BANKFRAME_CLOSED`, and `PLAYERBANKSLOTS_CHANGED` (slot payload), and several `C_Bank` functions carry the same secret-argument constraint. The tested transfer produced open/close and bag updates, but no `PLAYERBANKSLOTS_CHANGED`; consumers cannot require that event for a bank-bag transfer.
- `Blizzard_Settings_Shared/Blizzard_Settings.lua` defines `Settings.RegisterVerticalLayoutCategory` and `Settings.RegisterAddOnCategory`; `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua` defines `TooltipDataProcessor.AddTooltipPostCall`. The live probe exercised both paths. `Blizzard_UIPanels_Game/Mainline/DressUpFrames.lua` checks `C_Item.IsDressableItemByID` before `DressUpVisualLink`, then optionally tries housing preview and otherwise returns false. A wearable link passed in the live client; non-wearable runtime behavior remains untested.
- `Blizzard_APIDocumentationGenerated/TradeInfoDocumentation.lua` declares trade open, close, acceptance flags and target-item slot changes. `Blizzard_UIPanels_Game/Mainline/TradeFrame.lua` uses those events to update or hide the native frame; `TRADE_CLOSED` itself is only a close notification. No partner was available for a live trade, so neither a completed nor cancelled trade has a runtime pass. `TradeSkillUIDocumentation.lua` declares `TRADE_SKILL_ITEM_CRAFTED_RESULT` with a `CraftingItemResultData` payload; `TradeSkillUITypesDocumentation.lua` defines item ID, GUID, quantity and hyperlink fields. The probe records those scalar fields. The initial level 1 test character had no learned professions; one craft was later completed on another character, as recorded above. The source declarations alone do not establish runtime behavior.

For reproducibility, SHA-256 of the exported `ContainerDocumentation.lua` was `dd3e4741d45720384f814d3f78ce975dab3951458ae894e728ed3aedc8ae56b3`; `MailInfoDocumentation.lua` was `31f7dd4a22380561b76fea1fbcc65a0ab49121a5b807fbccfd0474e902d47751`; `Blizzard_Settings.lua` was `76ab19d14675e4e3dcf4fb1b02af35898e253e254da3cfce0ef655eab475e293`. The full export remains local and outside the repository.

## Prepare the run

1. Check that `ForeverCapabilityProbe` and `WoWUnit` are visible and enabled at character selection. The probe's provisional TOC declares interface `16001`; if the client reports another interface, record it and update the probe TOC before testing.
2. The installed WoWUnit is a separate upstream copy at the commit noted above. Its TOC declares version 12.1 and interface 16001, but that declaration is not a client test.
3. Use a disposable character or ordinary test items. Enable Lua error display (`/console scriptErrors 1`) and record the game build, locale, character/realm aliases, enabled addon versions, and test date. Redact account and character names in any shared trace.
4. Capture the probe's startup chat lines. Also run `/dump GetBuildInfo()`, `/dump WOW_PROJECT_ID`, and `/dump _VERSION`. Record all return values. If `/dump` is unavailable, record the probe's build line and the exact error.

To inspect the **exact installed build's** Blizzard UI source, enable the launcher option for additional game command-line arguments and add `-console`, restart the client, and open the console with `~` at login or character selection. Enter `exportInterfaceFiles code`; then inspect the resulting `_classic_beta_/BlizzardInterfaceCode` directory. Record the command's result and exported build before relying on the files. The in-game `/console` slash command is not the export route. Remove the temporary launcher argument afterward. This procedure is described in a [Blizzard UI forum reply](https://us.forums.blizzard.com/en/wow/t/are-there-any-commands-macro-lua-for-opening-generic-ui-elements-like-spellbook/812601/2) and was verified on build 70009, as recorded above.

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
| Quest | Complete fixed and choice rewards; capture quest ID, link, quantity, chat, and bag changes | Abandon or decline a quest; check that no item gain is inferred |
| Crafting | Craft one item and a short batch; capture recipe/result evidence and output quantities | Cancel crafting before success; check duplicate notifications |
| Vendor | Buy one item and one stack; capture success evidence and inventory delta | Full-bag failed purchase, sale and buyback |
| Trade | Complete an incoming item trade with an identified counterparty | Cancel a trade and receive the same item from another source nearby in time |
| Mail | Retrieve one attachment and a stack; record sender and item evidence | Open without taking; retrieve an item mailed by an alt |
| Bank/equipment | Scan bag and bank, transfer both directions, then equip/unequip | Close bank and relog an alt; record which storage remains unreadable and scan freshness |
| Item data | Observe an uncached item link and request metadata | Record failed/delayed callbacks and whether the original link survives |
| Native UI | Register a temporary Settings category, add one item tooltip line, preview one wearable link in dressing room | Repeat tooltip rebuild, use an uncached link and a non-wearable item; record API or template gaps |
| Location | Discover one item outdoors and one inside a dungeon | Compare stable map/instance identifiers with localized names |

Use `/eventtrace` if present; otherwise use a temporary event logger that records event names, argument types/values, timestamps and inventory snapshots. Some payloads may reject inspection; record the error rather than coercing a secret value. An event name alone does not prove successful item gain, quantity, source or ordering.

The probe includes an opt-in event logger for this purpose. After the updated probe files are copied into the AddOns directory and the client is reloaded, run `/fpt clear` to discard saved test traces, `/fpt start loot` (replace `loot` with a short scenario name), `/fpt snap before`, perform one case, `/fpt snap after`, then `/fpt stop` and `/reload` to flush the records to the probe's account SavedVariables file. Keep one scenario name per case. The logger records selected event names, elapsed client time and printable arguments, retaining at most 500 records. `/fpt snap <label>` records total stack quantities in bags 0–4 by item ID; `/fpt bank <label>` records aggregate quantities across `-1` and bank indexes `5`–`11`, plus each index's slot count. These do not prove equipment or other storage scope. The logger records `<inaccessible>` if an argument cannot be stringified. The raw trace may contain other players' names; redact those before sharing. Unsupported event registrations print a diagnostic at startup and should be reported.

The next probe revision also records `LOOT_SOURCE_SLOT` when a loot window opens, using the actual slot link and `GetLootSourceInfo` return values. For native UI, it registers a temporary **Forever Capability Probe** category under in-game AddOns settings with one SavedVariables-backed checkbox. Toggle it, run `/fpu status`, reload, and confirm the value remains. Run `/fpu tooltip on`, hover an item in a bag or chat link, and check that a single `Forever capability probe` line appears without an error or repeated lines. Run `/fpu tooltip off` afterward. Preview one wearable item with the native dressing room and report whether it opens and displays the model. These actions test behavior beyond the `/dump` function checks.

## Report back to the ticket

For each future gate, state **pass**, **fail**, or **unrun**, the build and locale, the exact steps, observed output, and any reproduction trace or screenshot. Keep uncertainty explicit. This ticket is closed with the unrun controls listed above; release-build checks follow [the release plan](https://github.com/ernestasgr/azeroth-ledger/issues/8).
