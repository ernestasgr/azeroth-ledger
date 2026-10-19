# Azeroth Ledger

Ever wondered which alt has that recipe? Or whether that ring dropped from a boss or came off a vendor? Azeroth Ledger keeps track for you.

It remembers the items on your characters (bags, bank, and whatever you're wearing) and keeps notes on how new ones showed up. Type `/al` or click the book by the minimap to open it.

## What it does

**The Collection** lists every item the addon has seen on any of your characters. Browse it by category or by place, search by name, or narrow it down to one character or realm. Pick an item to see its history: when it first showed up, whether you looted it or got it another way (quest, vendor, crafting, mail, trade, guild bank...), and who or what it came from, if the game says.

**The Journal** covers recent activity, newest first: what you picked up, what you mailed to your alts, and what you sold to a vendor or bought back. Click an entry for the details.

**Tooltips** get a few extra lines: when you first saw, looted, or got the item, how many you've gained in total, and where it came from.

When you get something you've never had before, a small notification pops up. Items you already had and items moved between your own characters don't trigger it.

## Good to know

- It only knows about characters you've logged into with the addon enabled. Open your bank once on each character so it can count what's in there.
- Anything already in your bags the first time it checks counts as "found", not "gained". It doesn't know where those came from, so it doesn't pretend to.
- Counts for offline characters are from the last time you played them.
- If an item turns up and the addon can't tell how, it doesn't guess. Those go into **Review item changes**, so you can look at them yourself.
- Everything stays in your SavedVariables. Nothing is sent anywhere, and there are no library dependencies.

## Settings

Under Options → AddOns → Azeroth Ledger you can:

- pick one of ten color themes or adjust the colors yourself
- resize the window
- change how notifications look and sound, and hold them during combat
- turn the tooltip lines on or off

It also works from the keyboard: Ctrl+F to search, arrow keys to move around, Esc to close.

## Bugs and ideas

If something looks wrong, please open an issue on [GitHub](https://github.com/ernestasgr/azeroth-ledger/issues). Tell me the item and what you did to get it; that's usually enough to track it down.
