local _, addon = ...

---@class AzerothLedgerObservation
---@field character string
---@field realm string
---@field area 'bags'|'bank'|'equipped'
---@field quantity integer
---@field seenAt integer

---@class AzerothLedgerCharacterSeen
---@field name string
---@field realm string
---@field firstSeen integer
---@field lastSeen integer
---@field firstSeenUnits integer

---@class AzerothLedgerAreaState
---@field seenAt integer
---@field complete boolean

---@class AzerothLedgerScanItem
---@field itemID integer
---@field link string
---@field quantity integer

---@class AzerothLedgerSnapshot
---@field character string
---@field realm string
---@field area 'bags'|'bank'|'equipped'
---@field seenAt integer
---@field complete boolean
---@field items AzerothLedgerScanItem[]

---@class AzerothLedgerLootSource
---@field kind 'mob'|'container'
---@field guid string
---@field name? string

---@class AzerothLedgerGain
---@field id string
---@field at integer
---@field quantity integer
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field method 'Looted'
---@field source? AzerothLedgerLootSource

---@class AzerothLedgerLootSlot
---@field key string
---@field source? AzerothLedgerLootSource
---@field quantity? integer

---@class AzerothLedgerLootContext
---@field character string
---@field realm string
---@field at integer
---@field level integer
---@field place string
---@field slots AzerothLedgerLootSlot[]

---@class AzerothLedgerLootClaim
---@field key string
---@field quantity integer

---@class AzerothLedgerLootReceipt: AzerothLedgerLootClaim
---@field itemID integer
---@field link string

---@class AzerothLedgerLootSessionSlot
---@field source? AzerothLedgerLootSource
---@field limit? integer

---@class AzerothLedgerLootSession
---@field id integer
---@field openedAt integer
---@field closedAt? integer
---@field endedAt? integer
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field slots table<string, AzerothLedgerLootSessionSlot>
---@field credits table<string, integer>
---@field baselineQuantities table<string, integer>
---@field receipts table<string, {quantity: integer, at: integer}>
---@field awarded table<string, integer>
---@field discoveries table<string, boolean>

---@class AzerothLedgerLootState
---@field nextID integer
---@field sessions AzerothLedgerLootSession[]

---@class AzerothLedgerRecord
---@field key string
---@field itemID integer
---@field firstSeen integer
---@field lastSeen integer
---@field firstSeenUnits integer
---@field totalGained integer
---@field gains AzerothLedgerGain[]
---@field firstGained? integer
---@field lastGained? integer
---@field links string[]
---@field characters AzerothLedgerCharacterSeen[]
---@field observations AzerothLedgerObservation[]

---@class AzerothLedgerData
---@field schema integer
---@field marker? string
---@field environment? AzerothLedgerEnvironment
---@field records table<string, AzerothLedgerRecord>
---@field areas table<string, AzerothLedgerAreaState>
---@field loot? AzerothLedgerLootState

---@class AzerothLedgerEnvironment
---@field build string
---@field interface string
---@field locale string
---@field revision string

---@class AzerothLedgerDiagnostic
---@field kind 'healthy'|'damaged'|'unsupported'
---@field damagedCount integer
---@field schema? integer

---@class AzerothLedgerStore
---@field diagnostic fun(self: AzerothLedgerStore): AzerothLedgerDiagnostic
---@field marker fun(self: AzerothLedgerStore): string?
---@field environment fun(self: AzerothLedgerStore): AzerothLedgerEnvironment?
---@field list fun(self: AzerothLedgerStore): AzerothLedgerRecord[]
---@field find fun(self: AzerothLedgerStore, key: string): AzerothLedgerRecord?
---@field area fun(self: AzerothLedgerStore, character: string, realm: string, area: string): AzerothLedgerAreaState?
---@field setMarker fun(self: AzerothLedgerStore, marker: string): boolean
---@field setEnvironment fun(self: AzerothLedgerStore, environment: AzerothLedgerEnvironment): boolean
---@field scan fun(self: AzerothLedgerStore, snapshot: AzerothLedgerSnapshot): boolean
---@field lootOpen fun(self: AzerothLedgerStore, context: AzerothLedgerLootContext): boolean
---@field lootClose fun(self: AzerothLedgerStore, at: integer): boolean
---@field lootReceipt fun(self: AzerothLedgerStore, receipt: AzerothLedgerLootClaim, at: integer, character: string, realm: string): boolean

