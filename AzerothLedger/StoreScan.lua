local _, addon = ...

-- Possessions snapshots: observations and identity evidence. Each correlating
-- domain settles its pending actions against the measured change through the
-- check handler its engine returns; one save commits the whole check.

local V = addon.SchemaValidate
local areas, isInteger, validCheckID, isName, areaKey = V.areas, V.isInteger, V.validCheckID, V.isName, V.areaKey
local copyValue, copyRecord = V.copyValue, V.copyRecord

---@class AzerothLedgerCheck One possessions check, shared with every domain handler.
---@field snapshot AzerothLedgerSnapshot
---@field grouped table<string, {itemID: integer, quantity: integer, links: table<string, true>}>
---@field records table<string, AzerothLedgerRecord> Records this check changes, by key
---@field oldScope table? The previous check of this area
---@field unresolvedIdentity boolean Whether this check resolved an unreadable item
---@field paired boolean Whether this equipped check completes a bag check of the same moment
---@field pairedKeys fun(): table<string, true> Items a paired check measures: bag items and this check's items

local StoreScan = {}

-- Handlers run in engine order. Each may provide item(key, group, known) before
-- the record changes, record(key, group, record, seen, known) after it changes,
-- finish() once every item is measured, and commit(fields) for the save.
---@param engines AzerothLedgerEngine[]
function StoreScan.install(store, kernel, correlation, engines)
    local valid, readable, saveFields, heldKeys = kernel.valid, kernel.readable, kernel.save, kernel.heldKeys
    local evidenceState, retain = correlation.state, correlation.retain

    ---@param snapshot AzerothLedgerSnapshot
    function store.scan(_self, snapshot)
        if
            not readable
            or type(snapshot) ~= "table"
            or not isName(snapshot.character)
            or not isName(snapshot.realm)
            or not areas[snapshot.area]
            or not isInteger(snapshot.seenAt)
            or snapshot.seenAt < 0
            or type(snapshot.complete) ~= "boolean"
            or type(snapshot.items) ~= "table"
        then
            return false
        end
        for _, item in ipairs(snapshot.items) do
            if
                type(item) ~= "table"
                or not isInteger(item.itemID)
                or item.itemID <= 0
                or not isInteger(item.quantity)
                or item.quantity <= 0
            then
                return false
            end
        end
        local priorScope = kernel.area(areaKey(snapshot.character, snapshot.realm, snapshot.area))
        if type(priorScope) == "table" and not validCheckID(priorScope.checkID) then
            return false
        end
        if type(priorScope) == "table" and isInteger(priorScope.seenAt) and snapshot.seenAt < priorScope.seenAt then
            return false
        end
        if not store:expireEvidence(snapshot.seenAt) then
            return false
        end
        snapshot = copyValue(snapshot)
        local grouped = {}
        local evidence = evidenceState()
        if not evidence then
            return false
        end
        local unresolvedIdentity = false
        for _, item in ipairs(snapshot.items) do
            if
                type(item) ~= "table"
                or not isInteger(item.itemID)
                or item.itemID <= 0
                or not isInteger(item.quantity)
                or item.quantity <= 0
            then
                return false
            end
            local key = addon.Item.key(item.link, item.itemID)
            if not key then
                snapshot.complete = false
                local found = false
                for _, entry in ipairs(evidence.unresolved) do
                    if
                        entry.kind == "identity"
                        and entry.character == snapshot.character
                        and entry.realm == snapshot.realm
                        and entry.detail.area == snapshot.area
                        and entry.detail.location == item.location
                        and entry.detail.itemID == item.itemID
                        and entry.detail.quantity == item.quantity
                        and entry.detail.link == item.link
                    then
                        found = true
                    end
                end
                if not found then
                    retain(evidence, "identity", "unreadable", snapshot.seenAt, snapshot, {
                        itemID = item.itemID,
                        quantity = item.quantity,
                        link = item.link,
                        location = item.location,
                        area = snapshot.area,
                    })
                end
            else
                for index = #evidence.unresolved, 1, -1 do
                    local entry = evidence.unresolved[index]
                    if
                        entry.kind == "identity"
                        and entry.character == snapshot.character
                        and entry.realm == snapshot.realm
                        and entry.detail.area == snapshot.area
                        and item.location ~= nil
                        and entry.detail.location == item.location
                        and entry.at == snapshot.seenAt
                        and entry.detail.itemID == item.itemID
                        and entry.detail.quantity == item.quantity
                    then
                        table.remove(evidence.unresolved, index)
                        unresolvedIdentity = true
                    end
                end
                local group = grouped[key] or { itemID = item.itemID, quantity = 0, links = {} }
                group.quantity = group.quantity + item.quantity
                group.links[item.link] = true
                grouped[key] = group
            end
        end
        local scopeKey = areaKey(snapshot.character, snapshot.realm, snapshot.area)
        local oldScope = kernel.area(scopeKey)
        if type(oldScope) == "table" and isInteger(oldScope.seenAt) and snapshot.seenAt < oldScope.seenAt then
            return false
        end
        local nextRecords = {}
        local function pairedKeys()
            local keys = {}
            for key in pairs(heldKeys(snapshot.character, snapshot.realm, "bags")) do
                keys[key] = true
            end
            for key in pairs(grouped) do
                keys[key] = true
            end
            return keys
        end
        ---@type AzerothLedgerCheck
        local scan = {
            snapshot = snapshot,
            grouped = grouped,
            records = nextRecords,
            oldScope = oldScope,
            unresolvedIdentity = unresolvedIdentity,
            paired = false,
            pairedKeys = pairedKeys,
        }
        local handlers = {}
        for index, engine in ipairs(engines) do
            handlers[index] = engine.check(scan)
        end
        for key, group in pairs(grouped) do
            local characterWasKnown = false
            local existingRecord = valid[key]
            if existingRecord then
                for _, seen in ipairs(existingRecord.characters) do
                    if seen.name == snapshot.character and seen.realm == snapshot.realm then
                        characterWasKnown = true
                        break
                    end
                end
            end
            for _, handler in ipairs(handlers) do
                if handler.item then
                    handler.item(key, group, characterWasKnown)
                end
            end
            local record = valid[key] and copyRecord(valid[key], true)
                or {
                    key = key,
                    itemID = group.itemID,
                    firstSeen = snapshot.seenAt,
                    lastSeen = snapshot.seenAt,
                    firstSeenUnits = group.quantity,
                    -- An earlier complete check of this area proves these
                    -- units arrived later, even when nothing explains how.
                    firstSeenLater = type(oldScope) == "table" and oldScope.complete or nil,
                    totalGained = 0,
                    gains = {},
                    links = {},
                    characters = {},
                    observations = {},
                }
            if snapshot.seenAt > record.lastSeen then
                record.lastSeen = snapshot.seenAt
            end
            local seenLinks = {}
            for _, link in ipairs(record.links) do
                seenLinks[link] = true
            end
            for link in pairs(group.links) do
                if not seenLinks[link] then
                    record.links[#record.links + 1] = link
                end
            end
            table.sort(record.links)
            local characterFound, characterEntry = false, nil
            for _, character in ipairs(record.characters) do
                if character.name == snapshot.character and character.realm == snapshot.realm then
                    characterFound = true
                    characterEntry = character
                    if snapshot.seenAt > character.lastSeen then
                        character.lastSeen = snapshot.seenAt
                    end
                    break
                end
            end
            if not characterFound then
                characterEntry = {
                    name = snapshot.character,
                    realm = snapshot.realm,
                    firstSeen = snapshot.seenAt,
                    lastSeen = snapshot.seenAt,
                    firstSeenUnits = group.quantity,
                    firstSeenLater = type(oldScope) == "table" and oldScope.complete or nil,
                }
                record.characters[#record.characters + 1] = characterEntry
            end
            local previous
            for _, observation in ipairs(record.observations) do
                if
                    observation.character == snapshot.character
                    and observation.realm == snapshot.realm
                    and observation.area == snapshot.area
                then
                    previous = observation
                end
            end
            if not previous or previous.quantity ~= group.quantity then
                record.observations[#record.observations + 1] = {
                    character = snapshot.character,
                    realm = snapshot.realm,
                    area = snapshot.area,
                    quantity = group.quantity,
                    seenAt = snapshot.seenAt,
                }
            else
                previous.seenAt = snapshot.seenAt
            end
            nextRecords[key] = record
            for _, handler in ipairs(handlers) do
                if handler.record then
                    handler.record(key, group, record, characterEntry, characterWasKnown)
                end
            end
        end
        if snapshot.complete then
            for key in pairs(heldKeys(snapshot.character, snapshot.realm, snapshot.area)) do
                local existing = valid[key]
                if not grouped[key] then
                    local previous
                    for _, observation in ipairs(existing.observations) do
                        if
                            observation.character == snapshot.character
                            and observation.realm == snapshot.realm
                            and observation.area == snapshot.area
                        then
                            previous = observation
                        end
                    end
                    if previous and previous.quantity > 0 then
                        local record = copyRecord(existing, true)
                        record.observations[#record.observations + 1] = {
                            character = snapshot.character,
                            realm = snapshot.realm,
                            area = snapshot.area,
                            quantity = 0,
                            seenAt = snapshot.seenAt,
                        }
                        nextRecords[key] = record
                    end
                end
            end
        end
        local bagArea = store:area(snapshot.character, snapshot.realm, "bags")
        -- The paired check follows the bag commit of the same moment.
        scan.paired = snapshot.area == "equipped"
            and snapshot.complete
            and bagArea ~= nil
            and bagArea.complete
            and bagArea.seenAt == snapshot.seenAt
        for _, handler in ipairs(handlers) do
            if handler.finish then
                handler.finish()
            end
        end
        local nextAreas = {}
        for key, state in pairs(kernel.areas()) do
            nextAreas[key] = state
        end
        local previousArea = store:area(snapshot.character, snapshot.realm, snapshot.area)
        nextAreas[scopeKey] = {
            seenAt = snapshot.seenAt,
            checkID = (type(oldScope) == "table" and oldScope.checkID or 0) + 1,
            complete = snapshot.complete,
            lastCompleteAt = snapshot.complete and snapshot.seenAt or (previousArea and previousArea.lastCompleteAt),
            character = snapshot.character,
            realm = snapshot.realm,
        }
        local fields = { records = nextRecords, areas = nextAreas, evidence = evidence }
        for _, handler in ipairs(handlers) do
            handler.commit(fields)
        end
        saveFields(fields)
        for key, record in pairs(nextRecords) do
            if valid[key] or grouped[key] then
                valid[key] = copyRecord(record, true)
            end
        end
        return true
    end
end

addon.StoreScan = StoreScan
