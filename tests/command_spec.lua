local load = assert(loadfile("tests/support/addon.lua"))()
local addon = load.addon("Schema")

-- Every store write enters through store:command, which checks the action's
-- time and character once before the owning domain sees it.
local saved
local function open(raw, actor)
    saved = raw
    local store = addon.Schema.open(raw, function(value)
        saved = value
    end)
    if actor then
        assert(store:setCharacter(actor.character, actor.realm))
    end
    return store
end

local link = "|Hitem:2589::::::::|h[Linen Cloth]|h"
local key = addon.Item.key(link, 2589)
local ada = { character = "Ada", realm = "Realm", level = 5, place = "Elwynn Forest", placeKind = "zone" }
local bea = { character = "Bea", realm = "Realm", level = 7, place = "Elwynn Forest", placeKind = "zone" }
local function checked(store, actor, at)
    for _, area in ipairs({ "bags", "equipped" }) do
        assert(store:scan({
            character = actor.character,
            realm = actor.realm,
            area = area,
            seenAt = at,
            complete = true,
            items = {},
        }))
    end
end
local function opened(store, actor, at)
    return store:command("lootOpen", {
        slots = {
            { key = key, quantity = 2, source = { kind = "mob", guid = "Creature-0-1-2-3-4-5", name = "Kobold" } },
        },
    }, at, actor)
end
local function evidence(store, kind, reason)
    local count = 0
    for _, entry in ipairs(store:unresolved()) do
        if entry.kind == kind and entry.reason == reason then
            count = count + 1
        end
    end
    return count
end

-- Before login names the character, no write is accepted.
local store = open(nil)
checked(store, ada, 100)
local before = saved
assert(not opened(store, ada, 101), "a loot window before login must not be recorded")
assert(saved == before, "a write before login must leave the save untouched")

-- A rejected time writes nothing: no loot cycle, no candidate, no evidence.
store = open(nil, ada)
checked(store, ada, 100)
before = saved
for _, at in ipairs({ -1, 100.5, "100" }) do
    assert(not opened(store, ada, at), "a loot window with an unreadable time must not be recorded")
    assert(
        not store:command("lootReceipt", { key = key, quantity = 1 }, at, ada),
        "a loot receipt with an unreadable time must not be recorded"
    )
end
assert(saved == before, "an action with an unreadable time must leave the save untouched")
assert(
    not store:command("lootReceipt", { key = key, quantity = 1 }, 101, { character = "Ada" }),
    "a loot receipt without a realm must not be credited to any character"
)
assert(not store:command("noSuchWrite", {}, 101, ada), "an action no domain declares must not change the ledger")
assert(saved == before, "an action without a full character must leave the save untouched")

-- The same loot window and receipt, with a readable time, credit the item.
assert(opened(store, ada, 101), "a loot window with a readable time must be recorded")
assert(store:command("lootReceipt", { key = key, quantity = 2 }, 102, ada), "the receipt must match its loot window")
assert(store:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    seenAt = 104,
    complete = true,
    items = { { itemID = 2589, link = link, quantity = 2 } },
}))
assert(store:breakdown(key).methods.Looted == 2, "a looted item must be credited to its loot window")

-- One login plays one character. A write from any other character is refused
-- outright and leaves the save untouched; Ada's loot window still matches Ada.
store = open(nil, ada)
checked(store, ada, 200)
checked(store, bea, 200)
assert(opened(store, ada, 201), "Ada's loot window must be recorded")
before = saved
assert(
    not store:command("lootReceipt", { key = key, quantity = 2 }, 202, bea),
    "a receipt for a character not playing must not be recorded"
)
assert(saved == before, "a write from a character not playing must leave the save untouched")
assert(not store:setCharacter("Bea", "Realm"), "only a new login can play another character")
assert(store:command("lootReceipt", { key = key, quantity = 2 }, 203, ada), "Ada's own receipt must still match")
assert(store:scan({
    character = "Ada",
    realm = "Realm",
    area = "bags",
    seenAt = 204,
    complete = true,
    items = { { itemID = 2589, link = link, quantity = 2 } },
}))
assert(store:breakdown(key).methods.Looted == 2, "Ada's loot must be credited once, to Ada")
assert(store:breakdown(key, { character = "Bea", realm = "Realm" }).gained == 0, "Bea must gain nothing")

-- A reload ends every pending action: the receipt after it proves nothing.
store = open(nil, ada)
checked(store, ada, 300)
assert(opened(store, ada, 301), "the loot window before the reload must be recorded")
store = open(saved, ada)
assert(evidence(store, "loot", "reload") == 1, "a reload must end the loot window opened before it")
assert(
    not store:command("lootReceipt", { key = key, quantity = 2 }, 302, ada),
    "a receipt after a reload must not match the loot window before it"
)
assert(evidence(store, "lootReceipt", "unmatched") == 1, "a receipt after a reload must stay unmatched")
assert(not store:find(key), "a receipt after a reload must not credit the loot window before it")

print("command_spec: passed")