local CURRENT_SCHEMA = 2
local areas = { bags = true, bank = true, equipped = true }

local function isInteger(value)
    return type(value) == "number" and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

local function isName(value)
    return type(value) == "string" and #value > 0 and #value <= 128
end

local function areaKey(character, realm, area)
    return realm .. ":" .. character .. ":" .. area
end

local function copyArray(source)
    local result = {}
    for index, value in ipairs(source) do
        if type(value) == "table" then
            local entry = {}
            for key, field in pairs(value) do
                entry[key] = field
            end
            result[index] = entry
        else
            result[index] = value
        end
    end
    return result
end

local function copyRecord(record)
    local gains = {}
    for index, gain in ipairs(record.gains or {}) do
        gains[index] = {
            id = gain.id,
            at = gain.at,
            quantity = gain.quantity,
            character = gain.character,
            realm = gain.realm,
            level = gain.level,
            place = gain.place,
            method = gain.method,
            source = gain.source and { kind = gain.source.kind, guid = gain.source.guid, name = gain.source.name }
                or nil,
        }
    end
    return {
        key = record.key,
        itemID = record.itemID,
        firstSeen = record.firstSeen,
        lastSeen = record.lastSeen,
        firstSeenUnits = record.firstSeenUnits,
        totalGained = record.totalGained,
        gains = gains,
        firstGained = record.firstGained,
        lastGained = record.lastGained,
        links = copyArray(record.links),
        characters = copyArray(record.characters),
        observations = copyArray(record.observations),
    }
end

local function validRecord(key, record)
    if
        type(key) ~= "string"
        or type(record) ~= "table"
        or record.key ~= key
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
            or not isInteger(gain.quantity)
            or gain.quantity < 1
            or not isName(gain.character)
            or not isName(gain.realm)
            or not isInteger(gain.level)
            or type(gain.place) ~= "string"
            or gain.method ~= "Looted"
            or gainIDs[gain.id]
        then
            return false
        end
        if gain.source ~= nil then
            if
                type(gain.source) ~= "table"
                or (gain.source.kind ~= "mob" and gain.source.kind ~= "container")
                or not isName(gain.source.guid)
                or (gain.source.name ~= nil and not isName(gain.source.name))
            then
                return false
            end
        end
        gainIDs[gain.id] = true
        gained = gained + gain.quantity
    end
    if gained ~= record.totalGained then
        return false
    end
    if gained > 0 and (not isInteger(record.firstGained) or not isInteger(record.lastGained)) then
        return false
    end
    return true
end

local function validEnvironment(environment)
    return type(environment) == "table"
        and isName(environment.build)
        and #environment.build <= 64
        and isName(environment.interface)
        and #environment.interface <= 32
        and isName(environment.locale)
        and #environment.locale <= 16
        and isName(environment.revision)
        and #environment.revision <= 64
end

local Schema = {}

