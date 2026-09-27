# Azeroth Ledger

Azeroth Ledger keeps a Collection of items seen on your characters and a Journal of recent item activity.

## Language

**Collection**:
One entry for each item or built-in gear variant seen across the characters and realms this addon has recorded on your WoW account. Character and realm filters narrow the list. This is the addon's list, not the game's Collections window.

**Journal**:
A recent log of items gained, moves between your own characters, and vendor sales, refunds, or buybacks. Each entry keeps its quantity. Removing old entries does not change lifetime counts.

**Gear variant**:
A built-in version of gear, such as a sword "of the Bear" or one with another built-in bonus. Enchants, gems, durability, and the character holding it do not make a new variant. Keep every full item link seen.

**Discovered**:
An item or gear variant added to the account's Collection for the first time. Each character also has a first-seen date. Finding an item in an initial bag or bank scan counts as a discovery, but does not show a new-item toast or tell us when it was gained.

**Seen**:
Found in a character's bags, bank, or equipped gear without knowing how or when it was gained. Keep the first and latest times seen separate from the first and latest confirmed gain dates. A later gain does not change the earlier Seen record.

**Looted**:
Personally looted by your character, with a matching item gain. Another player's loot or a nearby mob is not enough evidence.

**Obtained**:
Confirmed as gained through another means, such as a quest reward, craft, purchase, mail, or trade. The exact means can remain unknown when the item gain is clear.

**Total gained**:
The number of units confirmed gained from outside your recorded characters, minus confirmed refunds. Items already present in an initial scan add zero. Moving an item between your bags, bank, equipped gear, or alts adds zero. Gaining it again after disposal counts, except when buying back the same sold item.

**Transfer**:
A known move between your own characters. Show it in the Journal with sender and recipient when known, without adding to Total gained or the discovery count.

**Vendor sale, refund, and buyback**:
Selling an item leaves Total gained unchanged. A completed refund removes the uniquely linked purchase from Total gained. Buying back a sold item restores it without a new gain. Keep all three actions in the Journal.

**Last seen**:
Where, when, and how many of an item the addon last checked on a character. A partial check can show that an item is present; proving it absent requires complete checks of relevant bags, bank, and gear. A closed bank or an offline character can leave current ownership unknown.

**Historical only**:
An item seen before but absent from complete checks of the selected characters' relevant bags, bank, and equipped gear. This means absent as of those check dates. If needed storage could not be checked, the result is Unknown.

**Source**:
A mob, boss, chest, or other container tied to the specific looted item by evidence. A nearby mob or a loot message alone is not enough. Record a quest, vendor, or player separately when known; leave the source unknown when the game does not prove it.

**Vendor source**:
The merchant's name observed during the purchase. If the merchant's identity was not captured, the gain remains a Vendor gain with an unnamed source. A later refund reduces that purchase's source total.

**Found once**:
Exactly one confirmed unit gained from outside your recorded characters, with none seen beforehand. An item known only from an initial scan does not qualify.

**Zone or dungeon group**:
Items linked to a confirmed gain in that zone or dungeon, or to a known dungeon source. It is not a list of every possible drop. Scanning a bag there does not establish where its items came from.
