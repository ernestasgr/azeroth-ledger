local _, companion = ...
local addon = AzerothLedger
local tests = WoWUnit("AzerothLedgerPerformance")

function tests.LargeLedgerKeepsLinksSourcesAndLifetimeCountsAfterPruning(_self)
    local raw = companion.performanceFixture(10000)
    local store = addon.Schema.open(raw, function(value)
        raw = value
    end)
    WoWUnit.AreEqual("healthy", store:diagnostic().kind)
    WoWUnit.AreEqual(10000, store:count())
    WoWUnit.IsTrue(
        store:scan({ character = "Fixture", realm = "Test", area = "bags", seenAt = 1002, complete = true, items = {} })
    )
    for _, category in ipairs({ "gains", "vendor", "transfers" }) do
        WoWUnit.IsTrue(store:setRetention(category, 0))
    end
    local restored = addon.Schema.open(raw, function() end)
    WoWUnit.AreEqual(0, #restored:journal())
    WoWUnit.AreEqual(3, restored:breakdown("20000:0").recorded)
    WoWUnit.AreEqual(2, restored:breakdown("20000:0").sources["Mob #10000"])
    WoWUnit.AreEqual(2, #restored:find("20000:0").links)
end

function tests.RepeatedItemsKeepPermanentFactsAndCorrectionReferences(_self)
    local raw = companion.repeatedFixture(5000, 5000)
    local store = addon.Schema.open(raw, function(value)
        raw = value
    end)
    WoWUnit.AreEqual("healthy", store:diagnostic().kind)
    WoWUnit.AreEqual(5002, #store:journal())
    WoWUnit.IsTrue(
        store:scan({ character = "Fixture", realm = "Test", area = "bags", seenAt = 7000, complete = true, items = {} })
    )
    WoWUnit.AreEqual(2, #store:find("10001:0").observations)
    for _, category in ipairs({ "gains", "vendor", "transfers" }) do
        WoWUnit.IsTrue(store:setRetention(category, 0))
    end
    local restored = addon.Schema.open(raw, function() end)
    WoWUnit.AreEqual(0, #restored:journal())
    WoWUnit.AreEqual(5001, restored:breakdown("10001:0").recorded)
    WoWUnit.AreEqual(5000, restored:breakdown("10001:0").sources["Fixture mob"])
    WoWUnit.AreEqual(1001, restored:find("10001:0").firstGained)
    WoWUnit.AreEqual(6000, restored:find("10001:0").lastGained)
    WoWUnit.IsTrue(restored:correctGain({
        id = "old-proof",
        key = "10001:0",
        gainID = "repeated:1:1",
        quantity = 1,
        fromMethod = "Looted",
        fromSource = { kind = "mob", guid = "Creature-0-0-0-0-123-0", name = "Fixture mob" },
        method = "Quest",
        context = { kind = "quest", id = 123 },
    }))
    WoWUnit.AreEqual(0, #restored:journal())
    WoWUnit.AreEqual(4999, restored:breakdown("10001:0").methods.Looted)
    WoWUnit.AreEqual(1, restored:breakdown("10001:0").methods.Quest)
end

-- Opens anonymous synthetic data. The production store and SavedVariables are untouched.
SLASH_AZEROTHLEDGERPERFORMANCE1 = "/alperf"
SlashCmdList.AZEROTHLEDGERPERFORMANCE = function(message)
    local repeated = message and message:find("repeated", 1, true)
    local zero = message and message:find("zero", 1, true)
    addon.Work.timings = {}
    local raw = addon.Work.measure(_G, "Fixture build", function()
        return repeated and companion.repeatedFixture(50000, zero and 0 or 5000, 3)
            or companion.performanceFixture(10000)
    end)
    local store = addon.Work.measure(_G, "Fixture store load", function()
        return addon.Schema.open(raw, function() end)
    end)
    if zero then
        for _, category in ipairs({ "gains", "vendor", "transfers" }) do
            store:setRetention(category, 0)
        end
    end
    addon.Work.measure(_G, "Fixture Journal", function()
        return store:journal()
    end)
    addon.Work.measure(_G, "Fixture changed scan", function()
        return store:scan({
            character = "Fixture",
            realm = "Test",
            area = "bags",
            seenAt = 60000,
            complete = true,
            items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 50001 } },
        })
    end)
    if repeated then
        addon.Work.measure(_G, "Fixture confirmed gain scan", function()
            store:command(
                "rewardReceipt",
                { key = "10001:0", quantity = 1, method = "Crafted", context = { kind = "recipe", id = 123 } },
                60001,
                { character = "Fixture", realm = "Test", level = 1, place = "Test zone" }
            )
            return store:scan({
                character = "Fixture",
                realm = "Test",
                area = "bags",
                seenAt = 60002,
                complete = true,
                items = { { itemID = 10001, link = "|Hitem:10001::::::::|h[Item 00001]|h", quantity = 50002 } },
            })
        end)
        addon.Work.measure(_G, "Fixture tooltip", function()
            return addon.Presentation.line(store, "|Hitem:10001::::::::|h[Item 00001]|h", "Fixture", "Test")
        end)
    end
    addon.Book.open(_G, store, "Fixture", "Test")
    print(
        "Azeroth Ledger: "
            .. (repeated and "3 synthetic items with 50,000 gains each." or "10,000 synthetic items.")
            .. " Use /al profile for timings; /alperf repeated or /alperf repeated zero for long histories."
    )
end
