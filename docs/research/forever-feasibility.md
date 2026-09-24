# World of Warcraft: Forever feasibility research

Research date: 25 September 2026. This records prerequisite facts and open checks, not an implementation specification. No client was run and no compatibility claim has been validated in-game.

## Product and target

Blizzard describes **World of Warcraft: Forever** as a permanent new home alongside modern and Classic WoW: original continents, progression to level 60, and continuing new content. Its announced launch is 4 November 2026; beta began 17 September. This is an official Blizzard product, not a private server. [Blizzard announcement](https://news.blizzard.com/en-us/article/24302093/carve-a-new-path-with-world-of-warcraft-forever)

The public product page specifies beta availability through 21 October 2026. [Blizzard product page](https://worldofwarcraft.blizzard.com/th-th/forever)

**Exact current build remains unverified.** The GamepadSpeak author reports testing against Forever beta build **69913**, interface **16001**. This is a useful observed target, not proof that it is today's latest build or a stable release interface. [GamepadSpeak source and author documentation](https://github.com/kubeden/gps)

## Persistence is the first feasibility gate

Two addon authors report that the beta writes SavedVariables but fails to restore them on reload/login. GamepadSpeak names the build above. ForeverSVFix exists specifically to work around that loader failure; its author reports in-game validation on Linux/Wine and says native Windows/macOS validation is outstanding. These are firsthand addon-author reports, not an official Blizzard acknowledgement or our reproduction. [GamepadSpeak](https://github.com/kubeden/gps), [ForeverSVFix](https://github.com/nobewayo/ForeverSVFix)

**Implication:** before promising a permanent journal on beta, verify a small SavedVariables marker across `/reload`, character changes, and a complete client restart on the user's actual build. Do not adopt external patchers or filesystem-link workarounds as a silent dependency. A report of this failure alone does not establish that every subsequent beta build still has it.

## Recorder APIs: evidence and boundaries

Blizzard-generated Mainline API documentation, mirrored as source in Gethe/wow-ui-source, supports the proposed approach. These are Mainline source facts; the exact Forever export still needs comparison.

| Capability | Source evidence | Remaining verification |
| --- | --- | --- |
| Inventory reconciliation | `C_Container.GetContainerItemInfo`, `GetContainerItemLink`, and `BAG_UPDATE_DELAYED` are documented. [Container source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua) | Confirm bag/bank container indexes, scope and availability in Forever. |
| Loot context | `LOOT_OPENED` includes `autoLoot` and `isFromItem`; `LOOT_CLOSED` is documented. `QUEST_LOOT_RECEIVED` carries quest ID, link and quantity. [Loot source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/LootDocumentation.lua) | Trace ordinary, area and container loot, group awards, source identifiers, event order and duplicates. |
| Chat acquisition evidence | `CHAT_MSG_LOOT` is documented with message text and identity fields. Unlike nearby restricted chat events, that declaration lacks `SecretInChatMessagingLockdown`. [Chat source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua) | Verify self-versus-party messages, localization and crafting/quest message variants; a chat event name alone does not establish corpse-loot provenance. |
| Uncached item data | `C_Item.RequestLoadItemDataByID` and `ITEM_DATA_LOAD_RESULT(itemID, success)` are documented. [Item source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua) | Confirm load failures/retries and retain the original hyperlink before resolving display metadata. |

These declarations support a feasibility hypothesis; they do **not** prove that every requested value is unrestricted in every Forever execution context. Do not use combat-sensitive APIs as a substitute for missing loot context.

## WoWUnit and presentation

The intended modern **WoWUnit** is Jaliborc's framework. Its source documents event-triggered test groups, assertions, temporary mocks, and optional integration with `## OptionalDeps: WoWUnit`. An older, separately owned project named wowUnit also exists; pin the intended dependency explicitly. [Jaliborc WoWUnit](https://github.com/Jaliborc/WoWUnit), [older Mirroar wowUnit](https://github.com/Mirroar/wowUnit)

The freshly retrieved WoWUnit TOC lists version **12.1** and interfaces `120100, 50504, 40402, 30404, 20506, 16001, 11509`, including Forever's reported `16001`. This supersedes the older 12.0.1 TOC returned during the initial search. The author now declares the relevant interface support, but declaration is not our in-game validation: execute a sample assertion and mock-restoration test on the target Forever build. [WoWUnit TOC](https://raw.githubusercontent.com/Jaliborc/WoWUnit/master/WoWUnit.toc)

**Presentation recommendation, pending client inspection:** reuse the actual Forever client's native frame templates, fonts, textures, scroll widgets, tooltips, Settings registration, and dressing-room facilities. Do not infer a 2004 Classic visual style merely from the level-60 setting. Mainline source defines `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnCategory`, `Settings.OpenToCategory`, and `TooltipDataProcessor.AddTooltipPostCall`. These provide specific candidates to inspect, not a Forever compatibility guarantee. [Settings implementation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua), [tooltip implementation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)

This research did not obtain a verified Forever UI source export. Exact template names, Settings registration, tooltip mutation restrictions and dressing-room support remain open.

## Explicit feature gaps and bounded client checks

The following are unresolved implementation evidence, not missing product requirements. No row should be marked verified solely because its candidate API exists in Mainline.

| Feature | Evidence boundary | Bounded Forever check |
| --- | --- | --- |
| Quest rewards | Mainline documents `QUEST_LOOT_RECEIVED`; Forever reward coverage and ordering are untested. | Complete one fixed-reward and one choice-reward quest. Correlate quest ID, link and quantity against chat and bag events; require one acquisition per reward. |
| Crafting | Mainline exposes `C_TradeSkillUI`, but this research has not established Forever's result event contract or profession coverage. [TradeSkillUI source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua) | Craft once and then a short batch; cancel a cast. Identify the actual success evidence, recipe identifier, output quantity and duplicate chat/bag notifications. A started cast must not count as an acquisition. |
| Vendor | Forever purchase-completion evidence has not been researched or tested. Merchant proximity alone cannot prove purchase. | Buy one item, buy a stack, fail a purchase with full bags, and sell/buy back an item. Establish successful purchase correlation and distinguish buyback from new discovery. |
| Trade | Forever trade event payloads and completion semantics are unverified. | Complete an incoming item trade, cancel another, and receive the same item while another source event is pending. Verify actual completion, counterparty identity and transfer correlation. |
| Mail | Forever attachment and retrieval event contracts are unverified. | Retrieve one attachment, retrieve a stack, open mail without taking it, and retrieve an alt-sent item. Compare sender/attachment evidence with inventory changes; opening mail alone must not count. |
| Bank and ownership | Mainline has `C_Bank`, but Forever container types, readable scopes and closed-bank access have not been established. [Bank source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/BankDocumentation.lua) | Scan before/while/after opening the bank; transfer the same item in both directions; relog an alt. Record freshness by scope and retain Unknown for inaccessible or unscanned storage. |
| Mob, boss or container source | Loot-open context exists; exact source GUID/name resolution and multi-source attribution are unverified. | Trace one corpse, one boss, an item container and area loot from two corpses. Only attach a source where the payload links it to that item; preserve unknown/ambiguous source otherwise. |
| In-game Settings | Mainline registration functions are confirmed above; Forever behavior is unverified. | Register one category with a toggle and bounded history-limit setting; change them in-game and verify persistence after reload/restart. |
| Tooltip discovery line | Mainline post-processing exists; Forever safety, available link data and repeated rebuild behavior are unverified. | Inspect bag, equipment and chat-link tooltips, then uncached and repeated tooltip rebuilds. Require one correctly matched line, no duplicate lines or forbidden-data errors, and honest Observed wording. |
| Dressing-room gallery | No current Forever dressing-room source or callable contract was verified. | Preview one owned and one historical wearable hyperlink with the native UI; test an uncached link and non-wearable item. Confirm model loading, supported race/body presentation and graceful unsupported-item handling. |
| Zone/dungeon grouping | Discovery-based grouping is settled; exact Forever map/instance identity APIs are unverified. | Record a discovery in the open world and inside a dungeon; verify stable identifiers separately from localized display names. Do not imply undiscovered-item completion totals. |

## Bounded validation before implementation commitments

1. Capture `GetBuildInfo()`, client product identity and exported UI/API files from the intended Forever installation; record the exact supported build.
2. Pass the persistence marker test and run a WoWUnit assertion in-client.
3. Trace one acquisition each for corpse loot, quest reward, crafting, vendor, trade and mail. Confirm event payloads, localization, correlation and double-count prevention.
4. Trace bag-bank transfers, bag rearrangement, equipping, sale/buyback and alt mail. Ownership movement must not automatically become acquisition.
5. Capture real suffix/bonus-bearing links. Verify which actual fields encode intrinsic variants versus mutable instance state; preserve the full raw link separately from the canonical collection key.
6. Verify native Settings, tooltip augmentation and a minimal dressing-room preview against Forever's UI using the checks above.

## Settled product decisions and remaining semantics

The planning interview settled these requirements; they are user decisions, not API findings:

- Use native Lua, with no Effect or TypeScript runtime/toolchain requirement.
- Share collection data across all locally recorded characters and realms in the account scope. This does not claim automatic Battle.net-wide or cross-computer synchronization.
- Initial scans create Observed discoveries without initial discovery toasts. Historical acquisition date and method remain unknown; observation time is separate.
- Distinguish intrinsic gear variants and preserve full raw item links. Canonical field interpretation still requires real Forever examples.
- Represent stale ownership explicitly, with freshness and Unknown where current ownership cannot be established.
- Start zone and dungeon collections from recorded discoveries, without claiming a complete catalogue of possible drops.

Remaining semantics to resolve in implementation specifications: whether a proven alt transfer increments the receiving character's acquisition totals while leaving account discovery unchanged, and whether “only found once” means one acquisition event or one unit. Internal bag/bank movement must not count as a fresh acquisition. These distinctions should have explicit WoWUnit cases independently of client adapter verification.
