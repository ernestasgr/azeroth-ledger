local _, addon = ...

-- The public Schema API. Pure helpers live in SchemaValidate; Schema.open composes
-- one store from the kernel and the domain files, keeping one method table. Each
-- domain file declares the saved slices it owns and receives only their handles.
local V = addon.SchemaValidate

local Schema = {
    displayOptions = V.displayOptions,
    colorOptions = V.colorOptions,
    sourceText = V.sourceText,
    sourceIdentity = V.sourceIdentity,
    addSource = V.addSource,
    sourceGroups = V.sourceGroups,
    bookChoices = V.bookChoices,
    retentionOptions = V.retentionOptions,
}

---@param raw any
---@param save fun(value: AzerothLedgerData)
---@return AzerothLedgerStore
function Schema.open(raw, save)
    local Records, Preferences = addon.StoreRecords, addon.StorePreferences
    -- Exchange precedes vendor: their Journal entries take sequence numbers in this order.
    local slices = {}
    for _, list in ipairs({
        Records.slices,
        Preferences.slices,
        {
            addon.StoreEvidence.slice,
            addon.StoreLoot.slice,
            addon.StoreReward.slice,
            addon.StoreExchange.slice,
            addon.StoreVendor.slice,
        },
    }) do
        for _, slice in ipairs(list) do
            slices[#slices + 1] = slice
        end
    end
    local kernel, handles = addon.StoreKernel.open(raw, save, slices)
    local function own(list)
        local result = {}
        for _, slice in ipairs(list) do
            result[slice.name] = handles[slice.name]
        end
        return result
    end
    local store = {}
    Preferences.install(store, kernel, own(Preferences.slices))
    addon.StoreJournal.install(store, kernel)
    local evidence = addon.StoreEvidence.install(store, kernel, handles.evidence)
    Records.install(store, kernel, own(Records.slices))
    local reward = addon.StoreReward.install(store, kernel, handles.rewards)
    local loot = addon.StoreLoot.install(store, kernel, handles.loot, evidence, reward)
    local exchange = addon.StoreExchange.install(store, kernel, handles.exchange)
    local vendor = addon.StoreVendor.install(store, kernel, handles.vendor)
    -- Evidence expiry, evidence listing and check settlement all follow this order.
    local engines = {
        { name = "loot", engine = loot.engine },
        { name = "rewards", engine = reward.engine },
        { name = "vendor", engine = vendor.engine },
        { name = "exchange", engine = exchange.engine },
    }
    evidence.attach(engines)
    -- A new store is a login/reload boundary, never a continuation of a match.
    evidence.endCorrelation(0, "reload")
    local checks = {}
    for index, entry in ipairs(engines) do
        checks[index] = entry.engine
    end
    addon.StoreScan.install(store, kernel, evidence, checks)
    addon.StoreEvidence.guardCandidates(store, kernel, evidence)
    return store
end

addon.Schema = Schema
