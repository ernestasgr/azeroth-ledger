# Forever client capability check

For [Validate persistence, WoWUnit and required capabilities in the target Forever client](https://github.com/ernestasgr/azeroth-ledger/issues/9). Record observations from the actual client. Do not treat an installed build, Mainline API declaration, or mocked test as an in-client pass.

## Known local installation

On 25 September 2026, the local `World of Warcraft/_classic_beta_` installation's `.flavor.info` said `wow_classic_beta`. The root `.build.info` listed active product `wow_classic_beta`, version `1.60.1.70009`. The game was not running. `GetBuildInfo()`, interface version, runtime behavior, and whether this is the intended Forever character environment are unverified. Before preparation, the AddOns directory was empty, and no Forever capability test had been run.

The temporary probe and upstream WoWUnit are now installed in that beta's AddOns directory. WoWUnit was copied from Jaliborc/WoWUnit commit `45f9273818f1377340d624172e7a7e9cc2f247a0`, whose TOC declares version 12.1. Installation is preparation, not a test pass.

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

## Report back to the ticket

For each gate, state **pass**, **fail**, or **unrun**, the build and locale, the exact steps, observed output, and any reproduction trace or screenshot. Keep uncertainty explicit. The issue remains open until persistence, genuine in-client WoWUnit execution, required recording signals, and native UI facilities are evidenced on the intended build.