---@param raw any
---@param save fun(value: AzerothLedgerData)
---@return AzerothLedgerStore
function Schema.open(raw, save)
    if raw == nil then
        raw = { schema = CURRENT_SCHEMA, records = {}, areas = {} }
        save(raw)
    end
    local supported = type(raw) == "table" and raw.schema == CURRENT_SCHEMA
    local readable = supported and type(raw.records) == "table" and type(raw.areas) == "table"
    local valid = {}
    local damagedCount = 0
    if readable then
        for key, record in pairs(raw.records) do
            if validRecord(key, record) then
                valid[key] = copyRecord(record)
            else
                damagedCount = damagedCount + 1
            end
        end
        for key, state in pairs(raw.areas) do
            if
                type(key) ~= "string"
                or type(state) ~= "table"
                or not isInteger(state.seenAt)
                or type(state.complete) ~= "boolean"
            then
                damagedCount = damagedCount + 1
            end
        end
    elseif supported then
        damagedCount = 1
    end
    if supported and raw.environment ~= nil and not validEnvironment(raw.environment) then
        damagedCount = damagedCount + 1
    end

    local function saveFields(fields)
        local nextValue = {
            schema = CURRENT_SCHEMA,
            marker = fields.marker or raw.marker,
            environment = fields.environment or raw.environment,
            records = fields.records or raw.records,
            areas = fields.areas or raw.areas,
            loot = fields.loot or raw.loot,
        }
        save(nextValue)
        raw = nextValue
    end

    local store = {}

    function store.diagnostic(_self)
        if not supported then
            return { kind = "unsupported", damagedCount = 0, schema = type(raw) == "table" and raw.schema or nil }
        end
        local markerDamaged = raw.marker ~= nil and (not isName(raw.marker) or #raw.marker > 64)
        return {
            kind = (damagedCount > 0 or markerDamaged) and "damaged" or "healthy",
            damagedCount = damagedCount + (markerDamaged and 1 or 0),
            schema = CURRENT_SCHEMA,
        }
    end

    function store.marker(_self)
        return supported and isName(raw.marker) and #raw.marker <= 64 and raw.marker or nil
    end

    function store.environment(_self)
        if not supported or not validEnvironment(raw.environment) then
            return nil
        end
        local result = {}
        for key, value in pairs(raw.environment) do
            result[key] = value
        end
        return result
    end

    function store.list(_self)
        local result = {}
        for _, record in pairs(valid) do
            result[#result + 1] = copyRecord(record)
        end
        table.sort(result, function(left, right)
            return left.itemID < right.itemID or (left.itemID == right.itemID and left.key < right.key)
        end)
        return result
    end

    function store.find(_self, key)
        local record = valid[key]
        return record and copyRecord(record) or nil
    end

    function store.area(_self, character, realm, area)
        if not readable or not isName(character) or not isName(realm) or not areas[area] then
            return nil
        end
        local state = raw.areas[areaKey(character, realm, area)]
        if type(state) ~= "table" or not isInteger(state.seenAt) or type(state.complete) ~= "boolean" then
            return nil
        end
        return { seenAt = state.seenAt, complete = state.complete }
    end

    function store.setMarker(_self, marker)
        if not readable or not isName(marker) or #marker > 64 then
            return false
        end
        saveFields({ marker = marker })
        return true
    end

    function store.setEnvironment(_self, environment)
        if not readable or not validEnvironment(environment) then
            return false
        end
        saveFields({ environment = environment })
        return true
    end

    local function sessionIsLive(session, at)
        return type(session) == "table"
            and isInteger(session.openedAt)
            and isInteger(session.id)
            and isName(session.character)
            and isName(session.realm)
            and type(session.slots) == "table"
            and type(session.credits) == "table"
            and type(session.receipts) == "table"
            and type(session.awarded) == "table"
            and type(session.discoveries) == "table"
            and type(session.baselineQuantities) == "table"
            and (session.closedAt == nil or isInteger(session.closedAt))
            and (session.endedAt == nil or isInteger(session.endedAt))
            and isInteger(at)
            and at >= session.openedAt
            and (
                (session.closedAt == nil and session.endedAt == nil)
                or at <= (session.closedAt or session.endedAt) + 120
            )
    end

    local function activeSession(at)
        local loot = raw.loot
        local sessions = type(loot) == "table" and loot.sessions or nil
        if type(sessions) == "table" then
            for index = #sessions, 1, -1 do
                local session = sessions[index]
                if sessionIsLive(session, at) and (not session.endedAt or at < session.endedAt) then
                    return session
                end
            end
        end
        return nil
    end

    local function receiptSession(key, at, character, realm)
        local loot = raw.loot
        local sessions = type(loot) == "table" and loot.sessions or nil
        if type(sessions) ~= "table" then
            return nil
        end
        local latest
        for _, session in ipairs(sessions) do
            if
                sessionIsLive(session, at)
                and session.character == character
                and session.realm == realm
                and type(session.slots[key]) == "table"
            then
                latest = session
                local credit = isInteger(session.credits[key]) and session.credits[key] or 0
                local awarded = isInteger(session.awarded[key]) and session.awarded[key] or 0
                local limit = session.slots[key].limit
                local capacity = math.min(credit, isInteger(limit) and limit or math.huge)
                if capacity > awarded then
                    return session
                end
            end
        end
        return latest
    end

    local function award(session, key, records)
        local receipt = session.receipts[key]
        local record = records[key]
        if type(receipt) ~= "table" or not isInteger(receipt.quantity) or not isInteger(receipt.at) or not record then
            return
        end
        local awarded = isInteger(session.awarded[key]) and session.awarded[key] or 0
        local credit = isInteger(session.credits[key]) and session.credits[key] or 0
        local slot = session.slots[key]
        local limit = type(slot) == "table" and slot.limit or nil
        local target = math.min(credit, receipt.quantity, isInteger(limit) and limit or math.huge)
        local quantity = target - awarded
        if quantity <= 0 then
            return
        end
        record = copyRecord(record)
        local gainID = tostring(session.id) .. ":" .. key
        local gain
        for _, entry in ipairs(record.gains) do
            if entry.id == gainID then
                gain = entry
                break
            end
        end
        if gain then
            gain.quantity = gain.quantity + quantity
        else
            gain = {
                id = gainID,
                at = receipt.at,
                quantity = quantity,
                character = session.character,
                realm = session.realm,
                level = session.level,
                place = session.place,
                method = "Looted",
                source = type(session.slots[key]) == "table" and session.slots[key].source or nil,
            }
            record.gains[#record.gains + 1] = gain
        end
        record.totalGained = record.totalGained + quantity
        record.firstGained = record.firstGained and math.min(record.firstGained, gain.at) or gain.at
        record.lastGained = record.lastGained and math.max(record.lastGained, gain.at) or gain.at
        if session.discoveries[key] then
            record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
            for _, character in ipairs(record.characters) do
                if character.name == session.character and character.realm == session.realm then
                    character.firstSeenUnits = math.max(0, character.firstSeenUnits - quantity)
                    break
                end
            end
        end
        session.awarded[key] = target
        records[key] = record
    end

    ---@param context AzerothLedgerLootContext
    function store.lootOpen(_self, context)
        if
            not readable
            or type(context) ~= "table"
            or not isName(context.character)
            or not isName(context.realm)
            or not isInteger(context.at)
            or not isInteger(context.level)
            or type(context.place) ~= "string"
            or type(context.slots) ~= "table"
        then
            return false
        end
        local baseline = store:area(context.character, context.realm, "bags")
        if not baseline or not baseline.complete then
            return false
        end
        local slots = {}
        local baselineQuantities = {}
        for _, slot in ipairs(context.slots) do
            if type(slot) == "table" and type(slot.key) == "string" then
                if slots[slot.key] then
                    slots[slot.key].source = nil
                    if slots[slot.key].limit and isInteger(slot.quantity) and slot.quantity > 0 then
                        slots[slot.key].limit = slots[slot.key].limit + slot.quantity
                    else
                        slots[slot.key].limit = nil
                    end
                else
                    slots[slot.key] = {
                        source = slot.source,
                        limit = isInteger(slot.quantity) and slot.quantity > 0 and slot.quantity or nil,
                    }
                    local record = valid[slot.key]
                    for _, observation in ipairs(record and record.observations or {}) do
                        if
                            observation.character == context.character
                            and observation.realm == context.realm
                            and observation.area == "bags"
                        then
                            baselineQuantities[slot.key] = observation.quantity
                        end
                    end
                end
            end
        end
        local loot = type(raw.loot) == "table" and raw.loot or nil
        local previousID = loot and loot.nextID or nil
        local nextID = (isInteger(previousID) and previousID or 0) + 1
        local sessions = {}
        for _, session in ipairs(loot and loot.sessions or {}) do
            if sessionIsLive(session, context.at) then
                if not session.endedAt then
                    session.endedAt = context.at
                end
                for key, slot in pairs(slots) do
                    if type(session.slots[key]) == "table" then
                        slot.source = nil
                        session.slots[key].source = nil
                    end
                end
                sessions[#sessions + 1] = session
            end
        end
        sessions[#sessions + 1] = {
            id = nextID,
            openedAt = context.at,
            character = context.character,
            realm = context.realm,
            level = context.level,
            place = context.place,
            slots = slots,
            credits = {},
            baselineQuantities = baselineQuantities,
            receipts = {},
            awarded = {},
            discoveries = {},
        }
        saveFields({
            loot = {
                nextID = nextID,
                sessions = sessions,
            },
        })
        return true
    end

    ---@param receipt AzerothLedgerLootClaim
    ---@param at integer
    ---@param character string
    ---@param realm string
    function store.lootReceipt(_self, receipt, at, character, realm)
        local session = type(receipt) == "table" and receiptSession(receipt.key, at, character, realm) or nil
        if
            not readable
            or not session
            or type(receipt) ~= "table"
            or type(receipt.key) ~= "string"
            or type(session.slots[receipt.key]) ~= "table"
            or not isInteger(receipt.quantity)
            or receipt.quantity < 1
        then
            return false
        end
        local existing = session.receipts[receipt.key]
        session.receipts[receipt.key] = {
            quantity = (existing and existing.quantity or 0) + receipt.quantity,
            at = existing and existing.at or at,
        }
        local nextRecords = {}
        for key, record in pairs(raw.records) do
            nextRecords[key] = record
        end
        award(session, receipt.key, nextRecords)
        saveFields({ records = nextRecords })
        if nextRecords[receipt.key] then
            valid[receipt.key] = copyRecord(nextRecords[receipt.key])
        end
        return true
    end

    function store.lootClose(_self, at)
        local session = activeSession(at)
        if not readable or not session then
            return false
        end
        if not session.closedAt then
            session.closedAt = at
            saveFields({})
        end
        return true
    end

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
        local grouped = {}
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
                return false
            end
            local group = grouped[key] or { itemID = item.itemID, quantity = 0, links = {} }
            group.quantity = group.quantity + item.quantity
            group.links[item.link] = true
            grouped[key] = group
        end
        local scopeKey = areaKey(snapshot.character, snapshot.realm, snapshot.area)
        local oldScope = raw.areas[scopeKey]
        if type(oldScope) == "table" and isInteger(oldScope.seenAt) and snapshot.seenAt < oldScope.seenAt then
            return false
        end
        local nextRecords = {}
        for key, record in pairs(raw.records) do
            nextRecords[key] = record
        end
        for key, group in pairs(grouped) do
            local session = snapshot.area == "bags" and snapshot.complete and activeSession(snapshot.seenAt) or nil
            if session and (session.character ~= snapshot.character or session.realm ~= snapshot.realm) then
                session = nil
            end
            if session and type(oldScope) == "table" and oldScope.complete then
                local baselineQuantity = isInteger(session.baselineQuantities[key]) and session.baselineQuantities[key]
                    or 0
                local increase = group.quantity - baselineQuantity
                if increase > 0 and type(session.slots[key]) == "table" then
                    local credit = isInteger(session.credits[key]) and session.credits[key] or 0
                    session.credits[key] = math.max(credit, increase)
                    if not valid[key] then
                        session.discoveries[key] = true
                    end
                end
            end
            local record = valid[key] and copyRecord(valid[key])
                or {
                    key = key,
                    itemID = group.itemID,
                    firstSeen = snapshot.seenAt,
                    lastSeen = snapshot.seenAt,
                    firstSeenUnits = group.quantity,
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
            local characterFound = false
            for _, character in ipairs(record.characters) do
                if character.name == snapshot.character and character.realm == snapshot.realm then
                    characterFound = true
                    if snapshot.seenAt > character.lastSeen then
                        character.lastSeen = snapshot.seenAt
                    end
                    break
                end
            end
            if not characterFound then
                record.characters[#record.characters + 1] = {
                    name = snapshot.character,
                    realm = snapshot.realm,
                    firstSeen = snapshot.seenAt,
                    lastSeen = snapshot.seenAt,
                    firstSeenUnits = group.quantity,
                }
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
            end
            nextRecords[key] = record
            if session then
                award(session, key, nextRecords)
            end
        end
        if snapshot.complete then
            for key, existing in pairs(valid) do
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
                        local record = copyRecord(existing)
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
        local nextAreas = {}
        for key, state in pairs(raw.areas) do
            nextAreas[key] = state
        end
        nextAreas[scopeKey] = { seenAt = snapshot.seenAt, complete = snapshot.complete }
        saveFields({ records = nextRecords, areas = nextAreas })
        for key, record in pairs(nextRecords) do
            if valid[key] or grouped[key] then
                valid[key] = copyRecord(record)
            end
        end
        return true
    end

    return store
end

addon.Schema = Schema
