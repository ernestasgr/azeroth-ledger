local _, addon = ...

local Collection = {}
local Wording = addon.LastSeen

Collection.evidenceQuery = addon.CollectionEvidence.query

local function stamp(seconds)
    return seconds and date("%Y-%m-%d %H:%M", seconds) or "Unknown"
end

local function matchesFilter(filterCharacter, filterRealm, name, realm)
    return (not filterCharacter or name == filterCharacter) and (not filterRealm or realm == filterRealm)
end

local storageLabels = { bags = "Bags", bank = "Bank", equipped = "Equipped" }
---@param check ALStorageCheck
---@return string
function Collection.checkText(check)
    return check.character
        .. "-"
        .. check.realm
        .. " • "
        .. storageLabels[check.area]
        .. ": "
        .. (check.observedQuantity ~= nil and ("last found " .. check.observedQuantity .. " on " .. stamp(
            check.observedAt
        )) or "not seen yet")
        .. "; latest check "
        .. (check.quantity ~= nil and tostring(check.quantity) or "Unknown")
        .. (check.at and (" on " .. stamp(check.at)) or "; not checked yet")
        .. (not check.online and " (offline; status Unknown)" or (check.quantity == nil and "; status Unknown" or ""))
end

---@class AzerothLedgerCollectionFilter: ALCountScope
---@field historyKey? string
---@field source? string Recorded source identity
---@field search? string
---@field category? string
---@field character? string
---@field realm? string
---@field ownership? 'present'|'unknown'|'historical'
---@field quality? integer|'unknown'
---@field method? string
---@field sort? 'name'|'discovered'|'gained'|'quantity'
---@field action? string
---@field dateFrom? integer Inclusive timestamp
---@field dateTo? integer Exclusive timestamp
---@field dateRange? string
---@field place? string
---@field placeKind? string
---@field view? string

---@class AzerothLedgerItemMetadata
---@field category string
---@field loading? boolean
---@field quality? integer
---@field icon? integer|string
---@field gear? boolean

---@class AzerothLedgerCollectionRow
---@field key string
---@field name string
---@field record AzerothLedgerRecord
---@field category string
---@field loading? boolean
---@field ownership string
---@field ownershipState 'present'|'unknown'|'historical'
---@field discoveredAt integer
---@field lastGained? integer
---@field metadata AzerothLedgerItemMetadata
---@field recorded? integer
---@field characterOverall? integer
---@field allCharactersOverall? integer
---@field characterCurrent? integer
---@field allCharactersCurrent? integer
---@field currentUnits? integer
---@field sourceQuantity? integer Net confirmed contribution from the selected source

