local load = assert(loadfile("tests/support/addon.lua"))()
-- Long single-item histories: confirmed gains and tooltips stay off lifetime
-- history, and failed saves leave settlement retryable.
local addon = load.addon("Presentation")
date = os.date

local repeated = {}
assert(loadfile("AzerothLedger_Tests/PerformanceFixture.lua"))("Tests", repeated)
local instructions

for _, gainCount in ipairs({ 5000, 50000 }) do
    local acquisitionRaw = repeated.repeatedFixture(gainCount, 5000)
    local acquisition = addon.Schema.open(acquisitionRaw, function(value)
        acquisitionRaw = value
    end)
    assert(acquisition:setCharacter("Fixture", "Test"))
    local gainActor = { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }
    assert(
        acquisition:command(
            "rewardReceipt",
            { key = "10001:0", quantity = 1, method = "Crafted", context = { kind = "recipe", id = 123 } },
            1001 + gainCount,
            gainActor
        )
    )
    instructions = 0
    debug.sethook(function()
        instructions = instructions + 1000
    end, "", 1000)
    assert(acquisition:scan({
        character = "Fixture",
        realm = "Test",
        area = "bags",
        seenAt = 1002 + gainCount,
        complete = true,
        items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = gainCount + 1 } },
    }))
    debug.sethook()
    print("confirmed acquisition instructions", gainCount, instructions)
    assert(instructions < 250000, "Confirmed acquisition traversed lifetime history: " .. instructions)
    assert(acquisition:breakdown("10001:0").methods.Crafted == 1)
    assert(addon.Schema.open(acquisitionRaw, function() end):diagnostic().kind == "healthy")
    instructions = 0
    debug.sethook(function()
        instructions = instructions + 1000
    end, "", 1000)
    local tooltip = addon.Presentation.line(acquisition, "|Hitem:10001::::::::|h[Item 00001]|h", "Fixture", "Test")
    debug.sethook()
    assert(
        instructions < 250000 and tooltip:find("Crafted", 1, true),
        "Tooltip traversed lifetime history: " .. instructions
    )
    print("tooltip instructions", gainCount, instructions)
end

