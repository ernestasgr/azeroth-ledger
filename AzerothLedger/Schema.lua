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
---@field character? string
---@field realm? string

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
---@field method 'Looted'|'Quest'|'Crafted'|'Vendor'
---@field refunded? integer
---@field source? AzerothLedgerLootSource
---@field context? {kind: 'quest'|'recipe', id: integer, name?: string}

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

---@class AzerothLedgerActor
---@field character string
---@field realm string

---@alias ALActor AzerothLedgerActor

---@alias ALClaim AzerothLedgerLootClaim

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
---@field baselineGains table<string, integer>
---@field receipts table<string, {quantity: integer, at: integer}>
---@field awarded table<string, integer>
---@field discoveries table<string, boolean>

---@class AzerothLedgerLootState
---@field nextID integer
---@field sessions AzerothLedgerLootSession[]

---@class AzerothLedgerRewardContext
---@field kind 'quest'|'recipe'
---@field id integer
---@field name? string

---@class AzerothLedgerRewardReceipt
---@field key string
---@field quantity integer
---@field method 'Quest'|'Crafted'
---@field context? AzerothLedgerRewardContext
---@field preview? boolean
---@field choiceGroup? string

---@alias ALReward AzerothLedgerRewardReceipt

---@class AzerothLedgerGainActor: AzerothLedgerActor
---@field level integer
---@field place string

---@alias ALGainActor AzerothLedgerGainActor

---@class AzerothLedgerRewardSession
---@field id integer
---@field key string
---@field method 'Quest'|'Crafted'
---@field context? AzerothLedgerRewardContext
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field at integer
---@field baseline integer
---@field baselineGained integer
---@field quantity integer
---@field awarded integer
---@field discovery boolean
---@field confirmed boolean
---@field choiceGroup? string
---@field specific? boolean
---@field ambiguous? boolean

---@class AzerothLedgerRewardState
---@field nextID integer
---@field sessions AzerothLedgerRewardSession[]

---@class AzerothLedgerVendorIntent
---@field kind 'purchase'|'sale'|'refund'|'buyback'
---@field key string
---@field itemID integer
---@field link string
---@field quantity integer
---@field area? 'bags'|'equipped'

---@alias ALVendorIntent AzerothLedgerVendorIntent

---@class AzerothLedgerVendorAction: AzerothLedgerVendorIntent
---@field id integer
---@field at integer
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field baseline integer
---@field baselineGained integer
---@field receiptQuantity integer
---@field status 'pending'|'confirmed'|'unresolved'
---@field area 'bags'|'equipped'
---@field linkedGainID? string
---@field linkedSaleID? integer
---@field restored? boolean

---@class AzerothLedgerVendorActivity
---@field id integer
---@field kind 'sale'|'refund'|'buyback'
---@field key string
---@field quantity integer
---@field at integer
---@field character string
---@field realm string

---@class AzerothLedgerVendorState
---@field nextID integer
---@field actions AzerothLedgerVendorAction[]
---@field journal AzerothLedgerVendorActivity[]

---@class AzerothLedgerVendorEvidence
---@field id integer
---@field kind 'purchase'|'sale'|'refund'|'buyback'
---@field key string
---@field quantity integer
---@field at integer
---@field status 'pending'|'unresolved'
---@field character string
---@field realm string

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
---@field rewards? AzerothLedgerRewardState
---@field vendor? AzerothLedgerVendorState

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
---@field characters fun(self: AzerothLedgerStore): AzerothLedgerActor[]
---@field setMarker fun(self: AzerothLedgerStore, marker: string): boolean
---@field setEnvironment fun(self: AzerothLedgerStore, environment: AzerothLedgerEnvironment): boolean
---@field scan fun(self: AzerothLedgerStore, snapshot: AzerothLedgerSnapshot): boolean
---@field lootOpen fun(self: AzerothLedgerStore, context: AzerothLedgerLootContext): boolean
---@field lootClose fun(self: AzerothLedgerStore, at: integer): boolean
---@field lootReceipt fun(self: AzerothLedgerStore, receipt: ALClaim, at: integer, actor: AzerothLedgerActor): boolean
---@field rewardReceipt fun(self: AzerothLedgerStore, receipt: ALReward, at: integer, actor: ALGainActor): boolean
---@field questTurnedIn fun(self: AzerothLedgerStore, questID: integer, at: integer, actor: ALActor): boolean
---@field vendorAction fun(self: AzerothLedgerStore, action: ALVendorIntent, at: integer, actor: ALGainActor): boolean
---@field vendorReceipt fun(self: AzerothLedgerStore, receipt: ALClaim, at: integer, actor: ALActor): boolean
---@field vendorActivity fun(self: AzerothLedgerStore): AzerothLedgerVendorActivity[]
---@field vendorUnresolved fun(self: AzerothLedgerStore): AzerothLedgerVendorEvidence[]
---@field pruneJournal fun(self: AzerothLedgerStore, limit: integer): boolean

