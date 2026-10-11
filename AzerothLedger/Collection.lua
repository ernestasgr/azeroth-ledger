local _, addon = ...

local Collection = {}

local evidenceActions = {
    loot = "Loot pickup",
    lootOpen = "Loot pickup",
    lootReceipt = "Loot pickup",
    rewards = "Quest reward",
    rewardReceipt = "Quest reward",
    quest = "Quest reward",
    questPrepared = "Quest reward",
    vendor = "Vendor action",
    vendorAction = "Vendor action",
    vendorReceipt = "Vendor action",
    exchange = "Mail or trade",
    exchangeIntent = "Mail or trade",
    identity = "Bag, bank, or gear check",
}
local evidenceReasons = {
    expired = "The addon could not confirm this item gain in time.",
    reload = "You logged out or reloaded before the addon could confirm this item gain.",
    overflow = "Too many item changes happened at once for the addon to confirm this one.",
    unreadable = "The game did not provide a readable item name.",
    unmatched = "The item change did not match an action the addon saw.",
    stopped = "The addon could not tell which action caused this item change.",
}

local sourceUncertainty = "The addon could not identify one clear loot source. "
    .. "It also needs to see the item gain."

---@param entry ALEvidenceViewEntry
local function evidenceReason(entry)
    local reason = evidenceReasons[entry.reason]
    if entry.kind == "loot" and not entry.sourceKnown then
        return reason and (reason .. " " .. sourceUncertainty) or sourceUncertainty
    end
    if reason then
        return reason
    elseif entry.kind == "vendor" then
        return "The vendor action and matching item change could not both be confirmed."
    elseif entry.kind == "exchange" then
        return "The mail or trade, item change, or other character could not be confirmed."
    end
    return "The addon could not confirm both the action and the item change."
end

---@param entry ALEvidenceViewEntry
local function evidenceNextStep(entry)
    if entry.reason == "expired" or entry.reason == "reload" or entry.reason == "overflow" then
        return "This old item change can no longer be confirmed. Future checks will not add it to Total gained."
    elseif entry.kind == "identity" then
        local area = entry.area == "bank" and "the bank" or entry.area == "equipped" and "equipped gear" or "bags"
        return "Wait for the item name to load, then check "
            .. area
            .. " again. The item may be added as Seen, but that will not count as a gain."
    elseif entry.reason == "unmatched" then
        return "The addon did not see a matching action. This receipt alone does not confirm a gain."
    elseif entry.reason == "stopped" then
        return "The addon will not retry this action. Future checks will not confirm it."
    elseif entry.reason ~= "active" then
        return "This saved entry does not show whether the addon can still confirm the item change."
    end
    return "The addon can still match this while its check is open. "
        .. "Checking bags, bank, or gear may help, but might not confirm a gain."
end

