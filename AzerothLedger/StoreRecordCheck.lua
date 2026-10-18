local _, addon = ...

-- Validators for saved records and the gain Journal. Nothing here reads or
-- writes a store; the kernel uses them when it opens and saves.

local V = addon.SchemaValidate
local isInteger = V.isInteger
local isName = V.isName
local areas, gainMethods = V.areas, V.gainMethods
local validPlaceKind = V.validPlaceKind

local StoreRecordCheck = {}

local function validRefunded(gain)
    return gain.refunded == nil
        or (
            gain.method == "Vendor"
            and isInteger(gain.refunded)
            and gain.refunded >= 0
            and gain.refunded <= gain.quantity
        )
end

local function validRecord(key, record)
    if
        type(key) ~= "string"
        or type(record) ~= "table"
        or record.key ~= key
        or (record.evidencedDiscovery ~= nil and type(record.evidencedDiscovery) ~= "boolean")
        or (record.firstSeenLater ~= nil and type(record.firstSeenLater) ~= "boolean")
        or not isInteger(record.itemID)
        or record.itemID <= 0
        or not isInteger(record.firstSeen)
        or not isInteger(record.lastSeen)
        or record.firstSeen < 0
        or record.lastSeen < record.firstSeen
        or not isInteger(record.firstSeenUnits)
        or record.firstSeenUnits < 0
        or not isInteger(record.totalGained)
        or record.totalGained < 0
        or (record.firstGained ~= nil and not isInteger(record.firstGained))
        or (record.lastGained ~= nil and not isInteger(record.lastGained))
        or type(record.links) ~= "table"
        or type(record.characters) ~= "table"
        or type(record.observations) ~= "table"
        or (record.gains ~= nil and type(record.gains) ~= "table")
        or #record.links == 0
        or #record.characters == 0
        or #record.observations == 0
    then
        return false
    end
    for _, link in ipairs(record.links) do
        if addon.Item.key(link, record.itemID) ~= key then
            return false
        end
    end
    for _, character in ipairs(record.characters) do
        if
            type(character) ~= "table"
            or not isName(character.name)
            or not isName(character.realm)
            or not isInteger(character.firstSeen)
            or not isInteger(character.lastSeen)
            or not isInteger(character.firstSeenUnits)
            or (character.transferredUnits ~= nil and not isInteger(character.transferredUnits))
            or (character.firstSeenLater ~= nil and type(character.firstSeenLater) ~= "boolean")
        then
            return false
        end
    end
    for _, observation in ipairs(record.observations) do
        if
            type(observation) ~= "table"
            or not isName(observation.character)
            or not isName(observation.realm)
            or not areas[observation.area]
            or not isInteger(observation.seenAt)
            or not isInteger(observation.quantity)
            or observation.quantity < 0
        then
            return false
        end
    end
    local gained = 0
    local gainIDs = {}
    for _, gain in ipairs(record.gains or {}) do
        if
            type(gain) ~= "table"
            or type(gain.id) ~= "string"
            or not isInteger(gain.at)
            or (gain.openedAt ~= nil and not isInteger(gain.openedAt))
            or (gain.baselinePossessionsComplete ~= nil and type(gain.baselinePossessionsComplete) ~= "boolean")
            or not isInteger(gain.quantity)
            or gain.quantity < 1
            or not isName(gain.character)
            or not isName(gain.realm)
            or not isInteger(gain.level)
            or type(gain.place) ~= "string"
            or not validPlaceKind(gain.placeKind)
            or not gainMethods[gain.method]
            or (gain.mailKind ~= nil and (gain.mailKind ~= "auction-purchase" or gain.method ~= "Obtained"))
            or (gain.channel ~= nil and gain.channel ~= "mail" and gain.channel ~= "trade" and gain.channel ~= "guild")
            or (gain.channel ~= nil and gain.method ~= "Obtained")
            or not validRefunded(gain)
            or gainIDs[gain.id]
        then
            return false
        end
        if gain.source ~= nil then
            if type(gain.source) ~= "table" or (gain.source.name ~= nil and not isName(gain.source.name)) then
                return false
            end
            if gain.method == "Looted" then
                if (gain.source.kind ~= "mob" and gain.source.kind ~= "container") or not isName(gain.source.guid) then
                    return false
                end
            elseif gain.method == "Vendor" then
                if gain.source.kind ~= "vendor" or not isName(gain.source.name) or gain.source.guid ~= nil then
                    return false
                end
            elseif gain.method == "Obtained" then
                if gain.source.kind ~= "player" or not isName(gain.source.name) or not isName(gain.source.realm) then
                    return false
                end
            else
                return false
            end
        end
        if gain.context ~= nil then
            if
                type(gain.context) ~= "table"
                or gain.method == "Looted"
                or gain.method == "Vendor"
                or gain.context.kind ~= (gain.method == "Quest" and "quest" or "recipe")
                or not isInteger(gain.context.id)
                or gain.context.id < 1
                or (gain.context.name ~= nil and not isName(gain.context.name))
            then
                return false
            end
        end
        gainIDs[gain.id] = true
        if gain.corrections ~= nil then
            if type(gain.corrections) ~= "table" then
                return false
            end
            local ids = {}
            for _, id in ipairs(gain.corrections) do
                if not isName(id) or ids[id] then
                    return false
                end
                ids[id] = true
            end
        end
        gained = gained + gain.quantity - (gain.refunded or 0)
    end
    if gained ~= record.totalGained then
        return false
    end
    if #record.gains > 0 and (not isInteger(record.firstGained) or not isInteger(record.lastGained)) then
        return false
    end
    return true
end

local function recoverableRecord(key, record)
    if
        type(key) ~= "string"
        or type(record) ~= "table"
        or record.key ~= key
        or not isInteger(record.itemID)
        or record.itemID <= 0
        or not isInteger(record.firstSeen)
        or not isInteger(record.lastSeen)
        or not isInteger(record.firstSeenUnits)
        or not isInteger(record.totalGained)
        or type(record.links) ~= "table"
        or type(record.characters) ~= "table"
        or type(record.observations) ~= "table"
        or type(record.gains) ~= "table"
        or #record.links == 0
        or #record.characters == 0
        or #record.observations == 0
    then
        return false
    end
    for _, gain in ipairs(record.gains) do
        if
            type(gain) ~= "table"
            or (gain.source ~= nil and type(gain.source) ~= "table")
            or (gain.context ~= nil and type(gain.context) ~= "table")
        then
            return false
        end
    end
    return true
end

local function validJournal(value)
    if
        type(value) ~= "table"
        or not isInteger(value.nextSequence)
        or value.nextSequence < 1
        or type(value.gains) ~= "table"
    then
        return false
    end
    local seen = {}
    for _, entry in ipairs(value.gains) do
        if
            type(entry) ~= "table"
            or not isName(entry.id)
            or not isName(entry.key)
            or not isInteger(entry.at)
            or not isInteger(entry.sequence)
            or entry.sequence < 1
            or entry.sequence >= value.nextSequence
            or seen[entry.sequence]
        then
            return false
        end
        seen[entry.sequence] = true
    end
    return true
end

StoreRecordCheck.validRefunded = validRefunded
StoreRecordCheck.validRecord = validRecord
StoreRecordCheck.recoverableRecord = recoverableRecord
StoreRecordCheck.validJournal = validJournal

addon.StoreRecordCheck = StoreRecordCheck