---@param store ALStore
---@param character string
---@param realm string
---@param filter? AzerothLedgerCollectionFilter
---@param metadata? fun(record: AzerothLedgerRecord): AzerothLedgerItemMetadata
-- Queries are projections of permanent facts; filters never edit the ledger.
local function query(store, character, realm, filter, metadata, pause)
    filter = filter or {}
    local result =
        { rows = {}, discoveryCount = store:count(), loading = 0, places = {}, categories = {}, matchedCount = 0 }
    local places, sources, candidates = {}, {}, {}
    local cursor = store:cursor(pause)
    while true do
        local record = cursor()
        if not record then
            break
        end
        local matches = false
        local discoveredAt
        for _, seen in ipairs(record.characters) do
            if matchesFilter(filter.character, filter.realm, seen.name, seen.realm) then
                matches = true
                discoveredAt = math.min(discoveredAt or seen.firstSeen, seen.firstSeen)
            end
        end
        local methodMatches = not filter.method
            or (record.firstSeenUnits > 0 and filter.method == Wording.firstCheckMethod(record.firstSeenLater))
        local lastGained
        local sourceQuantity, recordSources = 0, {}
        for _, gain in ipairs(record.gains) do
            if matchesFilter(filter.character, filter.realm, gain.character, gain.realm) then
                local quantity = gain.quantity - (gain.refunded or 0)
                Wording.addSource(sources, gain, quantity)
                if filter.search and filter.search ~= "" then
                    Wording.addSource(recordSources, gain, quantity)
                end
                if filter.source and filter.source == Wording.sourceIdentity(gain) then
                    sourceQuantity = sourceQuantity + quantity
                end
                lastGained = math.max(lastGained or gain.at, gain.at)
                if gain.method == filter.method and gain.quantity > (gain.refunded or 0) then
                    methodMatches = true
                end
            end
            if pause then
                pause()
            end
        end
        local placeMatches = not filter.place
        for _, gain in ipairs(record.gains) do
            if
                gain.place ~= ""
                and gain.place ~= "Unknown"
                and matchesFilter(filter.character, filter.realm, gain.character, gain.realm)
            then
                local kind = gain.placeKind or "place"
                local key = kind .. ":" .. gain.place
                places[key] = { key = key, name = gain.place, kind = kind }
                if filter.place == gain.place and (not filter.placeKind or filter.placeKind == kind) then
                    placeMatches = true
                end
            end
            if pause then
                pause()
            end
        end
        local info = metadata and metadata(record) or { category = "Unknown", loading = true }
        local name = record.links[1]:match("%[([^%]]+)%]") or ("Item " .. record.itemID)
        local searchText = string.lower(name .. " " .. record.key .. " " .. table.concat(record.links, " "))
        local lastSeen = addon.LastSeen.project(store, record, character, realm, filter)
        local status = Wording.ownershipText(lastSeen)
        local currentUnits
        if filter.character then
            currentUnits = lastSeen.characterCurrent
        else
            currentUnits = lastSeen.allCharactersCurrent
        end
        local qualityMatches = filter.quality == nil
            or (filter.quality == "unknown" and info.quality == nil)
            or info.quality == filter.quality
        if
            matches
            and (filter.view ~= "Gallery" or info.gear == true or info.category == "Unknown")
            and placeMatches
            and (not filter.source or sourceQuantity > 0)
            and (not filter.ownership or lastSeen.state == filter.ownership)
            and qualityMatches
            and methodMatches
        then
            candidates[#candidates + 1] = {
                searchText = searchText,
                sources = recordSources,
                row = {
                    key = record.key,
                    name = name,
                    record = record,
                    category = info.category,
                    loading = info.loading,
                    ownership = status,
                    ownershipState = lastSeen.state,
                    discoveredAt = (not filter.character and not filter.realm) and record.firstSeen or discoveredAt,
                    metadata = info,
                    lastGained = lastGained,
                    sourceQuantity = filter.source and sourceQuantity or nil,
                    characterOverall = lastSeen.characterOverall,
                    allCharactersOverall = lastSeen.allCharactersOverall,
                    characterCurrent = lastSeen.characterCurrent,
                    allCharactersCurrent = lastSeen.allCharactersCurrent,
                    currentUnits = currentUnits,
                },
            }
        end
        if info.loading then
            result.loading = result.loading + 1
        end
        if pause then
            pause()
        end
    end
    result.sources = Wording.sourceGroups(sources, pause)
    local search, matchingSources = string.lower(filter.search or ""), {}
    if search ~= "" then
        for _, source in ipairs(result.sources) do
            local text = string.lower(source.label .. " " .. source.neutral .. " " .. source.key)
            local matches = text:find(search, 1, true) ~= nil
            for name in pairs(source.names) do
                matches = matches or string.lower(name):find(search, 1, true) ~= nil
                if pause then
                    pause()
                end
            end
            matchingSources[source.key] = matches
            if pause then
                pause()
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        local matches = candidate.searchText:find(search, 1, true) ~= nil
        for key in pairs(candidate.sources) do
            matches = matches or matchingSources[key]
            if pause then
                pause()
            end
        end
        if matches then
            local row = candidate.row
            result.categories[row.category] = (result.categories[row.category] or 0) + 1
            result.matchedCount = result.matchedCount + 1
            if not filter.category or filter.category == row.category then
                result.rows[#result.rows + 1] = row
            end
        end
        if pause then
            pause()
        end
    end
    for _, place in pairs(places) do
        result.places[#result.places + 1] = place
    end
    addon.Work.sort(result.places, function(a, b)
        return a.key < b.key
    end, pause)
    local sort = filter.sort or (filter.view == "Discoveries" and "discovered" or "name")
    addon.Work.sort(result.rows, function(a, b)
        local left, right
        if sort == "discovered" then
            left, right = a.discoveredAt, b.discoveredAt
        elseif sort == "gained" then
            left, right = a.lastGained, b.lastGained
        elseif sort == "quantity" then
            left = a.currentUnits
            right = b.currentUnits
        end
        if left ~= right then
            return left ~= nil and (right == nil or left > right)
        end
        return a.name < b.name or (a.name == b.name and a.key < b.key)
    end, pause)
    result.byKey, result.positions = {}, {}
    for index, row in ipairs(result.rows) do
        result.byKey[row.key], result.positions[row.key] = row, index
        if pause then
            pause()
        end
    end
    return result
end

function Collection.query(store, character, realm, filter, metadata)
    return query(store, character, realm, filter, metadata)
end

function Collection.startQuery(api, store, character, realm, filter, metadata)
    return addon.Work.start(api, "Collection query", function(pause)
        return query(store, character, realm, filter, metadata, pause)
    end)
end

---@class ALGallerySelection
---@field key string
---@field link string
---@field index integer

---@param result {rows: AzerothLedgerCollectionRow[], byKey?: table<string, AzerothLedgerCollectionRow>}
---@param key? string
---@param link? string
---@return ALGallerySelection?
-- A selection must belong to the filtered gallery and use an exact retained link.
function Collection.gallerySelection(result, key, link)
    local selected = result.rows[1]
    if result.byKey then
        selected = result.byKey[key] or selected
    else
        for _, row in ipairs(result.rows) do
            if row.key == key then
                selected = row
                break
            end
        end
    end
    if not selected then
        return nil
    end
    if selected.key == key then
        for index, savedLink in ipairs(selected.record.links) do
            if savedLink == link then
                return { key = selected.key, link = savedLink, index = index }
            end
        end
    end
    return { key = selected.key, link = selected.record.links[1], index = 1 }
end

---@class AzerothLedgerItemDetails
---@field record AzerothLedgerRecord
---@field breakdown AzerothLedgerBreakdown
---@field links {link: string, count: integer}[]
---@field ownership string
---@field ownershipState 'present'|'unknown'|'historical'
---@field evidence string
---@field firstSeen? integer
---@field lastSeen? integer
---@field firstGained? integer
---@field lastGained? integer
---@field scopeLabel string
---@field characterOverall? integer
---@field allCharactersOverall? integer
---@field characterCurrent? integer
---@field allCharactersCurrent? integer
---@field currentAt? integer
---@field checks ALStorageCheck[]

---@param store ALStore
---@param record AzerothLedgerRecord
---@param character string
---@param realm string
---@param filter AzerothLedgerCollectionFilter
---@param lastSeen? ALLastSeen
---@param pause? fun()
---@return AzerothLedgerItemDetails?
local function inspectRecord(store, record, character, realm, filter, lastSeen, pause)
    lastSeen = lastSeen or addon.LastSeen.project(store, record, character, realm, filter)
    local strength = "Seen in storage"
    local firstGained, lastGained
    for _, gain in ipairs(record.gains) do
        if matchesFilter(filter.character, filter.realm, gain.character, gain.realm) then
            firstGained = math.min(firstGained or gain.at, gain.at)
            lastGained = math.max(lastGained or gain.at, gain.at)
            if gain.source or gain.context then
                strength = "Confirmed gain with specific source"
            elseif strength ~= "Confirmed gain with specific source" then
                strength = "Confirmed " .. gain.method .. " gain; source Unknown"
            end
        end
        if pause then
            pause()
        end
    end
    local firstSeen, lastSeenAt
    for _, seen in ipairs(record.characters) do
        if matchesFilter(filter.character, filter.realm, seen.name, seen.realm) then
            firstSeen = math.min(firstSeen or seen.firstSeen, seen.firstSeen)
            lastSeenAt = math.max(lastSeenAt or seen.lastSeen, seen.lastSeen)
        end
    end
    return {
        record = record,
        breakdown = assert(store:breakdown(record.key, filter, pause)),
        links = addon.Item.linkGroups(record.links),
        firstSeen = firstSeen,
        lastSeen = lastSeenAt,
        firstGained = firstGained,
        lastGained = lastGained,
        scopeLabel = filter.character and (filter.character .. (filter.realm and ("-" .. filter.realm) or ""))
            or filter.realm
            or "Account",
        characterOverall = lastSeen.characterOverall,
        allCharactersOverall = lastSeen.allCharactersOverall,
        characterCurrent = lastSeen.characterCurrent,
        allCharactersCurrent = lastSeen.allCharactersCurrent,
        currentAt = lastSeen.currentAt,
        evidence = strength,
        checks = lastSeen.checks,
        ownership = Wording.ownershipText(lastSeen),
        ownershipState = lastSeen.state,
    }
end

---@param store ALStore
---@param key string
---@param character string
---@param realm string
---@param filter? AzerothLedgerCollectionFilter
---@return AzerothLedgerItemDetails?
function Collection.inspect(store, key, character, realm, filter, pause)
    local record = store:find(key, pause)
    return record and inspectRecord(store, record, character, realm, filter or {}, nil, pause) or nil
end

addon.Collection = Collection
