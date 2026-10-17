local _, addon = ...

-- The public Schema API. Pure helpers live in SchemaValidate; Schema.open composes
-- one store from the kernel and the domain files, keeping one method table.
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
    local kernel = addon.StoreKernel.open(raw, save)
    local store = {}
    addon.StorePreferences.install(store, kernel)
    addon.StoreJournal.install(store, kernel)
    local evidence = addon.StoreEvidence.install(store, kernel)
    addon.StoreRecords.install(store, kernel)
    -- A new store is a login/reload boundary, never a continuation of a match.
    evidence.endCorrelation(0, "reload")
    local domains = {
        evidence = evidence,
        loot = addon.StoreLoot.install(store, kernel, evidence),
        exchange = addon.StoreExchange.install(store, kernel),
        vendor = addon.StoreVendor.install(store, kernel),
        reward = addon.StoreReward.install(store, kernel),
    }
    addon.StoreScan.install(store, kernel, domains)
    addon.StoreEvidence.guardCandidates(store, kernel, evidence)
    return store
end

addon.Schema = Schema
