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

-- Opens anonymous synthetic data. The production store and SavedVariables are untouched.
SLASH_AZEROTHLEDGERPERFORMANCE1 = "/alperf"
SlashCmdList.AZEROTHLEDGERPERFORMANCE = function()
    addon.Work.timings = {}
    local raw = addon.Work.measure(_G, "Fixture build", function()
        return companion.performanceFixture(10000)
    end)
    local store = addon.Work.measure(_G, "Fixture store load", function()
        return addon.Schema.open(raw, function() end)
    end)
    addon.Collection.open(_G, store, "Fixture", "Test")
    print("Azeroth Ledger: browsing 10,000 synthetic entries and 9,000 Journal rows. Use /al profile for timings.")
end
