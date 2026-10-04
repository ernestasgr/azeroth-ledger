-- Synthetic, anonymous account data. Only a handful of items are currently held.
local function fixture(count)
    local raw = {
        schema = 2,
        records = {},
        areas = {},
        retention = { gains = 5000, transfers = 2000, vendor = 2000 },
        journal = { nextSequence = 9001, gains = {} },
        vendor = { nextID = 2001, actions = {}, journal = {} },
        exchange = { nextID = 2001, actions = {}, journal = {} },
    }
    for index = 1, count do
        local key = tostring(10000 + index) .. ":0"
        local link = "|Hitem:" .. (10000 + index) .. "::::::::|h[Item " .. string.format("%05d", index) .. "]|h"
        raw.records[key] = {
            key = key,
            itemID = 10000 + index,
            firstSeen = 1000,
            lastSeen = 1000,
            firstSeenUnits = 1,
            totalGained = 2,
            firstGained = 1001,
            lastGained = 1001,
            links = { link, (link:gsub("::::::::", ":1:::::::")) },
            characters = { -- Character first check is independent of account gains.
                { name = "Fixture", realm = "Test", firstSeen = 1000, lastSeen = 1000, firstSeenUnits = 1 },
            },
            observations = {
                {
                    character = "Fixture",
                    realm = "Test",
                    area = "bags",
                    quantity = index <= 5 and 1 or 0,
                    seenAt = 1000,
                },
            },
            gains = {
                {
                    id = "fixture:" .. index,
                    quantity = 2,
                    at = 1001,
                    character = "Fixture",
                    realm = "Test",
                    level = 1,
                    place = "Test zone",
                    method = "Looted",
                    source = { kind = "mob", guid = "Creature-0-0-0-0-" .. index .. "-0" },
                },
            },
        }
        if index <= 5000 then
            raw.journal.gains[index] = { id = "fixture:" .. index, key = key, at = 1001, sequence = index }
        end
        if index <= 2000 then
            raw.vendor.journal[index] = {
                id = index,
                key = key,
                at = 1001,
                quantity = 1,
                kind = "sale",
                character = "Fixture",
                realm = "Test",
                sequence = 5000 + index,
            }
            raw.exchange.journal[index] = {
                id = index,
                key = key,
                at = 1001,
                quantity = 1,
                channel = "mail",
                sender = "Fixture",
                senderRealm = "Test",
                recipient = "Alt",
                recipientRealm = "Test",
                sequence = 7000 + index,
            }
        end
    end
    raw.areas["Test:Fixture:bags"] = { character = "Fixture", realm = "Test", seenAt = 1000, complete = true }
    return raw
end
local _, companion = ...
if companion then
    companion.performanceFixture = fixture
end
return fixture