local CURRENT_SCHEMA = 2
local areas = { bags = true, bank = true, equipped = true }
local gainMethods = { Looted = true, Quest = true, Crafted = true, Vendor = true }

local function isInteger(value)
    return type(value) == "number" and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

local function isName(value)
    return type(value) == "string" and #value > 0 and #value <= 128
end

local function validRefunded(gain)
    return gain.refunded == nil
        or (
            gain.method == "Vendor"
            and isInteger(gain.refunded)
            and gain.refunded >= 0
            and gain.refunded <= gain.quantity
        )
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
            refunded = gain.refunded,
            source = gain.source and { kind = gain.source.kind, guid = gain.source.guid, name = gain.source.name }
                or nil,
            context = gain.context and { kind = gain.context.kind, id = gain.context.id, name = gain.context.name }
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
            or not gainMethods[gain.method]
            or not validRefunded(gain)
            or gainIDs[gain.id]
        then
            return false
        end
        if gain.source ~= nil then
            if
                gain.method ~= "Looted"
                or type(gain.source) ~= "table"
                or (gain.source.name ~= nil and not isName(gain.source.name))
            then
                return false
            end
            if (gain.source.kind ~= "mob" and gain.source.kind ~= "container") or not isName(gain.source.guid) then
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

local function validRewardContext(context, method)
    return context == nil
        or (
            type(context) == "table"
            and context.kind == (method == "Quest" and "quest" or "recipe")
            and isInteger(context.id)
            and context.id > 0
            and (context.name == nil or isName(context.name))
        )
end

local function validRewardSession(session)
    return type(session) == "table"
        and isInteger(session.id)
        and session.id > 0
        and type(session.key) == "string"
        and (session.method == "Quest" or session.method == "Crafted")
        and validRewardContext(session.context, session.method)
        and isName(session.character)
        and isName(session.realm)
        and isInteger(session.level)
        and type(session.place) == "string"
        and isInteger(session.at)
        and isInteger(session.baseline)
        and session.baseline >= 0
        and isInteger(session.baselineGained)
        and session.baselineGained >= 0
        and isInteger(session.quantity)
        and session.quantity > 0
        and isInteger(session.awarded)
        and session.awarded >= 0
        and session.awarded <= session.quantity
        and type(session.discovery) == "boolean"
        and type(session.confirmed) == "boolean"
        and (session.choiceGroup == nil or (type(session.choiceGroup) == "string" and session.choiceGroup ~= ""))
        and (session.specific == nil or type(session.specific) == "boolean")
        and (session.ambiguous == nil or type(session.ambiguous) == "boolean")
end

local function validRewardState(rewards)
    if type(rewards) ~= "table" or not isInteger(rewards.nextID) or type(rewards.sessions) ~= "table" then
        return false
    end
    for _, session in ipairs(rewards.sessions) do
        if not validRewardSession(session) then
            return false
        end
    end
    return true
end

local vendorKinds = { purchase = true, sale = true, refund = true, buyback = true }
local vendorStatuses = { pending = true, confirmed = true, unresolved = true }

