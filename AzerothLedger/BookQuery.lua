local _, addon = ...
local BookQuery = {}

local fields = {
    "view",
    "search",
    "category",
    "character",
    "realm",
    "ownership",
    "quality",
    "method",
    "sort",
    "action",
    "dateFrom",
    "dateTo",
    "dateRange",
    "foundOnce",
    "place",
    "placeKind",
    "historyKey",
    "source",
}

local function sameFilter(left, right)
    for _, field in ipairs(fields) do
        if left[field] ~= right[field] then
            return false
        end
    end
    return true
end

local function copyFilter(filter)
    local result = {}
    for _, field in ipairs(fields) do
        result[field] = filter[field]
    end
    return result
end

-- Own the query lifecycle, including input snapshots and invalidation during
-- cooperative work. The book only consumes completed, current results.
---@param api table
function BookQuery.new(api)
    local session = {}
    local currentStore, currentCharacter, currentRealm, currentFilter
    local revision, job, metadataPending

    local function start(store, character, realm, filter)
        currentStore, currentCharacter, currentRealm = store, character, realm
        currentFilter, revision, metadataPending = copyFilter(filter), store:revision(), false
        if currentFilter.view == "Evidence" then
            job = addon.Work.start(api, "Evidence query", function(pause)
                return addon.Collection.evidenceQuery(store, currentFilter, pause)
            end)
        elseif currentFilter.view == "Journal" then
            job = addon.Work.start(api, "Journal query", function(pause)
                local rows = addon.Journal.query(store, currentFilter, pause)
                local bySequence, positions, loading, items = {}, {}, 0, {}
                for index, row in ipairs(rows) do
                    local item = items[row.key]
                    if not item then
                        local record = store:describe(row.key)
                        item = { record = record, metadata = addon.Client.itemMetadata(api, record) }
                        items[row.key] = item
                    end
                    row.record, row.metadata = item.record, item.metadata
                    row.recorded = row.quantity
                    if row.metadata.loading then
                        loading = loading + 1
                    end
                    bySequence[row.sequence], positions[row.sequence] = row, index
                    pause()
                end
                return {
                    rows = rows,
                    categories = {},
                    places = {},
                    loading = loading,
                    matchedCount = #rows,
                    discoveryCount = store:count(),
                    bySequence = bySequence,
                    positions = positions,
                }
            end)
        else
            job = addon.Collection.startQuery(api, store, character, realm, currentFilter, function(record)
                return addon.Client.itemMetadata(api, record)
            end)
        end
    end

    ---@param store ALStore
    ---@param character string
    ---@param realm string
    ---@param filter AzerothLedgerCollectionFilter
    ---@return table? result
    ---@return boolean pending
    function session.step(_self, store, character, realm, filter)
        if
            not job
            or currentStore ~= store
            or currentCharacter ~= character
            or currentRealm ~= realm
            or not sameFilter(currentFilter, filter)
            or (job.done and (revision ~= store:revision() or metadataPending))
        then
            start(store, character, realm, filter)
        end
        local result = job:step()
        if not result then
            return nil, true
        end
        if revision ~= store:revision() or metadataPending then
            -- Finish a running job before replacing it, so event bursts cannot
            -- perpetually restart the same first frame. Never publish stale rows.
            start(store, character, realm, filter)
            return nil, true
        end
        return result, false
    end

    local inspection, inspectionStore, inspectionKey, inspectionScope, inspectionRevision
    local inspectionCharacter, inspectionRealm
    function session.inspect(_self, store, key, character, realm, scope)
        if not key then
            return nil, false
        end
        if
            not inspection
            or inspectionStore ~= store
            or inspectionKey ~= key
            or inspectionCharacter ~= character
            or inspectionRealm ~= realm
            or not sameFilter(inspectionScope, scope)
            or inspectionRevision ~= store:revision()
        then
            inspectionStore, inspectionKey = store, key
            inspectionCharacter, inspectionRealm = character, realm
            inspectionScope, inspectionRevision = copyFilter(scope), store:revision()
            inspection = addon.Work.start(api, "Item details", function(pause)
                return addon.Collection.inspect(store, key, character, realm, inspectionScope, pause)
            end)
        end
        local result = inspection:step()
        if inspectionRevision ~= store:revision() then
            inspection = nil
            return nil, true
        end
        return result, not inspection.done
    end

    function session.metadataChanged(_self)
        metadataPending = true
    end

    return session
end

addon.BookQuery = BookQuery
