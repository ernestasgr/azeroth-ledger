# Changelog

## 1.0.5

- Looting several corpses in quick succession now keeps the creature as each item's Source. Before, it showed as Unknown.
- An item you win in a group loot roll now keeps its Source even when a loot window couldn't be read in the meantime. Before, it showed as Unknown.
- Picking up items and other bag changes are about three times faster, so looting hitches less.

## 1.0.4

- /azledger and /azerothledger now open the ledger too, for when another addon also uses /al.
- Loot is no longer missed when the game hides details about the corpse or item. It's recorded without the details that couldn't be read.
- An item you win in a group loot roll now keeps the creature it dropped from as its Source. Before, it showed as Unknown.
- A creature looted during combat now shows its name if you saw it by target, mouseover or nameplate earlier in the session. Before, it showed as "Mob #" and a number.
- An item bought at auction no longer says its source is Unknown in its details.
- The addon's memory use no longer keeps climbing while nothing is happening.

## 1.0.3

- Conjured food and water, and items a spell gives you such as scrolls from Comprehend Scroll, now show that spell as their Source. Before, it showed as Unknown.
- A scroll you make with Comprehend Scroll while a vendor window is open now counts as Obtained. Before, it was taken for a purchase and ended up in the review list.
- Items you already have keep an Unknown Source. After updating, don't go back to an earlier version: it reports a Collection that names a spell as a Source as damaged.

## 1.0.2

- Looting an item from a corpse you had already opened, for example after making room in your bags, now keeps the creature as its Source. Before, it showed as Unknown.

## 1.0.1

- Loot you pick up right after checking your mail, trading, or using the guild bank now counts as Looted. Before, it was missed and ended up in the review list.
- Right-clicking an item a vendor won't buy no longer records a sale.

## 1.0.0

- First release.