local function validVendorState(vendor)
    if
        type(vendor) ~= "table"
        or not isInteger(vendor.nextID)
        or vendor.nextID < 1
        or type(vendor.actions) ~= "table"
        or type(vendor.journal) ~= "table"
    then
        return false
    end
    local ids = {}
    for _, action in ipairs(vendor.actions) do
        if
            type(action) ~= "table"
            or not isInteger(action.id)
            or action.id < 1
            or action.id >= vendor.nextID
            or ids[action.id]
            or not vendorKinds[action.kind]
            or not vendorStatuses[action.status]
            or (action.area ~= "bags" and action.area ~= "equipped")
            or type(action.key) ~= "string"
            or not isInteger(action.itemID)
            or addon.Item.key(action.link, action.itemID) ~= action.key
            or not isInteger(action.quantity)
            or action.quantity < 1
            or not isInteger(action.at)
            or not isName(action.character)
            or not isName(action.realm)
            or not isInteger(action.level)
            or type(action.place) ~= "string"
            or not isInteger(action.baseline)
            or action.baseline < 0
            or not isInteger(action.baselineGained)
            or action.baselineGained < 0
            or not isInteger(action.receiptQuantity)
            or action.receiptQuantity < 0
            or (action.linkedGainID ~= nil and type(action.linkedGainID) ~= "string")
            or (action.linkedSaleID ~= nil and not isInteger(action.linkedSaleID))
            or (action.restored ~= nil and type(action.restored) ~= "boolean")
        then
            return false
        end
        ids[action.id] = true
    end
    for _, entry in ipairs(vendor.journal) do
        if
            type(entry) ~= "table"
            or not isInteger(entry.id)
            or not vendorKinds[entry.kind]
            or entry.kind == "purchase"
            or type(entry.key) ~= "string"
            or not isInteger(entry.quantity)
            or entry.quantity < 1
            or not isInteger(entry.at)
            or not isName(entry.character)
            or not isName(entry.realm)
        then
            return false
        end
    end
    return true
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
            elseif recoverableRecord(key, record) then
                valid[key] = copyRecord(record)
                damagedCount = damagedCount + 1
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
                or (state.character ~= nil and not isName(state.character))
                or (state.realm ~= nil and not isName(state.realm))
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
    if supported and raw.rewards ~= nil and not validRewardState(raw.rewards) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.vendor ~= nil and not validVendorState(raw.vendor) then
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
            rewards = fields.rewards or raw.rewards,
            vendor = fields.vendor or raw.vendor,
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

    function store.characters(_self)
        local result = {}
        local seen = {}
        local function add(character, realm)
            local key = areaKey(character, realm, "")
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = { character = character, realm = realm }
            end
        end
        if readable then
            for _, state in pairs(raw.areas) do
                if type(state) == "table" and isName(state.character) and isName(state.realm) then
                    add(state.character, state.realm)
                end
            end
            for _, record in pairs(valid) do
                for _, character in ipairs(record.characters) do
                    add(character.name, character.realm)
                end
            end
        end
        table.sort(result, function(left, right)
            return left.realm < right.realm or (left.realm == right.realm and left.character < right.character)
        end)
        return result
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
            and type(session.baselineGains) == "table"
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

    local function receiptSession(key, at, actor)
        local loot = raw.loot
        local sessions = type(loot) == "table" and loot.sessions or nil
        if type(sessions) ~= "table" then
            return nil
        end
        local latest
        for _, session in ipairs(sessions) do
            if
                sessionIsLive(session, at)
                and session.character == actor.character
                and session.realm == actor.realm
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
        local baselineGained = session.baselineGains[key]
        if not isInteger(baselineGained) then
            return
        end
        local otherGains = math.max(0, record.totalGained - baselineGained - awarded)
        target = math.min(target, math.max(0, credit - otherGains))
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
        local baselineGains = {}
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
                    baselineGains[slot.key] = record and record.totalGained or 0
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
            baselineGains = baselineGains,
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
    ---@param actor AzerothLedgerActor
    function store.lootReceipt(_self, receipt, at, actor)
        local session = type(receipt) == "table" and type(actor) == "table" and receiptSession(receipt.key, at, actor)
            or nil
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
        local rewards = type(raw.rewards) == "table" and raw.rewards.sessions or nil
        for _, reward in ipairs(type(rewards) == "table" and rewards or {}) do
            if
                validRewardSession(reward)
                and reward.confirmed
                and reward.key == receipt.key
                and reward.character == actor.character
                and reward.realm == actor.realm
                and at >= reward.at
                and at - reward.at <= 120
            then
                local current = activeSession(at)
                if
                    not current
                    or current.openedAt <= reward.at
                    or type(current.slots[receipt.key]) ~= "table"
                    or current.character ~= actor.character
                    or current.realm ~= actor.realm
                then
                    return true
                end
                session = current
            end
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

    local function areaQuantity(record, character, realm, area)
        local quantity = 0
        for _, observation in ipairs(record and record.observations or {}) do
            if observation.character == character and observation.realm == realm and observation.area == area then
                quantity = observation.quantity
            end
        end
        return quantity
    end

    local function bagQuantity(record, character, realm)
        return areaQuantity(record, character, realm, "bags")
    end

    local function vendorState()
        if raw.vendor == nil then
            return { nextID = 1, actions = {}, journal = {} }
        end
        if validVendorState(raw.vendor) then
            return raw.vendor
        end
        return nil
    end

    local function vendorResult(state, action, status)
        action.status = status
        if status == "confirmed" and action.kind ~= "purchase" then
            state.journal[#state.journal + 1] = {
                id = action.id,
                kind = action.kind,
                key = action.key,
                quantity = action.quantity,
                at = action.at,
                character = action.character,
                realm = action.realm,
            }
            while #state.journal > 50 do
                table.remove(state.journal, 1)
            end
        end
    end

    local function linkedVendorGain(record, character, realm, quantity)
        local match
        for _, gain in ipairs(record and record.gains or {}) do
            if
                gain.method == "Vendor"
                and gain.character == character
                and gain.realm == realm
                and gain.quantity - (gain.refunded or 0) >= quantity
            then
                if match then
                    return nil
                end
                match = gain.id
            end
        end
        return match
    end

    function store.vendorAction(_self, action, at, actor)
        if
            not readable
            or type(action) ~= "table"
            or not vendorKinds[action.kind]
            or not isInteger(action.itemID)
            or action.itemID < 1
            or addon.Item.key(action.link, action.itemID) ~= action.key
            or not isInteger(action.quantity)
            or action.quantity < 1
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
            or not isInteger(actor.level)
            or type(actor.place) ~= "string"
        then
            return false
        end
        local actionArea = action.area or "bags"
        if actionArea ~= "bags" and (actionArea ~= "equipped" or action.kind ~= "refund") then
            return false
        end
        local scope = store:area(actor.character, actor.realm, actionArea)
        if not scope or not scope.complete then
            return false
        end
        local record = valid[action.key]
        if record and not validRecord(action.key, record) then
            return false
        end
        local state = vendorState()
        if not state then
            return false
        end
        for _, previous in ipairs(state.actions) do
            if
                previous.status == "pending"
                and previous.key == action.key
                and previous.character == actor.character
                and previous.realm == actor.realm
            then
                vendorResult(state, previous, "unresolved")
            end
        end
        local entry = {
            id = state.nextID,
            kind = action.kind,
            key = action.key,
            itemID = action.itemID,
            link = action.link,
            quantity = action.quantity,
            at = at,
            character = actor.character,
            realm = actor.realm,
            level = actor.level,
            place = actor.place,
            baseline = areaQuantity(record, actor.character, actor.realm, actionArea),
            baselineGained = record and record.totalGained or 0,
            receiptQuantity = 0,
            status = "pending",
            area = actionArea,
        }
        if action.kind == "refund" then
            entry.linkedGainID = linkedVendorGain(record, actor.character, actor.realm, action.quantity)
            if not entry.linkedGainID then
                entry.status = "unresolved"
            end
        elseif action.kind == "buyback" then
            local match
            for _, sale in ipairs(state.actions) do
                if
                    sale.kind == "sale"
                    and sale.status == "confirmed"
                    and not sale.restored
                    and sale.key == action.key
                    and sale.quantity == action.quantity
                    and sale.character == actor.character
                    and sale.realm == actor.realm
                then
                    if match then
                        match = nil
                        break
                    end
                    match = sale
                end
            end
            entry.linkedSaleID = match and match.id or nil
            if not entry.linkedSaleID then
                entry.status = "unresolved"
            end
        end
        state.nextID = state.nextID + 1
        state.actions[#state.actions + 1] = entry
        saveFields({ vendor = state })
        return true
    end

    local function settleVendor(state, area, at, character, realm, grouped, records)
        for _, action in ipairs(state.actions) do
            if
                action.status == "pending"
                and action.area == area
                and action.character == character
                and action.realm == realm
                and at >= action.at
                and at - action.at <= 120
            then
                local group = grouped[action.key]
                local current = group and group.quantity or 0
                local delta = current - action.baseline
                local record = records[action.key]
                if action.kind == "purchase" then
                    if delta > 0 and record then
                        local otherGains = math.max(0, record.totalGained - action.baselineGained)
                        local quantity = math.min(action.quantity, delta - otherGains)
                        if quantity > 0 then
                            record = copyRecord(record)
                            local gain = {
                                id = "vendor:" .. action.id .. ":" .. action.key,
                                at = action.at,
                                quantity = quantity,
                                character = action.character,
                                realm = action.realm,
                                level = action.level,
                                place = action.place,
                                method = "Vendor",
                            }
                            record.gains[#record.gains + 1] = gain
                            record.totalGained = record.totalGained + quantity
                            record.firstGained = record.firstGained and math.min(record.firstGained, action.at)
                                or action.at
                            record.lastGained = record.lastGained and math.max(record.lastGained, action.at)
                                or action.at
                            if not valid[action.key] then
                                record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
                                for _, seen in ipairs(record.characters) do
                                    if seen.name == action.character and seen.realm == action.realm then
                                        seen.firstSeenUnits = math.max(0, seen.firstSeenUnits - quantity)
                                        break
                                    end
                                end
                            end
                            records[action.key] = record
                            vendorResult(state, action, "confirmed")
                        end
                    end
                elseif action.kind == "refund" and delta == -action.quantity and record then
                    record = copyRecord(record)
                    local linked
                    for _, gain in ipairs(record.gains) do
                        if
                            gain.id == action.linkedGainID
                            and gain.method == "Vendor"
                            and gain.quantity - (gain.refunded or 0) >= action.quantity
                        then
                            linked = gain
                            break
                        end
                    end
                    if linked and record.totalGained >= action.quantity then
                        linked.refunded = (linked.refunded or 0) + action.quantity
                        record.totalGained = record.totalGained - action.quantity
                        records[action.key] = record
                        vendorResult(state, action, "confirmed")
                    else
                        vendorResult(state, action, "unresolved")
                    end
                elseif action.kind == "sale" and delta == -action.quantity then
                    vendorResult(state, action, "confirmed")
                elseif action.kind == "buyback" and delta == action.quantity then
                    for _, sale in ipairs(state.actions) do
                        if sale.id == action.linkedSaleID and sale.status == "confirmed" and not sale.restored then
                            sale.restored = true
                            vendorResult(state, action, "confirmed")
                            break
                        end
                    end
                end
            end
        end
        for index = #state.actions, 1, -1 do
            local action = state.actions[index]
            if action.status == "pending" and at - action.at > 120 then
                vendorResult(state, action, "unresolved")
            elseif action.status == "confirmed" and at - action.at > 7200 then
                table.remove(state.actions, index)
            end
        end
    end

    function store.vendorReceipt(_self, receipt, at, actor)
        if
            not readable
            or type(receipt) ~= "table"
            or type(receipt.key) ~= "string"
            or not isInteger(receipt.quantity)
            or receipt.quantity < 1
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        local state = vendorState()
        if not state then
            return false
        end
        local match
        for _, action in ipairs(state.actions) do
            if
                action.kind == "purchase"
                and action.status == "pending"
                and action.key == receipt.key
                and action.character == actor.character
                and action.realm == actor.realm
                and at >= action.at
                and at - action.at <= 120
            then
                if match then
                    return false
                end
                match = action
            end
        end
        if not match then
            return false
        end
        match.receiptQuantity = math.min(match.quantity, match.receiptQuantity + receipt.quantity)
        local records = {}
        for key, record in pairs(raw.records) do
            records[key] = record
        end
        local grouped = { [receipt.key] = { quantity = bagQuantity(valid[receipt.key], actor.character, actor.realm) } }
        settleVendor(state, "bags", at, actor.character, actor.realm, grouped, records)
        saveFields({ vendor = state, records = records })
        if records[receipt.key] then
            valid[receipt.key] = copyRecord(records[receipt.key])
        end
        return true
    end

    function store.vendorActivity(_self)
        local state = vendorState()
        return state and copyArray(state.journal) or {}
    end

    function store.vendorUnresolved(_self)
        local result = {}
        local state = vendorState()
        for _, action in ipairs(state and state.actions or {}) do
            if action.status ~= "confirmed" then
                result[#result + 1] = {
                    id = action.id,
                    kind = action.kind,
                    key = action.key,
                    quantity = action.quantity,
                    at = action.at,
                    status = action.status,
                    character = action.character,
                    realm = action.realm,
                }
            end
        end
        return result
    end

    function store.pruneJournal(_self, limit)
        if not readable or not isInteger(limit) or limit < 0 then
            return false
        end
        local state = vendorState()
        if not state then
            return false
        end
        while #state.journal > limit do
            table.remove(state.journal, 1)
        end
        saveFields({ vendor = state })
        return true
    end

    local function rewardSessions(at)
        local result = {}
        local rewards = raw.rewards
        local sessions = type(rewards) == "table" and rewards.sessions or nil
        for _, session in ipairs(type(sessions) == "table" and sessions or {}) do
            if validRewardSession(session) and at >= session.at and at - session.at <= 120 then
                result[#result + 1] = session
            end
        end
        return result
    end

    ---@param receipt AzerothLedgerRewardReceipt
    ---@param at integer
    ---@param actor AzerothLedgerGainActor
    function store.rewardReceipt(_self, receipt, at, actor)
        if
            not readable
            or type(receipt) ~= "table"
            or type(receipt.key) ~= "string"
            or (receipt.method ~= "Quest" and receipt.method ~= "Crafted")
            or not isInteger(receipt.quantity)
            or receipt.quantity < 1
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
            or not isInteger(actor.level)
            or type(actor.place) ~= "string"
            or (receipt.preview ~= nil and type(receipt.preview) ~= "boolean")
            or (receipt.choiceGroup ~= nil and (type(receipt.choiceGroup) ~= "string" or receipt.choiceGroup == ""))
            or (receipt.choiceGroup ~= nil and (receipt.method ~= "Quest" or not receipt.preview))
        then
            return false
        end
        local area = store:area(actor.character, actor.realm, "bags")
        if not area or not area.complete or area.seenAt > at then
            return false
        end
        local context = receipt.context
        if not validRewardContext(context, receipt.method) then
            return false
        end
        local sessions = rewardSessions(at)
        local session
        for _, existing in ipairs(sessions) do
            if
                existing.key == receipt.key
                and existing.method == receipt.method
                and existing.character == actor.character
                and existing.realm == actor.realm
                and (not receipt.preview or existing.choiceGroup == receipt.choiceGroup)
                and (receipt.method ~= "Quest" or not existing.confirmed or existing.awarded < existing.quantity)
                and (
                    (not existing.context and not context)
                    or (existing.context and context and existing.context.id == context.id)
                )
            then
                session = existing
                break
            end
        end
        local rewards = type(raw.rewards) == "table" and raw.rewards or nil
        local nextID = rewards and rewards.nextID or 0
        if not session then
            nextID = (isInteger(nextID) and nextID or 0) + 1
            session = {
                id = nextID,
                key = receipt.key,
                method = receipt.method,
                context = context,
                character = actor.character,
                realm = actor.realm,
                level = actor.level,
                place = actor.place,
                at = at,
                baseline = bagQuantity(valid[receipt.key], actor.character, actor.realm),
                baselineGained = valid[receipt.key] and valid[receipt.key].totalGained or 0,
                quantity = 0,
                awarded = 0,
                discovery = not valid[receipt.key],
                confirmed = receipt.method == "Crafted",
                choiceGroup = receipt.choiceGroup,
                specific = receipt.method == "Quest" and not receipt.preview or nil,
            }
            sessions[#sessions + 1] = session
        end
        if receipt.method == "Quest" then
            session.quantity = math.max(session.quantity, receipt.quantity)
            if not receipt.preview then
                session.specific = true
            end
        else
            session.quantity = session.quantity + receipt.quantity
        end
        saveFields({ rewards = { nextID = nextID, sessions = sessions } })
        return true
    end

    function store.questTurnedIn(_self, questID, at, actor)
        if
            not readable
            or not isInteger(questID)
            or questID < 1
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        local changed = false
        for _, session in ipairs(rewardSessions(at)) do
            if
                session.method == "Quest"
                and session.context
                and session.context.id == questID
                and session.character == actor.character
                and session.realm == actor.realm
                and not session.confirmed
            then
                session.confirmed = true
                changed = true
            end
        end
        if changed then
            saveFields({})
        end
        return changed
    end

    local function awardReward(session, key, currentQuantity, records)
        local record = records[key]
        if not record or not session.confirmed then
            return
        end
        local otherGains = math.max(0, record.totalGained - session.baselineGained - session.awarded)
        local target = math.min(session.quantity, math.max(0, currentQuantity - session.baseline - otherGains))
        local quantity = target - session.awarded
        if quantity <= 0 then
            return
        end
        record = copyRecord(record)
        local gainID = "reward:" .. session.id .. ":" .. key
        local gain
        for _, existing in ipairs(record.gains) do
            if existing.id == gainID then
                gain = existing
                break
            end
        end
        if gain then
            gain.quantity = gain.quantity + quantity
        else
            gain = {
                id = gainID,
                at = session.at,
                quantity = quantity,
                character = session.character,
                realm = session.realm,
                level = session.level,
                place = session.place,
                method = session.method,
                context = session.context,
            }
            record.gains[#record.gains + 1] = gain
        end
        record.totalGained = record.totalGained + quantity
        record.firstGained = record.firstGained and math.min(record.firstGained, gain.at) or gain.at
        record.lastGained = record.lastGained and math.max(record.lastGained, gain.at) or gain.at
        if session.discovery then
            record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
            for _, character in ipairs(record.characters) do
                if character.name == session.character and character.realm == session.realm then
                    character.firstSeenUnits = math.max(0, character.firstSeenUnits - quantity)
                    break
                end
            end
        end
        session.awarded = target
        records[key] = record
    end

    local function choiceIsProven(session, sessions, grouped)
        if not session.choiceGroup then
            return true
        end
        local specific
        local increased
        local specificCount = 0
        local increasedCount = 0
        for _, candidate in ipairs(sessions) do
            if candidate.choiceGroup == session.choiceGroup then
                if candidate.awarded > 0 and candidate ~= session then
                    return false
                end
                if candidate.specific then
                    specific = candidate
                    specificCount = specificCount + 1
                end
                local group = grouped[candidate.key]
                if group and group.quantity > candidate.baseline then
                    increased = candidate
                    increasedCount = increasedCount + 1
                end
            end
        end
        if specificCount > 0 then
            return specificCount == 1 and specific == session
        end
        if increasedCount > 1 then
            session.ambiguous = true
        end
        return increasedCount == 1 and increased == session and not session.ambiguous
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
        local activeRewards = snapshot.area == "bags" and snapshot.complete and rewardSessions(snapshot.seenAt) or {}
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
            else
                previous.seenAt = snapshot.seenAt
            end
            nextRecords[key] = record
            if session then
                award(session, key, nextRecords)
            end
            if snapshot.area == "bags" and snapshot.complete and type(oldScope) == "table" and oldScope.complete then
                for _, reward in ipairs(activeRewards) do
                    if
                        reward.key == key
                        and reward.character == snapshot.character
                        and reward.realm == snapshot.realm
                        and choiceIsProven(reward, activeRewards, grouped)
                    then
                        awardReward(reward, key, group.quantity, nextRecords)
                    end
                end
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
        local vendor = vendorState()
        if
            vendor
            and (snapshot.area == "bags" or snapshot.area == "equipped")
            and snapshot.complete
            and type(oldScope) == "table"
            and oldScope.complete
        then
            settleVendor(
                vendor,
                snapshot.area,
                snapshot.seenAt,
                snapshot.character,
                snapshot.realm,
                grouped,
                nextRecords
            )
        end
        local nextAreas = {}
        for key, state in pairs(raw.areas) do
            nextAreas[key] = state
        end
        nextAreas[scopeKey] = {
            seenAt = snapshot.seenAt,
            complete = snapshot.complete,
            character = snapshot.character,
            realm = snapshot.realm,
        }
        saveFields({ records = nextRecords, areas = nextAreas, vendor = vendor })
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