local retryRaw = repeated.repeatedFixture(5000, 5000)
local failGainSave = false
local retryStore
retryStore = addon.Schema.open(retryRaw, function(value)
    if failGainSave then
        assert(retryStore:find("10001:0").totalGained == 5000)
        assert(#retryStore:find("10001:0").gains == 5000)
        error("gain save failed")
    end
    retryRaw = value
end)
assert(retryStore:setCharacter("Fixture", "Test"))
assert(
    retryStore:command(
        "rewardReceipt",
        { key = "10001:0", quantity = 3, method = "Crafted", context = { kind = "recipe", id = 123 } },
        6001,
        { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }
    )
)
failGainSave = true
local retrySnapshot = {
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 6002,
    complete = true,
    items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 5001 } },
}
assert(not pcall(retryStore.scan, retryStore, retrySnapshot))
assert(retryStore:find("10001:0").totalGained == 5000 and #retryStore:journal() == 5002)
assert(#retryRaw.records["10001:0"].gains == 5000)
failGainSave = false
assert(retryStore:scan(retrySnapshot))
assert(retryStore:find("10001:0").totalGained == 5001)
retrySnapshot.seenAt, retrySnapshot.items[1].quantity = 6003, 5003
assert(retryStore:scan(retrySnapshot))
assert(retryStore:breakdown("10001:0").methods.Crafted == 3)
assert(retryStore:journal()[1].contributions[1].quantity == 3 and #retryStore:journal() == 5002)
assert(addon.Schema.open(retryRaw, function() end):diagnostic().kind == "healthy")

for _, channel in ipairs({ "vendor", "mail", "loot" }) do
    local failureRaw = repeated.repeatedFixture(5000, 5000)
    local failingSave = false
    local failureStore = addon.Schema.open(failureRaw, function(value)
        if failingSave then
            error("failed " .. channel .. " save")
        end
        failureRaw = value
    end)
    assert(failureStore:setCharacter("Fixture", "Test"))
    local actor = { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }
    local link = "|Hitem:10001::::::::|h[Item 00001]|h"
    if channel == "vendor" then
        assert(
            failureStore:command(
                "vendorAction",
                { kind = "purchase", key = "10001:0", itemID = 10001, link = link, quantity = 1 },
                6001,
                actor
            )
        )
        assert(failureStore:command("vendorReceipt", { key = "10001:0", quantity = 1 }, 6001, actor))
    elseif channel == "mail" then
        local id = assert(failureStore:command("exchangeIntent", {
            channel = "mail",
            direction = "in",
            key = "10001:0",
            itemID = 10001,
            link = link,
            quantity = 1,
            peerName = "Outside",
            peerRealm = "Test",
        }, 6001, actor))
        assert(failureStore:command("exchangeConfirm", { channel = "mail", direction = "in", ids = id }, 6001, actor))
    else
        assert(failureStore:scan({
            character = "Fixture",
            realm = "Test",
            area = "equipped",
            seenAt = 6000,
            complete = true,
            items = {},
        }))
        assert(failureStore:command("lootOpen", {
            slots = {
                {
                    key = "10001:0",
                    quantity = 1,
                    source = { kind = "mob", guid = "Creature-0-0-0-0-123-0", name = "Fixture mob" },
                },
            },
        }, 6001, { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }))
        assert(failureStore:command("lootReceipt", { key = "10001:0", quantity = 1 }, 6001, actor))
    end
    local snapshot = {
        character = "Fixture",
        realm = "Test",
        area = "bags",
        seenAt = 6002,
        complete = true,
        items = { { itemID = 10001, link = link, quantity = 5001 } },
    }
    failingSave = true
    assert(not pcall(failureStore.scan, failureStore, snapshot))
    assert(failureStore:find("10001:0").totalGained == 5000 and #failureRaw.records["10001:0"].gains == 5000)
    failingSave = false
    instructions = 0
    debug.sethook(function()
        instructions = instructions + 1000
    end, "", 1000)
    assert(failureStore:scan(snapshot))
    debug.sethook()
    assert(instructions < 250000, "Confirmed " .. channel .. " scan exceeded budget: " .. instructions)
    assert(failureStore:find("10001:0").totalGained == 5001, "Retry lost the " .. channel .. " gain")
    assert(addon.Schema.open(failureRaw, function() end):diagnostic().kind == "healthy")
end

-- A receipt can arrive after the quantity scan; failed settlement must remain retryable.
local lateRaw = repeated.repeatedFixture(5000, 5000)
local lateFail = false
local lateStore = addon.Schema.open(lateRaw, function(value)
    if lateFail then
        error("late receipt save failed")
    end
    lateRaw = value
end)
assert(lateStore:setCharacter("Fixture", "Test"))
assert(lateStore:scan({
    character = "Fixture",
    realm = "Test",
    area = "equipped",
    seenAt = 6000,
    complete = true,
    items = {},
}))
assert(lateStore:command("lootOpen", {
    slots = {
        {
            key = "10001:0",
            quantity = 1,
            source = { kind = "mob", guid = "Creature-0-0-0-0-123-0", name = "Fixture mob" },
        },
    },
}, 6001, { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }))
assert(lateStore:scan({
    character = "Fixture",
    realm = "Test",
    area = "bags",
    seenAt = 6002,
    complete = true,
    items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 5001 } },
}))
local lateReceipt, lateActor = { key = "10001:0", quantity = 1 }, { character = "Fixture", realm = "Test" }
lateFail = true
assert(not pcall(lateStore.lootReceipt, lateStore, lateReceipt, 6003, lateActor))
assert(lateStore:find("10001:0").totalGained == 5000 and #lateRaw.records["10001:0"].gains == 5000)
lateFail = false
instructions = 0
debug.sethook(function()
    instructions = instructions + 1000
end, "", 1000)
assert(lateStore:command("lootReceipt", lateReceipt, 6003, lateActor))
debug.sethook()
assert(instructions < 250000 and lateStore:find("10001:0").totalGained == 5001)
print("performance_history_spec: confirmed gains, tooltips and retryable settlement passed")
