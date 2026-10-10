local _, addon = ...
local BookQuery = {}

local fields = {
    "view",
    "search",
    "category",
    "character",
    "realm",
    "historical",
    "foundOnce",
    "place",
    "placeKind",
    "historyKey",
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
                local rows = addon.Journal.query(store, currentFilter.search, pause, currentFilter.historyKey)
                local bySequence, positions = {}, {}
                for index, row in ipairs(rows) do
                    row.record = store:find(row.key)
                    row.metadata = addon.Client.itemMetadata(api, row.record)
                    row.recorded = row.quantity
                    bySequence[row.sequence], positions[row.sequence] = row, index
                    pause()
                end
                return {
                    rows = rows,
                    categories = {},
                    places = {},
                    loading = 0,
                    matchedCount = 0,
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

    function session.metadataChanged(_self)
        metadataPending = true
    end

    return session
end

addon.BookQuery = BookQuery