-- Public read-only projection: saved evidence and live candidates share one
-- presentation, with stable IDs independent of Collection item identity.
function Collection.evidenceQuery(store, filter, pause)
    pause = pause or function() end
    local candidates, actors, seenActors, representedPreparations = {}, {}, {}, {}
    local summary = store:visitEvidence(function(entry)
        candidates[#candidates + 1] = entry
        if entry.kind == "rewards" and entry.preparationID then
            local key = entry.character .. "\031" .. entry.realm .. "\031" .. entry.preparationID
            representedPreparations[key] = true
        end
        local actorKey = entry.character .. "\031" .. entry.realm
        if not seenActors[actorKey] then
            seenActors[actorKey] = true
            actors[#actors + 1] = { character = entry.character, realm = entry.realm }
        end
    end, pause)
    local rows, positions, total = {}, {}, 0
    local search = string.lower(filter.search or "")
    for _, entry in ipairs(candidates) do
        local preparationKey = entry.preparationID
            and (entry.character .. "\031" .. entry.realm .. "\031" .. entry.preparationID)
        if entry.kind ~= "quest" or not representedPreparations[preparationKey] then
            total = total + 1
            local record = entry.key and store:find(entry.key)
            local link = entry.link or (record and record.links[1])
            local readableLink = link and addon.Item.key(link, entry.itemID or (record and record.itemID))
            local name = readableLink and link:match("%[([^%]]+)%]")
                or (entry.itemID and ("Item " .. entry.itemID .. (not readableLink and " • unresolved variant" or "")))
                or entry.key
                or "Unresolved item identity"
            local action = evidenceActions[entry.kind] or "Item evidence"
            if (entry.kind == "vendor" or entry.kind == "vendorAction") and entry.action then
                action = "Vendor " .. entry.action
            elseif entry.kind == "exchange" or entry.kind == "exchangeIntent" then
                action = entry.channel == "mail" and "Mail" or entry.channel == "trade" and "Trade" or "Mail or trade"
                if entry.direction == "in" then
                    action = action .. " received"
                elseif entry.direction == "out" then
                    action = action .. " sent"
                end
            elseif entry.method then
                action = entry.method == "Crafted" and "Craft" or "Quest reward"
            end
            if
                (not filter.character or entry.character == filter.character)
                and (not filter.realm or entry.realm == filter.realm)
                and string
                    .lower(name .. " " .. (link or "") .. " " .. (entry.key or "") .. " " .. (entry.itemID or ""))
                    :find(search, 1, true)
            then
                rows[#rows + 1] = {
                    id = entry.id,
                    key = entry.key,
                    link = readableLink and link or nil,
                    name = name,
                    character = entry.character,
                    realm = entry.realm,
                    at = entry.at,
                    action = action,
                    reason = evidenceReason(entry),
                    nextStep = evidenceNextStep(entry),
                    quantity = entry.quantity,
                    location = entry.location,
                    status = entry.reason == "expired" and "Timed out"
                        or entry.reason == "reload" and "Login interrupted"
                        or entry.reason == "overflow" and "Too many changes"
                        or entry.kind == "identity" and "Item name unavailable"
                        or entry.reason == "stopped" and "Could not match"
                        or entry.reason == "unmatched" and "No matching action"
                        or entry.reason == "active" and "Still checking"
                        or "Needs review",
                }
            end
        end
        pause()
    end
    addon.Work.sort(rows, function(left, right)
        return left.at > right.at or (left.at == right.at and left.id < right.id)
    end, pause)
    addon.Work.sort(actors, function(left, right)
        return left.realm < right.realm or (left.realm == right.realm and left.character < right.character)
    end, pause)
    for index, row in ipairs(rows) do
        positions[row.id] = index
        pause()
    end
    return {
        rows = rows,
        positions = positions,
        actors = actors,
        total = total,
        discarded = summary.discarded,
        firstDiscarded = summary.firstDiscarded,
        lastDiscarded = summary.lastDiscarded,
        categories = {},
        places = {},
        loading = 0,
        matchedCount = #rows,
        discoveryCount = store:count(),
    }
end

---@class AzerothLedgerCollectionApi
---@field CreateFrame? fun(frameType: string, name?: string, parent?: table, template?: string): table
---@field UIParent table
---@field GameFontNormal table

local function stamp(seconds)
    return seconds and date("%Y-%m-%d %H:%M", seconds) or "Unknown"
end

local function matchesFilter(filterCharacter, filterRealm, name, realm)
    return (not filterCharacter or name == filterCharacter) and (not filterRealm or realm == filterRealm)
end

local function sourceText(source)
    return addon.Schema.sourceText(source)
end

local function contextText(context)
    return context and (context.name or (context.kind .. " " .. context.id)) or "Unknown"
end

local storageAreas = { "bags", "bank", "equipped" }
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

local inspectRecord

local function ownershipText(lastSeen)
    if lastSeen.state == "present" then
        return "Present"
    elseif lastSeen.state == "unknown" then
        return "Unknown"
    end
    return "Historical only as of " .. stamp(lastSeen.asOf)
end

Collection.ownershipText = ownershipText

---@param store AzerothLedgerStore
---@param character string
---@param realm string
---@param filterCharacter? string
---@param filterRealm? string
---@param developerMode? boolean
---@return string[]
-- Produces the text shown in the Collection, including scope freshness.
function Collection.lines(store, character, realm, filterCharacter, filterRealm, developerMode)
    local lines = {}
    local evidence = store:evidenceSummary()
    if evidence.discarded > 0 then
        lines[#lines + 1] = "WARNING: older item changes need review; details unavailable: "
            .. evidence.discarded
            .. " • "
            .. stamp(evidence.firstDiscarded)
            .. " through "
            .. stamp(evidence.lastDiscarded)
    end
    local review = Collection.evidenceQuery(store, {})
    if #review.rows > 0 then
        lines[#lines + 1] = "Item changes to review: " .. #review.rows .. " • no gains guessed"
        local shownEvidence = 0
        for index = #review.rows, 1, -1 do
            local entry = review.rows[index]
            if matchesFilter(filterCharacter, filterRealm, entry.character, entry.realm) then
                lines[#lines + 1] = "  " .. entry.action .. " • " .. entry.status .. " • " .. stamp(entry.at)
                shownEvidence = shownEvidence + 1
                if shownEvidence == 10 then
                    break
                end
            end
        end
    end
    if not filterRealm or filterCharacter then
        for _, area in ipairs(storageAreas) do
            local state = store:area(filterCharacter or character, filterRealm or realm, area)
            if not state or not state.complete then
                lines[#lines + 1] = storageLabels[area] .. ": needs a check; amount Unknown"
            else
                lines[#lines + 1] = storageLabels[area] .. ": last checked " .. stamp(state.seenAt)
            end
        end
    end
    local shown = 0
    local recent = {}
    local records = store:list()
    for _, record in ipairs(records) do
        local matches = not filterCharacter and not filterRealm
        for _, seen in ipairs(record.characters) do
            if matchesFilter(filterCharacter, filterRealm, seen.name, seen.realm) then
                matches = true
                break
            end
        end
        if matches then
            shown = shown + 1
            local name = record.links[1]:match("%[([^%]]+)%]") or ("Item " .. record.itemID)
            lines[#lines + 1] = name
                .. (developerMode and (" [internal item key " .. record.key .. "]") or "")
                .. " — already had at first check "
                .. record.firstSeenUnits
                .. "; Total gained "
                .. record.totalGained
                .. "; Total found "
                .. (record.firstSeenUnits + record.totalGained)
            local lastSeen = addon.LastSeen.project(
                store,
                record,
                character,
                realm,
                { character = filterCharacter, realm = filterRealm }
            )
            lines[#lines + 1] = "  Status: " .. ownershipText(lastSeen)
            for _, check in ipairs(lastSeen.checks) do
                lines[#lines + 1] = "  " .. Collection.checkText(check)
            end
            local lastCheck = lastSeen.latestCheck
            if lastCheck then
                lines[#lines + 1] = "  Latest check "
                    .. (lastCheck.quantity or "Unknown")
                    .. " • "
                    .. lastCheck.character
                    .. "-"
                    .. lastCheck.realm
                    .. " • "
                    .. lastCheck.area
                    .. " • "
                    .. stamp(lastCheck.at)
            end
            lines[#lines + 1] = "  First seen "
                .. stamp(record.firstSeen)
                .. " • last seen "
                .. stamp(record.lastSeen)
                .. (
                    record.firstGained and (" • first confirmed gain " .. stamp(record.firstGained))
                    or " • confirmed gain unknown"
                )
            if record.lastGained then
                lines[#lines + 1] = "  Latest confirmed gain " .. stamp(record.lastGained)
            end
            local breakdown = assert(store:breakdown(record.key))
            local sources = breakdown.sources
            local methods = breakdown.methods
            if breakdown.recorded > 0 then
                local methodLabels = {}
                for method in pairs(methods) do
                    methodLabels[#methodLabels + 1] = method
                end
                table.sort(methodLabels)
                for _, method in ipairs(methodLabels) do
                    if methods[method] > 0 then
                        lines[#lines + 1] = "  How you got it: "
                            .. (method == "Seen" and "Already had at first check" or method)
                            .. " "
                            .. methods[method]
                    end
                end
                local labels = {}
                for label in pairs(sources) do
                    labels[#labels + 1] = label
                end
                table.sort(labels)
                for _, label in ipairs(labels) do
                    if sources[label] > 0 then
                        lines[#lines + 1] = "  From "
                            .. (label == "Initial stock" and "Already had before first check" or label)
                            .. " "
                            .. sources[label]
                    end
                end
            end
            for _, seen in ipairs(record.characters) do
                if matchesFilter(filterCharacter, filterRealm, seen.name, seen.realm) then
                    lines[#lines + 1] = "  "
                        .. seen.name
                        .. "-"
                        .. seen.realm
                        .. ": first seen "
                        .. stamp(seen.firstSeen)
                        .. " • "
                        .. seen.firstSeenUnits
                        .. " units"
                end
            end
            for _, observation in ipairs(record.observations) do
                if matchesFilter(filterCharacter, filterRealm, observation.character, observation.realm) then
                    lines[#lines + 1] = "  "
                        .. stamp(observation.seenAt)
                        .. " • "
                        .. observation.quantity
                        .. " • "
                        .. observation.character
                        .. "-"
                        .. observation.realm
                        .. " • "
                        .. storageLabels[observation.area]
                end
            end
            for _, gain in ipairs(record.gains) do
                if matchesFilter(filterCharacter, filterRealm, gain.character, gain.realm) then
                    local source = gain.source
                    local detail = "  "
                        .. stamp(gain.at)
                        .. " • +"
                        .. gain.quantity
                        .. " "
                        .. gain.method
                        .. " • "
                        .. gain.character
                        .. "-"
                        .. gain.realm
                        .. " level "
                        .. gain.level
                        .. " • "
                        .. gain.place
                        .. (gain.method == "Looted" and (" • source " .. sourceText(source)) or "")
                        .. (gain.method == "Vendor" and source and (" • vendor " .. sourceText(source)) or "")
                        .. (gain.method == "Obtained" and (" • source " .. sourceText(source)) or "")
                        .. (gain.method == "Quest" and (" • quest " .. contextText(gain.context)) or "")
                        .. (gain.method == "Crafted" and (" • recipe " .. contextText(gain.context)) or "")
                    lines[#lines + 1] = detail
                    recent[#recent + 1] = { at = gain.at, text = name .. detail }
                end
            end
        end
    end
    for _, action in ipairs(store:vendorActivity()) do
        if matchesFilter(filterCharacter, filterRealm, action.character, action.realm) then
            local record = store:find(action.key)
            local name = record and record.links[1]:match("%[([^%]]+)%]") or action.key
            local labels = { sale = "Sale", refund = "Refund", buyback = "Buyback" }
            recent[#recent + 1] = {
                at = action.at,
                text = name
                    .. "  "
                    .. stamp(action.at)
                    .. " • "
                    .. labels[action.kind]
                    .. " x"
                    .. action.quantity
                    .. " • "
                    .. action.character
                    .. "-"
                    .. action.realm
                    .. (action.vendorName and (" • vendor " .. action.vendorName) or ""),
            }
        end
    end
    for _, action in ipairs(store:vendorUnresolved()) do
        if matchesFilter(filterCharacter, filterRealm, action.character, action.realm) then
            lines[#lines + 1] = "Vendor action needs review: "
                .. action.kind
                .. " x"
                .. action.quantity
                .. " • "
                .. stamp(action.at)
        end
    end
    for _, action in ipairs(store:exchangeActivity()) do
        if
            matchesFilter(filterCharacter, filterRealm, action.sender, action.senderRealm)
            or matchesFilter(filterCharacter, filterRealm, action.recipient, action.recipientRealm)
        then
            local record = store:find(action.key)
            local name = record and record.links[1]:match("%[([^%]]+)%]") or action.key
            recent[#recent + 1] = {
                at = action.at,
                text = name
                    .. "  "
                    .. stamp(action.at)
                    .. " • Transfer x"
                    .. action.quantity
                    .. " • "
                    .. action.sender
                    .. "-"
                    .. action.senderRealm
                    .. " → "
                    .. action.recipient
                    .. "-"
                    .. action.recipientRealm
                    .. " • "
                    .. action.channel,
            }
        end
    end
    for _, action in ipairs(store:exchangeUnresolved()) do
        if matchesFilter(filterCharacter, filterRealm, action.character, action.realm) then
            lines[#lines + 1] = "Mail or trade needs review: "
                .. action.channel
                .. " "
                .. action.direction
                .. " x"
                .. action.quantity
                .. " • "
                .. stamp(action.at)
        end
    end
    if shown == 0 then
        lines[#lines + 1] = "No items found yet."
    end
    if #recent > 0 then
        table.sort(recent, function(left, right)
            return left.at > right.at
        end)
        lines[#lines + 1] = "Recent activity"
        for index = 1, math.min(#recent, 10) do
            lines[#lines + 1] = recent[index].text
        end
    end
    return lines
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
---@field checkedUnits? integer
---@field uncheckedAreas? integer
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
        local methodMatches = not filter.method or (filter.method == "Seen" and record.firstSeenUnits > 0)
        local lastGained
        local sourceQuantity, recordSources = 0, {}
        for _, gain in ipairs(record.gains) do
            if matchesFilter(filter.character, filter.realm, gain.character, gain.realm) then
                local quantity = gain.quantity - (gain.refunded or 0)
                addon.Schema.addSource(sources, gain, quantity)
                if filter.search and filter.search ~= "" then
                    addon.Schema.addSource(recordSources, gain, quantity)
                end
                if filter.source and filter.source == addon.Schema.sourceIdentity(gain) then
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
        local status = ownershipText(lastSeen)
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
                    recorded = not (filter.character or filter.realm) and (record.firstSeenUnits + record.totalGained)
                        or nil,
                    checkedUnits = lastSeen.checkedUnits,
                    uncheckedAreas = lastSeen.uncheckedAreas,
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
    result.sources = addon.Schema.sourceGroups(sources, pause)
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
            -- Account Recorded and scoped checked stock are different facts.
            left = a.sourceQuantity or a.recorded or a.checkedUnits
            right = b.sourceQuantity or b.recorded or b.checkedUnits
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
---@field checkedUnits? integer
---@field uncheckedAreas integer
---@field checkedAt? integer
---@field firstChecked? integer
---@field checks ALStorageCheck[]

---@param store ALStore
---@param record AzerothLedgerRecord
---@param character string
---@param realm string
---@param filter AzerothLedgerCollectionFilter
---@param lastSeen? ALLastSeen
---@param pause? fun()
---@return AzerothLedgerItemDetails?
inspectRecord = function(store, record, character, realm, filter, lastSeen, pause)
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
        checkedUnits = lastSeen.checkedUnits,
        uncheckedAreas = lastSeen.uncheckedAreas,
        checkedAt = lastSeen.checkedAt,
        firstChecked = lastSeen.firstChecked,
        evidence = strength,
        checks = lastSeen.checks,
        ownership = ownershipText(lastSeen),
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

---@param store ALStore
---@param key string
---@param character string
---@param realm string
---@param filter? AzerothLedgerCollectionFilter
---@param developerMode? boolean
---@return string[]
function Collection.details(store, key, character, realm, filter, developerMode)
    filter = filter or {}
    local model = Collection.inspect(store, key, character, realm, filter)
    if not model then
        return { "Select an item to see its history." }
    end
    local record = model.record
    local lines = {}
    lines[#lines + 1] = "First seen " .. stamp(model.firstSeen)
    lines[#lines + 1] = "Last seen " .. stamp(model.lastSeen)
    lines[#lines + 1] = "First confirmed gain: " .. stamp(model.firstGained)
    lines[#lines + 1] = "Last confirmed gain: " .. stamp(model.lastGained)
    if developerMode then
        lines[#lines + 1] = "Internal item key: " .. record.key
        lines[#lines + 1] = "Evidence summary: " .. model.evidence
    end
    local breakdown = model.breakdown
    if breakdown.recorded then
        lines[#lines + 1] = "Total found: " .. breakdown.recorded .. " (" .. model.scopeLabel .. ")"
    else
        lines[#lines + 1] = "Latest check: "
            .. (model.checkedUnits or "Unknown")
            .. (model.uncheckedAreas > 0 and "; some bags, bank, or gear need checking" or "")
        lines[#lines + 1] = "First checked: " .. (model.firstChecked or "Unknown")
    end
    lines[#lines + 1] = "Total gained: " .. breakdown.gained
    for _, group in ipairs({ { "How you got it", breakdown.methods }, { "Where it came from", breakdown.sources } }) do
        local labels = {}
        for label in pairs(group[2]) do
            labels[#labels + 1] = label
        end
        table.sort(labels)
        for _, label in ipairs(labels) do
            local playerLabel = label
            if group[1] == "How you got it" and label == "Seen" then
                playerLabel = "Already had at first check"
            elseif group[1] == "Where it came from" and label == "Initial stock" then
                playerLabel = "Already had before first check"
            end
            lines[#lines + 1] = group[1] .. ": " .. playerLabel .. " " .. group[2][label]
        end
    end
    lines[#lines + 1] = "Status: " .. model.ownership
    local describedActors = {}
    for _, seen in ipairs(record.characters) do
        if matchesFilter(filter.character, filter.realm, seen.name, seen.realm) then
            describedActors[seen.name .. "-" .. seen.realm] = true
            lines[#lines + 1] = seen.name
                .. "-"
                .. seen.realm
                .. ": first seen "
                .. stamp(seen.firstSeen)
                .. "; last seen "
                .. stamp(seen.lastSeen)
            for _, check in ipairs(model.checks) do
                if check.character == seen.name and check.realm == seen.realm then
                    lines[#lines + 1] = "  " .. Collection.checkText(check)
                end
            end
        end
    end
    local additionalActors = {}
    for _, check in ipairs(model.checks) do
        local actor = check.character .. "-" .. check.realm
        if not describedActors[actor] then
            if not additionalActors[actor] then
                lines[#lines + 1] = actor .. (not check.online and " • Offline; status Unknown" or "")
                additionalActors[actor] = true
            end
            lines[#lines + 1] = "  " .. Collection.checkText(check)
        end
    end
    return lines
end

---@param api table
---@param store ALStore
---@param character string
---@param realm string
---@param filterCharacter? string
---@param filterRealm? string
function Collection.open(api, store, character, realm, filterCharacter, filterRealm)
    return addon.Book.open(api, store, character, realm, filterCharacter, filterRealm)
end

function Collection.refresh(store, character, realm)
    if addon.Book then
        addon.Book.refresh(store, character, realm)
    end
end

addon.Collection = Collection
