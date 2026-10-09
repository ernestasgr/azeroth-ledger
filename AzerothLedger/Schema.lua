local _, addon = ...

local displayDefaults = { tooltips = true, toasts = true }
local function validDisplay(value)
    return type(value) == "table" and type(value.tooltips) == "boolean" and type(value.toasts) == "boolean"
end

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
---@field checkID? integer
---@field character? string
---@field realm? string

---@class AzerothLedgerScanItem
---@field itemID integer
---@field link? string
---@field quantity integer
---@field location? string

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

---@class AzerothLedgerVendorSource
---@field kind 'vendor'
---@field name string

---@class AzerothLedgerPlayerSource
---@field kind 'player'
---@field name string
---@field realm string

---@class AzerothLedgerGain
---@field id string
---@field at integer
---@field quantity integer
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field placeKind? 'zone'|'dungeon'
---@field method 'Looted'|'Quest'|'Crafted'|'Vendor'|'Obtained'
---@field mailKind? 'auction-purchase'
---@field refunded? integer
---@field source? AzerothLedgerLootSource|AzerothLedgerVendorSource|AzerothLedgerPlayerSource
---@field context? {kind: 'quest'|'recipe', id: integer, name?: string}
---@field corrections? string[]

---@class AzerothLedgerLootSlot
---@field key string
---@field source? AzerothLedgerLootSource
---@field quantity? integer
---@field slot? integer
---@field sourceIndex? integer

---@class AzerothLedgerLootContext
---@field character string
---@field realm string
---@field at integer
---@field level integer
---@field place string
---@field placeKind? 'zone'|'dungeon'
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
---@field shares? {source?: AzerothLedgerLootSource, quantity?: integer, slot: integer, sourceIndex: integer}[]

---@class AzerothLedgerLootSession
---@field id integer
---@field openedAt integer
---@field closedAt? integer
---@field endedAt? integer
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field placeKind? 'zone'|'dungeon'
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
---@field placeKind? 'zone'|'dungeon'
---@field vendorName? string

---@alias ALGainActor AzerothLedgerGainActor

---@alias ALStore AzerothLedgerStore
---@alias ALExIntent AzerothLedgerExchangeIntent
---@alias ALExIds integer|table<integer, boolean>

---@class AzerothLedgerRewardSession
---@field id integer
---@field key string
---@field method 'Quest'|'Crafted'
---@field context? AzerothLedgerRewardContext
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field placeKind? 'zone'|'dungeon'
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
---@field questPreparationID? integer

---@class AzerothLedgerQuestPreparation
---@field id integer
---@field questID integer
---@field character string
---@field realm string
---@field at integer
---@field confirmed boolean
---@field baseline table<string, {quantity: integer, gained: integer, discovery?: boolean}>

---@class AzerothLedgerRewardState
---@field nextID integer
---@field sessions AzerothLedgerRewardSession[]
---@field preparations? AzerothLedgerQuestPreparation[]

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
---@field placeKind? 'zone'|'dungeon'
---@field baseline integer
---@field baselineGained integer
---@field receiptQuantity integer
---@field status 'pending'|'confirmed'|'unresolved'
---@field area 'bags'|'equipped'
---@field linkedGainID? string
---@field linkedSaleID? integer
---@field restored? boolean
---@field vendorName? string

---@class AzerothLedgerVendorActivity
---@field sequence? integer
---@field id integer
---@field kind 'sale'|'refund'|'buyback'
---@field key string
---@field quantity integer
---@field at integer
---@field character string
---@field realm string
---@field vendorName? string

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

---@class AzerothLedgerExchangeIntent
---@field channel 'mail'|'trade'
---@field direction 'in'|'out'
---@field key string
---@field itemID integer
---@field link string
---@field quantity integer
---@field peerName? string
---@field peerRealm? string
---@field mailKind? 'return'|'auction-purchase'|'unresolved'

---@class AzerothLedgerExchangeAction: AzerothLedgerExchangeIntent
---@field id integer
---@field at integer
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field placeKind? 'zone'|'dungeon'
---@field baseline integer
---@field baselineGained integer
---@field discovery boolean
---@field confirmed boolean
---@field status 'pending'|'unresolved'|'settled'|'canceled'
---@field transferred? integer
---@field isTransfer? boolean
---@field isReturn? boolean
---@field baselineCheckID? integer

---@class AzerothLedgerExchangeActivity
---@field sequence? integer
---@field id integer
---@field key string
---@field channel 'mail'|'trade'
---@field quantity integer
---@field at integer
---@field sender string
---@field senderRealm string
---@field recipient string
---@field recipientRealm string

---@class AzerothLedgerExchangeState
---@field nextID integer
---@field actions AzerothLedgerExchangeAction[]
---@field journal AzerothLedgerExchangeActivity[]

---@class AzerothLedgerRecord
---@field key string
---@field itemID integer
---@field firstSeen integer
---@field lastSeen integer
---@field firstSeenUnits integer
---@field totalGained integer
---@field evidencedDiscovery? boolean
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
---@field exchange? AzerothLedgerExchangeState
---@field evidence? AzerothLedgerEvidenceState
---@field retention? table<string, integer>
---@field display? table<string, boolean>
---@field journal? ALJournalState

---@class ALJournalReference
---@field id string
---@field key string
---@field at integer
---@field sequence integer

---@class ALJournalState
---@field nextSequence integer
---@field gains ALJournalReference[]

---@class AzerothLedgerEvidence
---@field id integer
---@field kind string
---@field reason string
---@field at integer
---@field character string
---@field realm string
---@field detail table

---@class AzerothLedgerEvidenceState
---@field nextID integer
---@field unresolved AzerothLedgerEvidence[]
---@field discarded integer
---@field firstDiscarded? integer
---@field lastDiscarded? integer

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
---@field count fun(self: AzerothLedgerStore): integer
---@field revision fun(self: AzerothLedgerStore): integer
---@field cursor fun(self: AzerothLedgerStore): fun(): AzerothLedgerRecord?
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
---@field questPrepared fun(self: AzerothLedgerStore, questID: integer, at: integer, actor: ALActor): boolean
---@field questTurnedIn fun(self: AzerothLedgerStore, questID: integer, at: integer, actor: ALActor): boolean
---@field vendorAction fun(self: AzerothLedgerStore, action: ALVendorIntent, at: integer, actor: ALGainActor): boolean
---@field vendorReceipt fun(self: AzerothLedgerStore, receipt: ALClaim, at: integer, actor: ALActor): boolean
---@field vendorActivity fun(self: AzerothLedgerStore): AzerothLedgerVendorActivity[]
---@field vendorUnresolved fun(self: AzerothLedgerStore): AzerothLedgerVendorEvidence[]
---@field exchangeIntent fun(self: ALStore, intent: ALExIntent, at: integer, actor: ALGainActor): integer|boolean
---@field exchangeConfirm fun(self: ALStore, c: string, d: string, at: integer, a: ALActor, ids?: ALExIds): boolean
---@field exchangeCancel fun(self: AzerothLedgerStore, channel: 'mail'|'trade', actor: ALActor): boolean
---@field exchangeMarkUnresolved fun(self: AzerothLedgerStore, id: integer, actor: ALActor): boolean
---@field mailProgress fun(self: AzerothLedgerStore, ids: table<integer, boolean>): 'waiting'|'measured'|'ended'
---@field exchangeActivity fun(self: AzerothLedgerStore): AzerothLedgerExchangeActivity[]
---@field exchangeUnresolved fun(self: AzerothLedgerStore): AzerothLedgerExchangeAction[]
---@field retention fun(self: ALStore): table<string, integer>
---@field setRetention fun(self: ALStore, category: string, limit: integer): boolean
---@field display fun(self: ALStore): table<string, boolean>
---@field setDisplay fun(self: ALStore, control: string, enabled: boolean): boolean
---@field takeDiscoveries fun(self: ALStore): AzerothLedgerRecord[]
---@field journal fun(self: ALStore, pause?: fun()): table[]
---@field unresolved fun(self: AzerothLedgerStore): AzerothLedgerEvidence[]
---@field evidenceSummary fun(self: AzerothLedgerStore): AzerothLedgerEvidenceState
---@field expireEvidence fun(self: AzerothLedgerStore, at: integer): boolean
---@field correctGain fun(self: AzerothLedgerStore, proof: AzerothLedgerGainCorrection): boolean
---@field breakdown fun(self: ALStore, key: string, scope?: ALCountScope): AzerothLedgerBreakdown?
---@field lootSourceProof fun(self: ALStore, slots: ALLootSlots, at: integer, actor: ALActor): boolean

---@alias ALLootSlots AzerothLedgerLootSlot[]

---@class ALCountScope
---@field character? string
---@field realm? string

---@class AzerothLedgerBreakdown
---@field recorded? integer
---@field initial? integer
---@field gained integer
---@field methods table<string, integer>
---@field sources table<string, integer>

---@class AzerothLedgerGainCorrection
---@field id string
---@field key string
---@field gainID string
---@field quantity integer
---@field fromMethod string
---@field fromSource? AzerothLedgerLootSource|AzerothLedgerVendorSource|AzerothLedgerPlayerSource
---@field method string
---@field source? AzerothLedgerLootSource|AzerothLedgerVendorSource|AzerothLedgerPlayerSource
---@field context? AzerothLedgerRewardContext
---@field link? string

local CURRENT_SCHEMA = 2
local areas = { bags = true, bank = true, equipped = true }
local gainMethods = { Looted = true, Quest = true, Crafted = true, Vendor = true, Obtained = true }
local retentionDefinitions = {
    { key = "gains", name = "Recent gains", default = 1000, maximum = 5000 },
    { key = "transfers", name = "Alt transfers", default = 250, maximum = 2000 },
    { key = "vendor", name = "Vendor sales, refunds and buybacks", default = 250, maximum = 2000 },
}
local retentionDefaults, retentionMaximums = {}, {}
for _, definition in ipairs(retentionDefinitions) do
    retentionDefaults[definition.key] = definition.default
    retentionMaximums[definition.key] = definition.maximum
end

local function isInteger(value)
    return type(value) == "number" and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

local function validCheckID(value)
    return value == nil or (isInteger(value) and value >= 1)
end

local function validRetention(value)
    if type(value) ~= "table" then
        return false
    end
    for category, maximum in pairs(retentionMaximums) do
        if not isInteger(value[category]) or value[category] < 0 or value[category] > maximum then
            return false
        end
    end
    return true
end

local function gainRoot(id)
    return id:match("^(.-):share:") or id:match("^(.-):proof:") or id
end

local function chronological(a, b)
    return a.at < b.at or (a.at == b.at and a.sequence < b.sequence)
end

local function trimHistory(rows, limit)
    table.sort(rows, chronological)
    local remove = math.max(0, #rows - limit)
    for index = 1, #rows - remove do
        rows[index] = rows[index + remove]
    end
    for index = #rows, #rows - remove + 1, -1 do
        rows[index] = nil
    end
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

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, field in pairs(value) do
        result[key] = copyValue(field)
    end
    return result
end

local function validEvidence(state)
    if
        type(state) ~= "table"
        or not isInteger(state.nextID)
        or state.nextID < 1
        or type(state.unresolved) ~= "table"
        or #state.unresolved > 2000
        or not isInteger(state.discarded)
        or state.discarded < 0
    then
        return false
    end
    if
        state.discarded > 0
        and (
            not isInteger(state.firstDiscarded)
            or not isInteger(state.lastDiscarded)
            or state.firstDiscarded < 0
            or state.lastDiscarded < state.firstDiscarded
        )
    then
        return false
    end
    local ids = {}
    for _, entry in ipairs(state.unresolved) do
        if
            type(entry) ~= "table"
            or not isInteger(entry.id)
            or entry.id < 1
            or entry.id >= state.nextID
            or ids[entry.id]
            or not isName(entry.kind)
            or not isName(entry.reason)
            or not isInteger(entry.at)
            or entry.at < 0
            or not isName(entry.character)
            or not isName(entry.realm)
            or type(entry.detail) ~= "table"
        then
            return false
        end
        ids[entry.id] = true
    end
    return true
end

local function validLootSource(source)
    return source == nil
        or (
            type(source) == "table"
            and (source.kind == "mob" or source.kind == "container")
            and isName(source.guid)
            and (source.name == nil or isName(source.name))
        )
end

local function validLootState(state)
    if type(state) ~= "table" or not isInteger(state.nextID) or state.nextID < 0 or type(state.sessions) ~= "table" then
        return false
    end
    for _, session in ipairs(state.sessions) do
        if
            type(session) ~= "table"
            or not isInteger(session.id)
            or not isInteger(session.openedAt)
            or session.openedAt < 0
            or not isName(session.character)
            or not isName(session.realm)
            or not isInteger(session.level)
            or type(session.place) ~= "string"
            or type(session.slots) ~= "table"
            or type(session.receipts) ~= "table"
            or type(session.discoveries) ~= "table"
            or (session.closedAt ~= nil and not isInteger(session.closedAt))
            or (session.endedAt ~= nil and not isInteger(session.endedAt))
        then
            return false
        end
        for _, name in ipairs({ "credits", "awarded", "baselineQuantities", "baselineGains" }) do
            if type(session[name]) ~= "table" then
                return false
            end
            for key, quantity in pairs(session[name]) do
                if type(key) ~= "string" or not isInteger(quantity) or quantity < 0 then
                    return false
                end
            end
        end
        for key, slot in pairs(session.slots) do
            if
                type(key) ~= "string"
                or type(slot) ~= "table"
                or not validLootSource(slot.source)
                or (slot.limit ~= nil and (not isInteger(slot.limit) or slot.limit < 1))
            then
                return false
            end
            if slot.shares ~= nil then
                if type(slot.shares) ~= "table" then
                    return false
                end
                for _, share in ipairs(slot.shares) do
                    if
                        type(share) ~= "table"
                        or not validLootSource(share.source)
                        or (share.quantity ~= nil and (not isInteger(share.quantity) or share.quantity < 1))
                    then
                        return false
                    end
                end
            end
        end
        for key, receipt in pairs(session.receipts) do
            if
                type(key) ~= "string"
                or type(receipt) ~= "table"
                or not isInteger(receipt.at)
                or not isInteger(receipt.quantity)
                or receipt.quantity < 1
            then
                return false
            end
        end
    end
    return true
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
            placeKind = gain.placeKind,
            method = gain.method,
            mailKind = gain.mailKind,
            refunded = gain.refunded,
            corrections = gain.corrections and copyArray(gain.corrections) or nil,
            source = gain.source and {
                kind = gain.source.kind,
                guid = gain.source.guid,
                name = gain.source.name,
                realm = gain.source.realm,
            } or nil,
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
        evidencedDiscovery = record.evidencedDiscovery,
        gains = gains,
        firstGained = record.firstGained,
        lastGained = record.lastGained,
        links = copyArray(record.links),
        characters = copyArray(record.characters),
        observations = copyArray(record.observations),
    }
end

local function validPlaceKind(kind)
    return kind == nil or kind == "zone" or kind == "dungeon"
end

local function validRecord(key, record)
    if
        type(key) ~= "string"
        or type(record) ~= "table"
        or record.key ~= key
        or (record.evidencedDiscovery ~= nil and type(record.evidencedDiscovery) ~= "boolean")
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
            or not validPlaceKind(gain.placeKind)
            or not gainMethods[gain.method]
            or (gain.mailKind ~= nil and (gain.mailKind ~= "auction-purchase" or gain.method ~= "Obtained"))
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
        and (
            session.questPreparationID == nil
            or (isInteger(session.questPreparationID) and session.questPreparationID > 0)
        )
end

local function validRewardState(rewards)
    if
        type(rewards) ~= "table"
        or not isInteger(rewards.nextID)
        or type(rewards.sessions) ~= "table"
        or (rewards.preparations ~= nil and type(rewards.preparations) ~= "table")
    then
        return false
    end
    for _, session in ipairs(rewards.sessions) do
        if not validRewardSession(session) then
            return false
        end
    end
    for _, preparation in ipairs(rewards.preparations or {}) do
        if
            type(preparation) ~= "table"
            or not isInteger(preparation.id)
            or preparation.id < 1
            or not isInteger(preparation.questID)
            or preparation.questID < 1
            or not isName(preparation.character)
            or not isName(preparation.realm)
            or not isInteger(preparation.at)
            or type(preparation.confirmed) ~= "boolean"
            or type(preparation.baseline) ~= "table"
        then
            return false
        end
        for key, item in pairs(preparation.baseline) do
            if
                type(key) ~= "string"
                or type(item) ~= "table"
                or not isInteger(item.quantity)
                or item.quantity < 0
                or not isInteger(item.gained)
                or item.gained < 0
                or (item.discovery ~= nil and type(item.discovery) ~= "boolean")
            then
                return false
            end
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
            or (action.vendorName ~= nil and not isName(action.vendorName))
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
            or (entry.vendorName ~= nil and not isName(entry.vendorName))
        then
            return false
        end
    end
    return true
end

local exchangeStatuses = { pending = true, unresolved = true, settled = true, canceled = true }
local mailKinds = { ["return"] = true, ["auction-purchase"] = true, unresolved = true }

local function validMailKind(intent)
    return intent.mailKind == nil
        or (intent.channel == "mail" and intent.direction == "in" and mailKinds[intent.mailKind] == true)
end

local function validTransferred(action)
    local transferred = action.transferred
    return transferred == nil or (isInteger(transferred) and transferred >= 0 and transferred <= action.quantity)
end

local function validExchangeState(exchange)
    if
        type(exchange) ~= "table"
        or not isInteger(exchange.nextID)
        or type(exchange.actions) ~= "table"
        or type(exchange.journal) ~= "table"
    then
        return false
    end
    local ids = {}
    for _, action in ipairs(exchange.actions) do
        if
            type(action) ~= "table"
            or not isInteger(action.id)
            or action.id < 1
            or action.id >= exchange.nextID
            or ids[action.id]
            or (action.channel ~= "mail" and action.channel ~= "trade")
            or (action.direction ~= "in" and action.direction ~= "out")
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
            or type(action.discovery) ~= "boolean"
            or type(action.confirmed) ~= "boolean"
            or not exchangeStatuses[action.status]
            or (action.peerName ~= nil and not isName(action.peerName))
            or (action.peerRealm ~= nil and not isName(action.peerRealm))
            or not validTransferred(action)
            or not validCheckID(action.baselineCheckID)
            or (action.isTransfer ~= nil and type(action.isTransfer) ~= "boolean")
            or (action.isReturn ~= nil and type(action.isReturn) ~= "boolean")
            or not validMailKind(action)
        then
            return false
        end
        ids[action.id] = true
    end
    for _, activity in ipairs(exchange.journal) do
        if
            type(activity) ~= "table"
            or not isInteger(activity.id)
            or type(activity.key) ~= "string"
            or (activity.channel ~= "mail" and activity.channel ~= "trade")
            or not isInteger(activity.quantity)
            or activity.quantity < 1
            or not isInteger(activity.at)
            or not isName(activity.sender)
            or not isName(activity.senderRealm)
            or not isName(activity.recipient)
            or not isName(activity.recipientRealm)
        then
            return false
        end
    end
    return true
end

local Schema = {}

-- The entry ID identifies the container type; the final field identifies a
-- particular spawn. Keep the complete GUID in the gain as its original proof.
local function containerID(source)
    if not source or source.kind ~= "container" then
        return nil
    end
    local id = source.guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    local entry = id and tonumber(id)
    return entry and entry > 0 and entry <= 4294967295 and tostring(entry) or nil
end

---@param source? AzerothLedgerLootSource|AzerothLedgerVendorSource|AzerothLedgerPlayerSource
---@return string
function Schema.sourceText(source)
    if not source then
        return "Unknown"
    elseif source.kind == "player" then
        return source.name .. "-" .. source.realm
    end
    local id = containerID(source)
    return source.name or (id and ("Container #" .. id)) or source.guid or ("Unnamed " .. source.kind)
end

function Schema.retentionOptions()
    return copyValue(retentionDefinitions)
end

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
                or not validCheckID(state.checkID)
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
    if supported and raw.loot ~= nil and not validLootState(raw.loot) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.vendor ~= nil and not validVendorState(raw.vendor) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.exchange ~= nil and not validExchangeState(raw.exchange) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.evidence ~= nil and not validEvidence(raw.evidence) then
        damagedCount = damagedCount + 1
    end
    if supported and raw.retention ~= nil and not validRetention(raw.retention) then
        damagedCount = damagedCount + 1
    end

    local function retention()
        return type(raw) == "table" and validRetention(raw.retention) and copyValue(raw.retention)
            or copyValue(retentionDefaults)
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
    if supported and raw.journal ~= nil and not validJournal(raw.journal) then
        damagedCount = damagedCount + 1
    end
    if readable then
        for _, category in ipairs({ "exchange", "vendor" }) do
            local state = raw[category]
            local validState = category == "exchange" and validExchangeState or validVendorState
            for _, entry in ipairs(state and validState(state) and state.journal or {}) do
                if not valid[entry.key] then
                    damagedCount = damagedCount + 1
                end
            end
        end
        for _, entry in ipairs(validJournal(raw.journal) and raw.journal.gains or {}) do
            if not valid[entry.key] then
                damagedCount = damagedCount + 1
            end
        end
    end

    if supported and raw.display ~= nil and not validDisplay(raw.display) then
        damagedCount = damagedCount + 1
    end
    -- Runtime indexes are rebuilt from validated facts, never persisted or pruned.
    local scopeRecords, actorIndex, recordKeys, keyIndex = {}, {}, {}, {}
    local revision = 0
    local function indexRecord(key, record)
        if not keyIndex[key] then
            recordKeys[#recordKeys + 1], keyIndex[key] = key, true
        end
        local previous = valid[key]
        for _, observation in ipairs(previous and previous.observations or {}) do
            local scope = scopeRecords[areaKey(observation.character, observation.realm, observation.area)]
            if scope then
                scope[key] = nil
            end
        end
        for _, seen in ipairs(record.characters) do
            actorIndex[areaKey(seen.name, seen.realm, "")] = { character = seen.name, realm = seen.realm }
        end
        for _, observation in ipairs(record.observations) do
            local scopeKey = areaKey(observation.character, observation.realm, observation.area)
            scopeRecords[scopeKey] = scopeRecords[scopeKey] or {}
            scopeRecords[scopeKey][key] = observation.quantity > 0 and true or nil
        end
    end
    for key, record in pairs(valid) do
        indexRecord(key, record)
    end

    local function heldKeys(character, realm, area)
        return scopeRecords[areaKey(character, realm, area)] or {}
    end
    local function priorQuantity(record, character, realm, area)
        local quantity = 0
        for _, observation in ipairs(record and record.observations or {}) do
            if observation.character == character and observation.realm == realm and observation.area == area then
                quantity = observation.quantity
            end
        end
        return quantity
    end

    local journalHealthy = readable and validJournal(raw.journal)
    local vendorHealthy = readable and (raw.vendor == nil or validVendorState(raw.vendor))
    local exchangeHealthy = readable and (raw.exchange == nil or validExchangeState(raw.exchange))
    local discoveries = {}
    local function saveFields(fields)
        local nextValue = {
            schema = CURRENT_SCHEMA,
            marker = fields.marker or raw.marker,
            environment = fields.environment or raw.environment,
            records = raw.records,
            areas = fields.areas or raw.areas,
            loot = fields.loot or raw.loot,
            rewards = fields.rewards or raw.rewards,
            vendor = fields.vendor or raw.vendor,
            exchange = fields.exchange or raw.exchange,
            evidence = fields.evidence or raw.evidence,
            retention = fields.retention or raw.retention,
            display = fields.display or raw.display,
            journal = journalHealthy and raw.journal or { nextSequence = 1, gains = {} },
        }
        local history = { nextSequence = nextValue.journal.nextSequence, gains = nextValue.journal.gains }
        nextValue.journal = history
        local function sequence(entry)
            entry.sequence = history.nextSequence
            history.nextSequence = history.nextSequence + 1
        end
        -- Permanent contributions are assembled first. Only their new event roots
        -- enter history; corrections and later shares cannot resurrect pruned rows.
        local pending = {}
        for key, record in pairs(fields.records or {}) do
            if record ~= raw.records[key] then
                local known = {}
                for _, gain in ipairs(raw.records[key] and raw.records[key].gains or {}) do
                    known[gainRoot(gain.id)] = true
                end
                for _, gain in ipairs(record.gains or {}) do
                    local id = gainRoot(gain.id)
                    if not known[id] then
                        pending[#pending + 1] = { id = id, key = key, at = gain.at }
                        known[id] = true
                    end
                end
            end
        end
        -- A single scan can commit several items. Sort these explicitly rather
        -- than letting Lua's hash iteration choose their sequence.
        table.sort(pending, function(a, b)
            if a.at ~= b.at then
                return a.at < b.at
            end
            if a.id ~= b.id then
                return a.id < b.id
            end
            return a.key < b.key
        end)
        if #pending > 0 or fields.retention then
            history.gains = copyArray(history.gains)
        end
        for _, entry in ipairs(pending) do
            sequence(entry)
            history.gains[#history.gains + 1] = entry
        end
        local limits = validRetention(nextValue.retention) and nextValue.retention or retentionDefaults
        if #pending > 0 or fields.retention then
            trimHistory(history.gains, limits.gains)
        end
        for _, category in ipairs({ "exchange", "vendor" }) do
            local state = nextValue[category]
            local validState = category == "exchange" and validExchangeState or validVendorState
            if state and (fields[category] or fields.retention) and validState(state) then
                state = copyValue(state)
                nextValue[category] = state
                for _, entry in ipairs(state.journal) do
                    if not isInteger(entry.sequence) or entry.sequence < 1 then
                        sequence(entry)
                    end
                end
                trimHistory(state.journal, limits[category == "exchange" and "transfers" or "vendor"])
            end
        end
        local discovered = {}
        for key, record in pairs(fields.records or {}) do
            if record.evidencedDiscovery and not (raw.records[key] and raw.records[key].evidencedDiscovery) then
                discovered[#discovered + 1] = copyRecord(record)
            end
        end
        table.sort(discovered, function(a, b)
            return a.key < b.key
        end)
        -- Capture previously unheld items lazily before their first change during
        -- an active action. Late item identification keeps the pre-action totals.
        local previousRecords = {}
        for key, record in pairs(fields.records or {}) do
            local before = valid[key]
            for _, session in ipairs(nextValue.loot and nextValue.loot.sessions or {}) do
                if session.baselineGains[key] == nil then
                    session.baselineGains[key] = before and before.totalGained or 0
                    session.baselineQuantities[key] = priorQuantity(before, session.character, session.realm, "bags")
                end
            end
            for _, preparation in ipairs(nextValue.rewards and nextValue.rewards.preparations or {}) do
                if not preparation.baseline[key] then
                    preparation.baseline[key] = {
                        quantity = priorQuantity(before, preparation.character, preparation.realm, "bags")
                            + priorQuantity(before, preparation.character, preparation.realm, "equipped"),
                        gained = before and before.totalGained or 0,
                        discovery = before == nil,
                    }
                end
            end
            previousRecords[key] = raw.records[key] or false
            nextValue.records[key] = record
        end
        local savedOK, failure = pcall(save, nextValue)
        if not savedOK then
            for key, record in pairs(previousRecords) do
                raw.records[key] = record or nil
            end
            error(failure)
        end
        for key, record in pairs(fields.records or {}) do
            indexRecord(key, record)
        end
        revision = revision + 1
        journalHealthy = true
        raw = nextValue
        if not validDisplay(nextValue.display) or nextValue.display.toasts then
            for _, record in ipairs(discovered) do
                discoveries[#discoveries + 1] = record
            end
        end
    end

    local store = {}
    function store.display(_self)
        return copyValue(readable and validDisplay(raw.display) and raw.display or displayDefaults)
    end

    function store.setDisplay(_self, control, enabled)
        if not readable or displayDefaults[control] == nil or type(enabled) ~= "boolean" then
            return false
        end
        local values = store:display()
        values[control] = enabled
        saveFields({ display = values })
        return true
    end
    function store.takeDiscoveries(_self)
        local result = discoveries
        discoveries = {}
        return result
    end
    function store.retention(_self)
        return retention()
    end

    function store.setRetention(_self, category, limit)
        local maximum = retentionMaximums[category]
        if not readable or not maximum or not isInteger(limit) or limit < 0 or limit > maximum then
            return false
        end
        if
            category == "vendor" and raw.vendor ~= nil and not validVendorState(raw.vendor)
            or category == "transfers" and raw.exchange ~= nil and not validExchangeState(raw.exchange)
            or category == "gains" and raw.journal ~= nil and not validJournal(raw.journal)
        then
            return false
        end
        local limits = retention()
        limits[category] = limit
        saveFields({ retention = limits })
        return true
    end

    function store.journal(_self, pause)
        local result = {}
        if not readable then
            return result
        end
        for _, entry in ipairs(journalHealthy and raw.journal.gains or {}) do
            if pause then
                pause()
            end
            local record = valid[entry.key]
            local contributions = {}
            for _, gain in ipairs(record and record.gains or {}) do
                if gainRoot(gain.id) == entry.id then
                    contributions[#contributions + 1] = copyValue(gain)
                end
            end
            if #contributions > 0 then
                local row = copyValue(entry)
                row.category, row.contributions = "gain", contributions
                result[#result + 1] = row
            end
        end
        for _, category in ipairs({ "exchange", "vendor" }) do
            local state = raw[category]
            local healthy = category == "exchange" and exchangeHealthy or vendorHealthy
            for _, entry in ipairs(state and healthy and state.journal or {}) do
                if pause then
                    pause()
                end
                if valid[entry.key] and isInteger(entry.sequence) and entry.sequence > 0 then
                    local row = copyValue(entry)
                    row.category = category == "exchange" and "transfer" or "vendor"
                    result[#result + 1] = row
                end
            end
        end
        local function newestFirst(a, b)
            return chronological(b, a)
        end
        if pause then
            addon.Work.sort(result, newestFirst, pause)
        else
            table.sort(result, newestFirst)
        end
        return result
    end
    local candidates = {}

    local function evidenceState()
        if raw.evidence == nil then
            return { nextID = 1, unresolved = {}, discarded = 0 }
        end
        return validEvidence(raw.evidence) and copyValue(raw.evidence) or nil
    end

    local function retain(state, kind, reason, at, actor, detail)
        state.unresolved[#state.unresolved + 1] = {
            id = state.nextID,
            kind = kind,
            reason = reason,
            at = at,
            character = actor.character,
            realm = actor.realm,
            detail = copyValue(detail),
        }
        state.nextID = state.nextID + 1
        if #state.unresolved > 2000 then
            local discarded = table.remove(state.unresolved, 1)
            state.discarded = state.discarded + 1
            state.firstDiscarded = math.min(state.firstDiscarded or discarded.at, discarded.at)
            state.lastDiscarded = math.max(state.lastDiscarded or discarded.at, discarded.at)
        end
    end

    -- End correlation independently of event traffic. Completed vendor and outgoing
    -- transfer references remain available for refunds, buybacks and alt receipts.
    local function endCorrelation(at, reason)
        if not readable then
            return false
        end
        local engines = {
            loot = raw.loot and validLootState(raw.loot) and raw.loot or nil,
            rewards = raw.rewards and validRewardState(raw.rewards) and raw.rewards or nil,
            vendor = raw.vendor and vendorHealthy and raw.vendor or nil,
            exchange = raw.exchange and exchangeHealthy and raw.exchange or nil,
        }
        for index = #candidates, 1, -1 do
            if at - candidates[index].at >= 60 then
                table.remove(candidates, index)
            end
        end
        if reason ~= "reload" then
            local stale = false
            for _, name in ipairs({ "loot", "rewards", "vendor", "exchange" }) do
                local state = engines[name]
                local list = (name == "loot" or name == "rewards") and "sessions" or "actions"
                for _, entry in ipairs(state and state[list] or {}) do
                    local active = name == "loot"
                        or name == "rewards"
                        or entry.status == "pending"
                        or entry.status == "unresolved"
                    if active and at - (entry.openedAt or entry.at) >= 60 then
                        stale = true
                        break
                    end
                end
                for _, entry in ipairs(name == "rewards" and state and state.preparations or {}) do
                    if at - entry.at >= 60 then
                        stale = true
                        break
                    end
                end
            end
            if not stale then
                return raw.evidence == nil or validEvidence(raw.evidence)
            end
        end
        local evidence = evidenceState()
        if not evidence then
            return false
        end
        local fields = { evidence = evidence }
        local changed = false
        for _, name in ipairs({ "loot", "rewards", "vendor", "exchange" }) do
            local original = engines[name]
            if type(original) == "table" then
                local state = copyValue(original)
                local list = (name == "loot" or name == "rewards") and "sessions" or "actions"
                local entries = state[list]
                if type(entries) == "table" then
                    for index = #entries, 1, -1 do
                        local entry = entries[index]
                        local openedAt = entry.openedAt or entry.at
                        local stale = reason == "reload" or (isInteger(openedAt) and at - openedAt >= 60)
                        local active = name == "loot"
                            or name == "rewards"
                            or entry.status == "pending"
                            or entry.status == "unresolved"
                        if
                            stale
                            and active
                            and isInteger(openedAt)
                            and isName(entry.character)
                            and isName(entry.realm)
                        then
                            if name == "loot" then
                                for key, slot in pairs(entry.slots or {}) do
                                    local received = entry.receipts and entry.receipts[key]
                                    local quantity = math.max(
                                        slot.limit or 0,
                                        received and received.quantity or 0,
                                        entry.credits and entry.credits[key] or 0
                                    )
                                    if quantity == 0 or quantity > (entry.awarded[key] or 0) then
                                        retain(evidence, name, reason, openedAt, entry, {
                                            key = key,
                                            slot = slot,
                                            receipt = received,
                                            measured = entry.credits[key],
                                            awarded = entry.awarded[key],
                                        })
                                    end
                                end
                            elseif name ~= "rewards" or entry.awarded < entry.quantity or not entry.confirmed then
                                retain(evidence, name, reason, openedAt, entry, entry)
                            end
                            table.remove(entries, index)
                            changed = true
                        end
                    end
                end
                if name == "rewards" then
                    for index = #(state.preparations or {}), 1, -1 do
                        local entry = state.preparations[index]
                        if reason == "reload" or at - entry.at >= 60 then
                            if not entry.confirmed then
                                retain(evidence, "quest", reason, entry.at, entry, entry)
                            end
                            table.remove(state.preparations, index)
                            changed = true
                        end
                    end
                end
                fields[name] = state
            end
        end
        if changed then
            saveFields(fields)
        end
        return true
    end

    function store.expireEvidence(_self, at)
        return isInteger(at) and at >= 0 and endCorrelation(at, "expired") or false
    end

    function store.unresolved(_self)
        local state = evidenceState()
        return state and state.unresolved or {}
    end

    function store.evidenceSummary(_self)
        return evidenceState() or { nextID = 1, unresolved = {}, discarded = 0 }
    end

    local function sameSource(left, right)
        if not left or not right then
            return left == right
        end
        return left.kind == right.kind
            and left.guid == right.guid
            and left.name == right.name
            and left.realm == right.realm
    end

    local function canEnrichLootSource(current, proof)
        return not current
            or (
                current.guid == proof.guid
                and current.kind == proof.kind
                and (current.name == nil or proof.name ~= nil)
            )
    end

    function store.correctGain(_self, proof)
        if
            not readable
            or type(proof) ~= "table"
            or not isName(proof.id)
            or type(proof.key) ~= "string"
            or type(proof.gainID) ~= "string"
            or not isInteger(proof.quantity)
            or proof.quantity < 1
            or not gainMethods[proof.method]
            or (proof.source ~= nil and type(proof.source) ~= "table")
            or (proof.fromSource ~= nil and type(proof.fromSource) ~= "table")
        then
            return false
        end
        local existing = valid[proof.key]
        if
            not existing
            or not validRecord(proof.key, existing)
            or (proof.link ~= nil and addon.Item.key(proof.link, existing.itemID) ~= proof.key)
        then
            return false
        end
        local record = copyRecord(existing)
        local gain
        for _, entry in ipairs(record.gains) do
            for _, id in ipairs(entry.corrections or {}) do
                if id == proof.id then
                    return false
                end
            end
            if entry.id == proof.gainID then
                gain = entry
            end
        end
        local newLink = false
        if proof.link then
            newLink = true
            for _, storedLink in ipairs(record.links) do
                if storedLink == proof.link then
                    newLink = false
                end
            end
        end
        if
            not gain
            or gain.method ~= proof.fromMethod
            or not sameSource(gain.source, proof.fromSource)
            or proof.quantity > gain.quantity - (gain.refunded or 0)
            or (
                gain.method == proof.method
                and sameSource(gain.source, proof.source)
                and (not proof.context or (gain.context and gain.context.id == proof.context.id))
                and not newLink
            )
        then
            return false
        end
        -- A refund references a complete purchase. Never split or reclassify it.
        if gain.method == "Vendor" and (proof.method ~= "Vendor" or proof.quantity ~= gain.quantity) then
            return false
        end
        if proof.quantity < gain.quantity then
            local share = copyValue(gain)
            gain.quantity = gain.quantity - proof.quantity
            share.id = gain.id .. ":proof:" .. proof.id
            share.quantity = proof.quantity
            share.refunded = nil
            record.gains[#record.gains + 1] = share
            gain = share
        end
        gain.method = proof.method
        gain.source = copyValue(proof.source)
        gain.context = copyValue(proof.context)
        gain.corrections = gain.corrections or {}
        gain.corrections[#gain.corrections + 1] = proof.id
        if proof.link then
            local found = false
            for _, storedLink in ipairs(record.links) do
                if storedLink == proof.link then
                    found = true
                end
            end
            if not found then
                record.links[#record.links + 1] = proof.link
            end
        end
        if not validRecord(proof.key, record) then
            return false
        end
        local records = {}
        records[proof.key] = record
        saveFields({ records = records })
        valid[proof.key] = copyRecord(record)
        return true
    end

    function store.breakdown(_self, key, scope)
        local record = valid[key]
        if not record then
            return nil
        end
        scope = scope or {}
        local scoped = scope.character ~= nil or scope.realm ~= nil
        local function matches(character, realm)
            return (not scope.character or scope.character == character) and (not scope.realm or scope.realm == realm)
        end
        local initial = not scoped and record.firstSeenUnits or nil
        local result = {
            initial = initial,
            gained = scoped and 0 or record.totalGained,
            methods = initial and { Seen = initial } or {},
            sources = initial and { ["Initial stock"] = initial } or {},
        }
        local containers = {}
        for _, gain in ipairs(record.gains) do
            if matches(gain.character, gain.realm) then
                local quantity = gain.quantity - (gain.refunded or 0)
                if scoped then
                    result.gained = result.gained + quantity
                end
                result.methods[gain.method] = (result.methods[gain.method] or 0) + quantity
                local source = gain.source
                local id = containerID(source)
                if id and not gain.context then
                    local group = containers[id] or { quantity = 0, names = {} }
                    containers[id] = group
                    group.quantity = group.quantity + quantity
                    if source.name then
                        group.names[source.name] = true
                    end
                else
                    local label = Schema.sourceText(source)
                    if gain.mailKind == "auction-purchase" then
                        label = "Auction purchase"
                    end
                    if gain.context then
                        label = gain.context.name or (gain.context.kind .. " " .. gain.context.id)
                    end
                    result.sources[label] = (result.sources[label] or 0) + quantity
                end
            end
        end
        local labels = {}
        for id, group in pairs(containers) do
            local name = next(group.names)
            -- Conflicting recorded names stay neutral rather than picking one.
            local label = name and not next(group.names, name) and name or ("Container #" .. id)
            group.label = label
            labels[label] = (labels[label] or 0) + 1
        end
        for id, group in pairs(containers) do
            local label = group.label
            if labels[label] > 1 or result.sources[label] ~= nil then
                label = label .. " (container #" .. id .. ")"
            end
            result.sources[label] = group.quantity
        end
        if initial then
            result.recorded = initial + result.gained
        end
        return result
    end

    local function reserveCandidate(kind, detail, at, actor, cost)
        if not endCorrelation(at, "expired") then
            return false
        end
        local count = 0
        for _, entry in ipairs(candidates) do
            if entry.character == actor.character and entry.realm == actor.realm then
                count = count + 1
            end
        end
        cost = cost or 1
        if count + cost > 256 then
            local evidence = evidenceState()
            retain(evidence, kind, "overflow", at, actor, detail)
            saveFields({ evidence = evidence })
            return false
        end
        for _ = 1, cost do
            candidates[#candidates + 1] = { at = at, character = actor.character, realm = actor.realm }
        end
        return true
    end

    -- A new store is a login/reload boundary, never a continuation of a match.
    endCorrelation(0, "reload")

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

    function store.count(_self)
        return #recordKeys
    end
    function store.revision(_self)
        return revision
    end
    -- A stable-length cursor copies one record at a time. Consumers restart when
    -- the revision changes; no query can edit permanent records through it.
    function store.cursor(_self)
        local index, count = 0, #recordKeys
        return function()
            index = index + 1
            if index <= count then
                return copyRecord(valid[recordKeys[index]])
            end
        end
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
            for _, actor in pairs(actorIndex) do
                add(actor.character, actor.realm)
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
            and at - session.openedAt < 60
            and (
                (session.closedAt == nil and session.endedAt == nil)
                or at <= (session.closedAt or session.endedAt) + 60
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

    local function attributeLoot(session, key, record)
        local slot = session.slots[key]
        local shares = slot and slot.shares
        if not shares then
            return
        end
        local gainID = tostring(session.id) .. ":" .. key
        local gain
        local contributions, total, corrected = {}, 0, false
        for _, entry in ipairs(record.gains) do
            if entry.id == gainID or entry.id:sub(1, #gainID + 7) == gainID .. ":share:" then
                contributions[#contributions + 1] = entry
                total = total + entry.quantity
                corrected = corrected or entry.corrections ~= nil
            end
            if entry.id == gainID then
                gain = entry
            end
        end
        if #contributions > 1 and not corrected and slot.limit == session.awarded[key] and total == slot.limit then
            gain = copyValue(contributions[1])
            gain.id, gain.quantity, gain.source = gainID, total, nil
            for index = #record.gains, 1, -1 do
                local entry = record.gains[index]
                if entry.id == gainID or entry.id:sub(1, #gainID + 7) == gainID .. ":share:" then
                    table.remove(record.gains, index)
                end
            end
            record.gains[#record.gains + 1] = gain
        end
        if not gain then
            for index, share in ipairs(shares) do
                for _, entry in ipairs(record.gains) do
                    if
                        entry.id == gainID .. ":share:" .. index
                        and entry.quantity == share.quantity
                        and not entry.corrections
                        and share.source
                    then
                        entry.source = copyValue(share.source)
                    end
                end
            end
            return
        end
        if gain.corrections then
            return
        end
        -- A partial take needs no division when every possible share proves
        -- the same corpse or container. Missing or different sources still
        -- require the complete measured take below.
        local commonSource = shares[1] and shares[1].source
        for _, share in ipairs(shares) do
            if not sameSource(commonSource, share.source) then
                commonSource = nil
                break
            end
        end
        if commonSource then
            gain.source = copyValue(commonSource)
            return
        end
        if #shares == 1 then
            return
        end
        -- Only a complete, measured take of every slot proves the division.
        if slot.limit ~= session.awarded[key] or gain.quantity ~= slot.limit then
            return
        end
        local proven = 0
        local knownSource = false
        for _, share in ipairs(shares) do
            if not isInteger(share.quantity) or share.quantity < 1 then
                return
            end
            if share.source then
                knownSource = true
            end
            proven = proven + share.quantity
        end
        if proven ~= gain.quantity or not knownSource then
            return
        end
        for index, entry in ipairs(record.gains) do
            if entry == gain then
                table.remove(record.gains, index)
                break
            end
        end
        for index, share in ipairs(shares) do
            local contribution = copyValue(gain)
            contribution.id = gainID .. ":share:" .. index
            contribution.quantity = share.quantity
            contribution.source = copyValue(share.source)
            record.gains[#record.gains + 1] = contribution
        end
    end

    -- Craft/quest receipts can share the chat channel with loot. A newer,
    -- item-specific loot cycle is required to override a confirmed reward.
    local function lootRewardSession(key, at, actor, context)
        local rewards = type(raw.rewards) == "table" and raw.rewards.sessions or nil
        local latest
        for _, reward in ipairs(type(rewards) == "table" and rewards or {}) do
            if
                validRewardSession(reward)
                and reward.confirmed
                and reward.key == key
                and reward.character == actor.character
                and reward.realm == actor.realm
                and at >= reward.at
                and at - reward.at < 60
            then
                if not latest or reward.at > latest.at then
                    latest = reward
                end
            end
        end
        if not latest then
            return false
        end
        local current = context or activeSession(at)
        if
            not current
            or current.openedAt <= latest.at
            or type(current.slots[key]) ~= "table"
            or current.character ~= actor.character
            or current.realm ~= actor.realm
        then
            return true
        end
        return false, current
    end

    local function award(session, key, records, at)
        local receipt = session.receipts[key]
        local record = records[key] or valid[key]
        if type(receipt) ~= "table" or not isInteger(receipt.quantity) or not isInteger(receipt.at) or not record then
            return
        end
        local awarded = isInteger(session.awarded[key]) and session.awarded[key] or 0
        local credit = isInteger(session.credits[key]) and session.credits[key] or 0
        local slot = session.slots[key]
        if type(slot) ~= "table" then
            return
        end
        if lootRewardSession(key, at or receipt.at, session, session) then
            return
        end
        local limit = slot.limit
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
                placeKind = session.placeKind,
                method = "Looted",
                source = type(session.slots[key]) == "table" and session.slots[key].source or nil,
            }
            record.gains[#record.gains + 1] = gain
        end
        record.totalGained = record.totalGained + quantity
        record.firstGained = record.firstGained and math.min(record.firstGained, gain.at) or gain.at
        record.lastGained = record.lastGained and math.max(record.lastGained, gain.at) or gain.at
        if session.discoveries[key] then
            record.evidencedDiscovery = true
            record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
            for _, character in ipairs(record.characters) do
                if character.name == session.character and character.realm == session.realm then
                    character.firstSeenUnits = math.max(0, character.firstSeenUnits - quantity)
                    break
                end
            end
        end
        session.awarded[key] = target
        attributeLoot(session, key, record)
        records[key] = record
    end

    ---@param entries AzerothLedgerLootSlot[]
    ---@return table<string, AzerothLedgerLootSessionSlot>?
    local function lootSlots(entries)
        local slots = {}
        for index, entry in ipairs(entries) do
            if
                type(entry) ~= "table"
                or type(entry.key) ~= "string"
                or not validLootSource(entry.source)
                or (entry.quantity ~= nil and (not isInteger(entry.quantity) or entry.quantity < 1))
            then
                return nil
            end
            local share = {
                source = copyValue(entry.source),
                quantity = entry.quantity,
                slot = entry.slot or index,
                sourceIndex = entry.sourceIndex or 1,
            }
            local slot = slots[entry.key]
            if slot then
                slot.shares[#slot.shares + 1] = share
                slot.source = nil
                slot.limit = slot.limit and entry.quantity and slot.limit + entry.quantity or nil
            else
                slots[entry.key] = { source = copyValue(entry.source), limit = entry.quantity, shares = { share } }
            end
        end
        return slots
    end

    local function competingLoot(session, key, actor)
        local slot = session.slots[key]
        return session.character == actor.character
            and session.realm == actor.realm
            and slot ~= nil
            and (not slot.limit or (session.awarded[key] or 0) < slot.limit)
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
            or not validPlaceKind(context.placeKind)
            or type(context.slots) ~= "table"
        then
            return false
        end
        local baseline = store:area(context.character, context.realm, "bags")
        if not baseline or not baseline.complete then
            return false
        end
        local slots = lootSlots(context.slots)
        if not slots then
            return false
        end
        local baselineQuantities = {}
        local baselineGains = {}
        -- Only currently held and identified loot items need eager baselines.
        for key in pairs(heldKeys(context.character, context.realm, "bags")) do
            local record = valid[key]
            baselineGains[key] = record.totalGained
            baselineQuantities[key] = priorQuantity(record, context.character, context.realm, "bags")
        end
        for key in pairs(slots) do
            baselineGains[key] = baselineGains[key] or (valid[key] and valid[key].totalGained or 0)
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
                    if competingLoot(session, key, context) then
                        slot.source = nil
                        slot.shares = nil
                        session.slots[key].source = nil
                        session.slots[key].shares = nil
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
            placeKind = context.placeKind,
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

    function store.lootSourceProof(_self, slots, at, actor)
        if
            not readable
            or type(slots) ~= "table"
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        for _, proof in ipairs(slots) do
            if
                type(proof) ~= "table"
                or type(proof.key) ~= "string"
                or not validLootSource(proof.source)
                or (proof.quantity ~= nil and (not isInteger(proof.quantity) or proof.quantity < 1))
            then
                return false
            end
        end
        if not store:expireEvidence(at) then
            return false
        end
        local current = activeSession(at)
        if not current or current.character ~= actor.character or current.realm ~= actor.realm then
            return false
        end
        local session = copyValue(current)
        local keys = {}
        local additions = {}
        if not session.closedAt then
            for index, proof in ipairs(slots) do
                local existing = session.slots[proof.key]
                local captured = existing ~= nil and existing.shares == nil
                for _, share in ipairs(existing and existing.shares or {}) do
                    if share.slot == (proof.slot or index) then
                        captured = true
                        break
                    end
                end
                if not captured then
                    local addition = copyValue(proof)
                    addition.slot = proof.slot or index
                    additions[#additions + 1] = addition
                end
            end
        end
        local newSlots = lootSlots(additions) or {}
        if #additions > 0 then
            if not reserveCandidate("lootOpen", { slots = additions }, at, actor, #additions) then
                return false
            end
            for key, slot in pairs(newSlots) do
                local existing = session.slots[key]
                if existing and existing.shares then
                    for _, share in ipairs(slot.shares or {}) do
                        existing.shares[#existing.shares + 1] = share
                    end
                    existing.limit = existing.limit and slot.limit and existing.limit + slot.limit or nil
                    existing.source = nil
                else
                    session.slots[key] = slot
                end
                session.baselineGains[key] = session.baselineGains[key] or (valid[key] and valid[key].totalGained or 0)
                keys[key] = true
            end
        end
        for key, incoming in pairs(lootSlots(slots) or {}) do
            local slot = session.slots[key]
            local gainID = tostring(session.id) .. ":" .. key
            local corrected = false
            for _, entry in ipairs(valid[key] and valid[key].gains or {}) do
                if
                    (entry.id == gainID or entry.id:sub(1, #gainID + 7) == gainID .. ":share:")
                    and entry.corrections
                then
                    corrected = true
                end
            end
            if slot and slot.shares and not corrected then
                for index = #slot.shares, 1, -1 do
                    local share = slot.shares[index]
                    if not share.source and share.quantity then
                        local captured, quantity, known = 0, 0, false
                        local replacement = {}
                        for _, existing in ipairs(slot.shares) do
                            if existing.slot == share.slot then
                                captured = captured + 1
                            end
                        end
                        for _, proof in ipairs(incoming.shares or {}) do
                            if proof.slot == share.slot then
                                replacement[#replacement + 1] = proof
                                quantity = quantity + (proof.quantity or 0)
                                known = known or proof.source ~= nil
                            end
                        end
                        if captured == 1 and #replacement > 1 and known and quantity == share.quantity then
                            table.remove(slot.shares, index)
                            for replacementIndex = #replacement, 1, -1 do
                                table.insert(slot.shares, index, copyValue(replacement[replacementIndex]))
                            end
                            slot.source = nil
                            keys[key] = true
                        end
                    end
                end
            end
        end
        for index, proof in ipairs(slots) do
            if type(proof) ~= "table" or type(proof.key) ~= "string" or not validLootSource(proof.source) then
                return false
            end
            local slot = session.slots[proof.key]
            for _, share in ipairs(slot and slot.shares or {}) do
                if
                    share.slot == (proof.slot or index)
                    and share.sourceIndex == (proof.sourceIndex or 1)
                    and share.quantity == proof.quantity
                    and proof.source
                    and canEnrichLootSource(share.source, proof.source)
                    and not sameSource(share.source, proof.source)
                then
                    share.source = copyValue(proof.source)
                    if #slot.shares == 1 then
                        slot.source = copyValue(proof.source)
                    end
                    keys[proof.key] = true
                end
            end
        end
        if not next(keys) then
            return false
        end
        local loot = copyValue(raw.loot)
        for index, entry in ipairs(loot.sessions) do
            if entry.id == session.id then
                loot.sessions[index] = session
            else
                for key in pairs(newSlots) do
                    if competingLoot(entry, key, actor) then
                        -- An overlapping session cannot prove either source.
                        entry.slots[key].source, entry.slots[key].shares = nil, nil
                        session.slots[key].source, session.slots[key].shares = nil, nil
                    end
                end
            end
        end
        local records = {}
        for key in pairs(keys) do
            if valid[key] then
                local record = copyRecord(valid[key])
                local previous = current.slots[key]
                local gainID = tostring(session.id) .. ":" .. key
                for _, entry in ipairs(record.gains) do
                    if
                        entry.id:sub(1, #gainID + 7) == gainID .. ":share:"
                        and entry.source
                        and not entry.corrections
                    then
                        local previousIndex = tonumber(entry.id:sub(#gainID + 8))
                        local share = previous and previous.shares and previous.shares[previousIndex]
                        for nextIndex, proof in ipairs(session.slots[key].shares or {}) do
                            if
                                share
                                and proof.slot == share.slot
                                and proof.sourceIndex == share.sourceIndex
                                and proof.quantity == share.quantity
                                and sameSource(proof.source, share.source)
                            then
                                entry.id = gainID .. ":share:" .. nextIndex
                                break
                            end
                        end
                    end
                end
                if newSlots[key] and previous and previous.shares and #previous.shares == 1 then
                    for _, entry in ipairs(record.gains) do
                        if entry.id == gainID and entry.source and not entry.corrections then
                            -- Keep already proven units separate from later ambiguous shares.
                            entry.id = gainID .. ":share:1"
                        end
                    end
                end
                attributeLoot(session, key, record)
                records[key] = record
                award(session, key, records, at)
                if not validRecord(key, records[key]) then
                    return false
                end
            end
        end
        local evidence = evidenceState()
        if not evidence then
            return false
        end
        for index = #evidence.unresolved, 1, -1 do
            local entry = evidence.unresolved[index]
            if
                entry.kind == "lootReceipt"
                and entry.reason == "unmatched"
                and entry.character == session.character
                and entry.realm == session.realm
                and entry.at >= session.openedAt
                and entry.at <= at
                and keys[entry.detail.key]
                and session.receipts[entry.detail.key]
            then
                table.remove(evidence.unresolved, index)
            end
        end
        saveFields({ loot = loot, records = records, evidence = evidence })
        for key in pairs(keys) do
            if records[key] then
                valid[key] = copyRecord(records[key])
            end
        end
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
        local handled, preferred = lootRewardSession(receipt.key, at, actor)
        if handled then
            return true
        end
        session = preferred or session
        local current = activeSession(at)
        if
            session
            and current
            and not current.closedAt
            and current.id ~= session.id
            and current.character == actor.character
            and current.realm == actor.realm
            and not current.slots[receipt.key]
        then
            local credit = session.credits[receipt.key] or 0
            local limit = session.slots[receipt.key].limit or math.huge
            if math.min(credit, limit) <= (session.awarded[receipt.key] or 0) then
                session = nil
            end
        end
        if not session then
            local pending = activeSession(at)
            if
                pending
                and not pending.closedAt
                and pending.character == actor.character
                and pending.realm == actor.realm
            then
                -- A personal receipt can precede its readable slot. It remains
                -- unresolved until that same live cycle proves the item.
                local existing = pending.receipts[receipt.key]
                pending.receipts[receipt.key] = {
                    quantity = (existing and existing.quantity or 0) + receipt.quantity,
                    at = existing and existing.at or at,
                }
                saveFields({})
            end
            return false
        end
        if type(session.slots[receipt.key]) ~= "table" then
            return false
        end
        local existing = session.receipts[receipt.key]
        session.receipts[receipt.key] = {
            quantity = (existing and existing.quantity or 0) + receipt.quantity,
            at = existing and existing.at or at,
        }
        local nextRecords = {}
        award(session, receipt.key, nextRecords, at)
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

    local function characterGained(record, character, realm)
        local quantity = 0
        for _, gain in ipairs(record and record.gains or {}) do
            if gain.character == character and gain.realm == realm then
                quantity = quantity + gain.quantity - (gain.refunded or 0)
            end
        end
        return quantity
    end

    local function exchangeState()
        if raw.exchange == nil then
            return { nextID = 1, actions = {}, journal = {} }
        end
        return exchangeHealthy and raw.exchange or nil
    end

    local function pruneExchange(state, at)
        for index = #state.actions, 1, -1 do
            local action = state.actions[index]
            local age = at - action.at
            if
                age > 31 * 86400
                or (
                    age >= 60
                    and (
                        action.status == "canceled"
                        or (
                            action.status == "settled"
                            and (action.direction == "in" or action.transferred == action.quantity)
                        )
                    )
                )
            then
                table.remove(state.actions, index)
            end
        end
    end

    function store.exchangeIntent(_self, intent, at, actor)
        if
            not readable
            or type(intent) ~= "table"
            or (intent.channel ~= "mail" and intent.channel ~= "trade")
            or (intent.direction ~= "in" and intent.direction ~= "out")
            or not isInteger(intent.itemID)
            or intent.itemID < 1
            or addon.Item.key(intent.link, intent.itemID) ~= intent.key
            or not isInteger(intent.quantity)
            or intent.quantity < 1
            or (intent.peerName ~= nil and not isName(intent.peerName))
            or (intent.peerRealm ~= nil and not isName(intent.peerRealm))
            or not validMailKind(intent)
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
            or not isInteger(actor.level)
            or type(actor.place) ~= "string"
            or not validPlaceKind(actor.placeKind)
        then
            return false
        end
        local scope = raw.areas[areaKey(actor.character, actor.realm, "bags")]
        local state = exchangeState()
        if not state or type(scope) ~= "table" or not scope.complete or not validCheckID(scope.checkID) then
            return false
        end
        pruneExchange(state, at)
        local record = valid[intent.key]
        state.actions[#state.actions + 1] = {
            id = state.nextID,
            channel = intent.channel,
            direction = intent.direction,
            key = intent.key,
            itemID = intent.itemID,
            link = intent.link,
            quantity = intent.quantity,
            peerName = intent.peerName,
            peerRealm = intent.peerRealm,
            mailKind = intent.mailKind,
            at = at,
            character = actor.character,
            realm = actor.realm,
            level = actor.level,
            place = actor.place,
            placeKind = actor.placeKind,
            baseline = bagQuantity(record, actor.character, actor.realm),
            baselineGained = characterGained(record, actor.character, actor.realm),
            baselineCheckID = scope.checkID,
            discovery = record == nil,
            confirmed = false,
            status = "pending",
        }
        local id = state.nextID
        state.nextID = id + 1
        saveFields({ exchange = state })
        return id
    end

    function store.exchangeConfirm(_self, channel, direction, at, actor, ids)
        if
            not readable
            or (channel ~= "mail" and channel ~= "trade")
            or (direction ~= "in" and direction ~= "out")
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        if not store:expireEvidence(at) then
            return false
        end
        local state = exchangeState()
        if not state then
            return false
        end
        local changed = false
        for _, action in ipairs(state.actions) do
            if
                action.status == "pending"
                and not action.confirmed
                and action.channel == channel
                and action.direction == direction
                and action.character == actor.character
                and action.realm == actor.realm
                and at >= action.at
                and at - action.at < 60
                and (ids == nil or ids == action.id or (type(ids) == "table" and ids[action.id]))
            then
                action.confirmed = true
                changed = true
            end
        end
        if changed then
            saveFields({ exchange = state })
        end
        return changed
    end

    function store.exchangeCancel(_self, channel, actor)
        local state = exchangeState()
        if
            not readable
            or not state
            or (channel ~= "mail" and channel ~= "trade")
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        local changed = false
        for _, action in ipairs(state.actions) do
            if
                action.channel == channel
                and action.character == actor.character
                and action.realm == actor.realm
                and action.status ~= "settled"
                and action.status ~= "canceled"
            then
                action.status = "canceled"
                changed = true
            end
        end
        if changed then
            saveFields({ exchange = state })
        end
        return changed
    end

    function store.exchangeMarkUnresolved(_self, id, actor)
        local state = exchangeState()
        if
            not readable
            or not state
            or not isInteger(id)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        for _, action in ipairs(state.actions) do
            if
                action.id == id
                and (action.status == "pending" or action.status == "unresolved")
                and action.character == actor.character
                and action.realm == actor.realm
            then
                action.status = "unresolved"
                action.confirmed = false
                saveFields({ exchange = state })
                return true
            end
        end
        return false
    end

    function store.exchangeActivity(_self)
        local state = exchangeState()
        return state and copyArray(state.journal) or {}
    end

    -- Completion signals can arrive before possessions. Adapters keep these
    -- actions separate until every selected unit has actually been measured.
    function store.mailProgress(_self, ids)
        local state = exchangeState()
        if not state or type(ids) ~= "table" or not next(ids) then
            return "ended"
        end
        local remaining, groups = {}, {}
        for id in pairs(ids) do
            remaining[id] = true
        end
        for _, action in ipairs(state.actions) do
            if remaining[action.id] and action.confirmed and action.channel == "mail" and action.direction == "in" then
                local scopeKey = areaKey(action.character, action.realm, "bags")
                local groupKey = table.concat({
                    scopeKey,
                    action.key,
                    action.baseline,
                    action.baselineGained,
                    tostring(action.baselineCheckID),
                }, "\031")
                local group = groups[groupKey]
                    or {
                        scopeKey = scopeKey,
                        key = action.key,
                        character = action.character,
                        realm = action.realm,
                        baseline = action.baseline,
                        baselineGained = action.baselineGained,
                        baselineCheckID = action.baselineCheckID,
                        quantity = 0,
                        at = action.at,
                    }
                groups[groupKey] = group
                group.quantity = group.quantity + action.quantity
                group.at = math.max(group.at, action.at)
                remaining[action.id] = nil
            end
        end
        if next(remaining) then
            return "ended"
        end
        for _, group in pairs(groups) do
            -- Earlier settled takes sharing this baseline already occupy part
            -- of the increase; a later attachment cannot reuse those units.
            for _, action in ipairs(state.actions) do
                if
                    not ids[action.id]
                    and action.status == "settled"
                    and action.direction == "in"
                    and action.key == group.key
                    and action.character == group.character
                    and action.realm == group.realm
                    and action.baseline == group.baseline
                    and action.baselineGained == group.baselineGained
                    and action.baselineCheckID == group.baselineCheckID
                then
                    group.quantity = group.quantity + action.quantity
                end
            end
            local scope = raw.areas[group.scopeKey]
            if
                not scope
                or not scope.complete
                or scope.seenAt < group.at
                or bagQuantity(valid[group.key], group.character, group.realm) < group.baseline + group.quantity
            then
                return "waiting"
            end
        end
        return "measured"
    end

    function store.exchangeUnresolved(_self)
        local state = exchangeState()
        local result = {}
        for _, action in ipairs(state and state.actions or {}) do
            if action.status == "unresolved" then
                local copy = {}
                for key, value in pairs(action) do
                    copy[key] = value
                end
                result[#result + 1] = copy
            end
        end
        return result
    end

    local function settleExchange(state, snapshot, grouped, records)
        if not state or snapshot.area ~= "bags" or not snapshot.complete then
            return
        end
        pruneExchange(state, snapshot.seenAt)
        for _, action in ipairs(state.actions) do
            if
                action.confirmed
                and (action.status == "pending" or action.status == "unresolved")
                and action.character == snapshot.character
                and action.realm == snapshot.realm
                and snapshot.seenAt >= action.at
                and snapshot.seenAt - action.at < 60
            then
                local group = grouped[action.key]
                local current = group and group.quantity or 0
                local delta = current - action.baseline
                if action.direction == "out" then
                    local reserved = 0
                    for _, prior in ipairs(state.actions) do
                        if
                            prior.id < action.id
                            and prior.status == "settled"
                            and prior.direction == "out"
                            and prior.key == action.key
                            and prior.character == action.character
                            and prior.realm == action.realm
                            and prior.baseline == action.baseline
                            and prior.baselineCheckID == action.baselineCheckID
                        then
                            reserved = reserved + prior.quantity
                        end
                    end
                    if
                        action.peerName
                        and action.peerRealm
                        and action.baseline >= action.quantity + reserved
                        and -delta >= action.quantity + reserved
                    then
                        action.status = "settled"
                    else
                        action.status = "unresolved"
                    end
                elseif delta > 0 then
                    local record = records[action.key] or valid[action.key]
                    local otherGains =
                        math.max(0, characterGained(record, action.character, action.realm) - action.baselineGained)
                    local reserved = 0
                    for _, prior in ipairs(state.actions) do
                        if
                            prior.id < action.id
                            and prior.status == "settled"
                            and (prior.isTransfer or prior.isReturn)
                            and prior.key == action.key
                            and prior.character == action.character
                            and prior.realm == action.realm
                            and prior.baseline == action.baseline
                            and prior.baselineCheckID == action.baselineCheckID
                        then
                            reserved = reserved + prior.quantity
                        end
                    end
                    local quantity = math.min(action.quantity, delta - otherGains - reserved)
                    -- A removed mail attachment is a whole stack. A partial
                    -- possessions update cannot identify its completed quantity.
                    if action.channel == "mail" and quantity < action.quantity then
                        action.status = "unresolved"
                    elseif quantity > 0 and record then
                        local playerExchange = action.mailKind == nil
                        local ownSender
                        local senderCandidates = 0
                        local senderKnown = false
                        for _, character in ipairs(playerExchange and store:characters() or {}) do
                            if
                                character.character == action.peerName
                                and (not action.peerRealm or character.realm == action.peerRealm)
                            then
                                senderKnown = true
                            end
                        end
                        if senderKnown then
                            for _, outgoing in ipairs(state.actions) do
                                if
                                    outgoing.status == "settled"
                                    and outgoing.direction == "out"
                                    and outgoing.channel == action.channel
                                    and outgoing.key == action.key
                                    and outgoing.quantity - (outgoing.transferred or 0) >= quantity
                                    and outgoing.character == action.peerName
                                    and (not action.peerRealm or outgoing.realm == action.peerRealm)
                                    and outgoing.peerName == action.character
                                    and outgoing.peerRealm == action.realm
                                then
                                    ownSender = outgoing
                                    senderCandidates = senderCandidates + 1
                                end
                            end
                        end
                        if action.mailKind == "return" then
                            local returned, returnCandidates = nil, 0
                            for _, outgoing in ipairs(state.actions) do
                                if
                                    outgoing.status == "settled"
                                    and outgoing.direction == "out"
                                    and outgoing.channel == "mail"
                                    and outgoing.key == action.key
                                    and outgoing.character == action.character
                                    and outgoing.realm == action.realm
                                    and outgoing.at <= action.at
                                    and outgoing.quantity - (outgoing.transferred or 0) >= quantity
                                    and (
                                        (
                                            action.peerName == outgoing.peerName
                                            and (not action.peerRealm or action.peerRealm == outgoing.peerRealm)
                                        )
                                        or (
                                            action.peerName == action.character
                                            and (not action.peerRealm or action.peerRealm == action.realm)
                                        )
                                    )
                                then
                                    returned, returnCandidates = outgoing, returnCandidates + 1
                                end
                            end
                            if returned and returnCandidates == 1 then
                                returned.transferred = (returned.transferred or 0) + quantity
                                action.isReturn = true
                                action.quantity = quantity
                                action.status = "settled"
                            else
                                action.status = "unresolved"
                            end
                        elseif action.mailKind == "unresolved" then
                            action.status = "unresolved"
                        elseif playerExchange and not action.peerName then
                            action.status = "unresolved"
                        elseif ownSender and senderCandidates == 1 then
                            ownSender.transferred = (ownSender.transferred or 0) + quantity
                            action.peerRealm = ownSender.realm
                            action.isTransfer = true
                            state.journal[#state.journal + 1] = {
                                id = action.id,
                                key = action.key,
                                channel = action.channel,
                                quantity = quantity,
                                at = action.at,
                                sender = ownSender.character,
                                senderRealm = ownSender.realm,
                                recipient = action.character,
                                recipientRealm = action.realm,
                            }
                            action.quantity = quantity
                            action.status = "settled"
                        elseif senderKnown then
                            action.status = "unresolved"
                        else
                            record = copyRecord(record)
                            local gain = {
                                id = "exchange:" .. action.id .. ":" .. action.key,
                                at = action.at,
                                quantity = quantity,
                                character = action.character,
                                realm = action.realm,
                                level = action.level,
                                place = action.place,
                                placeKind = action.placeKind,
                                method = "Obtained",
                                mailKind = action.mailKind,
                                source = playerExchange and action.peerName and action.peerRealm and {
                                    kind = "player",
                                    name = action.peerName,
                                    realm = action.peerRealm,
                                } or nil,
                            }
                            record.gains[#record.gains + 1] = gain
                            record.totalGained = record.totalGained + quantity
                            record.firstGained = record.firstGained and math.min(record.firstGained, action.at)
                                or action.at
                            record.lastGained = record.lastGained and math.max(record.lastGained, action.at)
                                or action.at
                            if action.discovery then
                                record.evidencedDiscovery = true
                                record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
                                for _, seen in ipairs(record.characters) do
                                    if seen.name == action.character and seen.realm == action.realm then
                                        seen.firstSeenUnits = math.max(0, seen.firstSeenUnits - quantity)
                                        break
                                    end
                                end
                            end
                            records[action.key] = record
                            action.quantity = quantity
                            action.status = "settled"
                        end
                    else
                        action.status = "unresolved"
                    end
                else
                    action.status = "unresolved"
                end
            end
        end
    end

    local function vendorState()
        if raw.vendor == nil then
            return { nextID = 1, actions = {}, journal = {} }
        end
        if vendorHealthy then
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
                vendorName = action.vendorName,
            }
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
            or not validPlaceKind(actor.placeKind)
            or (actor.vendorName ~= nil and not isName(actor.vendorName))
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
            placeKind = actor.placeKind,
            vendorName = actor.vendorName,
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
                and at - action.at < 60
            then
                local group = grouped[action.key]
                local current = group and group.quantity or 0
                local delta = current - action.baseline
                local record = records[action.key] or valid[action.key]
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
                                placeKind = action.placeKind,
                                method = "Vendor",
                                source = action.vendorName and { kind = "vendor", name = action.vendorName } or nil,
                            }
                            record.gains[#record.gains + 1] = gain
                            record.totalGained = record.totalGained + quantity
                            record.firstGained = record.firstGained and math.min(record.firstGained, action.at)
                                or action.at
                            record.lastGained = record.lastGained and math.max(record.lastGained, action.at)
                                or action.at
                            if not valid[action.key] then
                                record.evidencedDiscovery = true
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
            if action.status == "pending" and at - action.at >= 60 then
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
                and at - action.at < 60
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

    local function rewardSessions(at)
        local result = {}
        local rewards = raw.rewards
        local sessions = type(rewards) == "table" and rewards.sessions or nil
        for _, session in ipairs(type(sessions) == "table" and sessions or {}) do
            if validRewardSession(session) and at >= session.at and at - session.at < 60 then
                result[#result + 1] = session
            end
        end
        return result
    end

    local function questPreparations(at)
        local result = {}
        local rewards = raw.rewards
        local preparations = type(rewards) == "table" and rewards.preparations or nil
        for _, preparation in ipairs(type(preparations) == "table" and preparations or {}) do
            if at >= preparation.at and at - preparation.at < 60 then
                result[#result + 1] = preparation
            end
        end
        return result
    end

    local function questPreparation(questID, at, actor)
        local preparations = questPreparations(at)
        for index = #preparations, 1, -1 do
            local preparation = preparations[index]
            if
                preparation.questID == questID
                and preparation.character == actor.character
                and preparation.realm == actor.realm
            then
                return preparation
            end
        end
        return nil
    end

    function store.questPrepared(_self, questID, at, actor)
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
        local area = store:area(actor.character, actor.realm, "bags")
        local equippedArea = store:area(actor.character, actor.realm, "equipped")
        if
            not area
            or not area.complete
            or area.seenAt > at
            or not equippedArea
            or not equippedArea.complete
            or equippedArea.seenAt ~= area.seenAt
        then
            return false
        end
        local existing = questPreparation(questID, at, actor)
        if existing and not existing.confirmed then
            return false
        end
        local rewards = type(raw.rewards) == "table" and raw.rewards or nil
        local nextID = (rewards and isInteger(rewards.nextID) and rewards.nextID or 0) + 1
        local baseline = {}
        local possessions = {}
        for _, storageArea in ipairs({ "bags", "equipped" }) do
            for key in pairs(heldKeys(actor.character, actor.realm, storageArea)) do
                possessions[key] = true
            end
        end
        for key in pairs(possessions) do
            local record = valid[key]
            baseline[key] = {
                quantity = bagQuantity(record, actor.character, actor.realm)
                    + areaQuantity(record, actor.character, actor.realm, "equipped"),
                gained = record.totalGained,
            }
        end
        local preparations = {}
        for _, preparation in ipairs(questPreparations(at)) do
            if
                preparation.questID ~= questID
                or preparation.character ~= actor.character
                or preparation.realm ~= actor.realm
            then
                preparations[#preparations + 1] = preparation
            end
        end
        preparations[#preparations + 1] = {
            id = nextID,
            questID = questID,
            character = actor.character,
            realm = actor.realm,
            at = at,
            confirmed = false,
            baseline = baseline,
        }
        saveFields({ rewards = { nextID = nextID, sessions = rewardSessions(at), preparations = preparations } })
        return true
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
            or not validPlaceKind(actor.placeKind)
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
        local preparation = receipt.method == "Quest" and context and questPreparation(context.id, at, actor) or nil
        local sessions = rewardSessions(at)
        local session
        for _, existing in ipairs(sessions) do
            local awaitingReward = not existing.confirmed or existing.awarded < existing.quantity
            if
                existing.key == receipt.key
                and existing.method == receipt.method
                and existing.character == actor.character
                and existing.realm == actor.realm
                and (not receipt.preview or existing.choiceGroup == receipt.choiceGroup)
                and (not preparation or existing.questPreparationID == preparation.id)
                and (receipt.method ~= "Quest" or preparation or awaitingReward)
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
            local before = preparation and preparation.baseline[receipt.key] or nil
            if preparation and not before and valid[receipt.key] then
                before = { quantity = 0, gained = valid[receipt.key].totalGained }
                preparation.baseline[receipt.key] = before
            end
            session = {
                id = nextID,
                key = receipt.key,
                method = receipt.method,
                context = context,
                character = actor.character,
                realm = actor.realm,
                level = actor.level,
                place = actor.place,
                placeKind = actor.placeKind,
                at = at,
                baseline = preparation and (before and before.quantity or 0)
                    or bagQuantity(valid[receipt.key], actor.character, actor.realm),
                baselineGained = preparation and (before and before.gained or 0)
                    or (valid[receipt.key] and valid[receipt.key].totalGained or 0),
                quantity = 0,
                awarded = 0,
                discovery = preparation and (not before or before.discovery == true) or not valid[receipt.key],
                confirmed = receipt.method == "Crafted" or (preparation and preparation.confirmed) or false,
                choiceGroup = receipt.choiceGroup,
                specific = receipt.method == "Quest" and not receipt.preview or nil,
                questPreparationID = preparation and preparation.id or nil,
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
        saveFields({ rewards = { nextID = nextID, sessions = sessions, preparations = questPreparations(at) } })
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
        if not store:expireEvidence(at) then
            return false
        end
        local changed = false
        local preparation = questPreparation(questID, at, actor)
        if preparation and not preparation.confirmed then
            preparation.confirmed = true
            changed = true
        end
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
            local rewards = raw.rewards
            saveFields({
                rewards = {
                    nextID = rewards.nextID,
                    sessions = rewardSessions(at),
                    preparations = questPreparations(at),
                },
            })
        end
        return changed
    end

    local function awardReward(session, key, currentQuantity, records)
        local record = records[key] or valid[key]
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
                placeKind = session.placeKind,
                method = session.method,
                context = session.context,
            }
            record.gains[#record.gains + 1] = gain
        end
        record.totalGained = record.totalGained + quantity
        record.firstGained = record.firstGained and math.min(record.firstGained, gain.at) or gain.at
        record.lastGained = record.lastGained and math.max(record.lastGained, gain.at) or gain.at
        if session.discovery then
            record.evidencedDiscovery = true
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
        local priorScope = raw.areas[areaKey(snapshot.character, snapshot.realm, snapshot.area)]
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
        local oldScope = raw.areas[scopeKey]
        if type(oldScope) == "table" and isInteger(oldScope.seenAt) and snapshot.seenAt < oldScope.seenAt then
            return false
        end
        local nextRecords = {}
        local activeRewards = (snapshot.area == "bags" or snapshot.area == "equipped")
                and snapshot.complete
                and rewardSessions(snapshot.seenAt)
            or {}
        for key, group in pairs(grouped) do
            local session = snapshot.area == "bags" and snapshot.complete and activeSession(snapshot.seenAt) or nil
            if session and (session.character ~= snapshot.character or session.realm ~= snapshot.realm) then
                session = nil
            end
            if session and type(oldScope) == "table" and oldScope.complete and not unresolvedIdentity then
                local baselineQuantity = isInteger(session.baselineQuantities[key]) and session.baselineQuantities[key]
                    or 0
                local increase = group.quantity - baselineQuantity
                if increase > 0 then
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
                award(session, key, nextRecords, snapshot.seenAt)
            end
            if snapshot.area == "bags" and snapshot.complete and type(oldScope) == "table" and oldScope.complete then
                for _, reward in ipairs(activeRewards) do
                    if
                        reward.key == key
                        and not reward.questPreparationID
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
        local bagArea = store:area(snapshot.character, snapshot.realm, "bags")
        if
            snapshot.area == "equipped"
            and snapshot.complete
            and bagArea
            and bagArea.complete
            and bagArea.seenAt == snapshot.seenAt
        then
            local quantities = {}
            for _, reward in ipairs(activeRewards) do
                if reward.questPreparationID then
                    local record = nextRecords[reward.key] or valid[reward.key]
                    local equipped = grouped[reward.key]
                    quantities[reward.key] = {
                        quantity = bagQuantity(record, snapshot.character, snapshot.realm)
                            + (equipped and equipped.quantity or 0),
                    }
                end
            end
            for _, reward in ipairs(activeRewards) do
                if
                    reward.questPreparationID
                    and reward.character == snapshot.character
                    and reward.realm == snapshot.realm
                    and choiceIsProven(reward, activeRewards, quantities)
                then
                    awardReward(reward, reward.key, quantities[reward.key].quantity, nextRecords)
                end
            end
        end
        local vendor = vendorState()
        if vendor and #vendor.actions == 0 then
            vendor = nil
        end
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
        local exchange = exchangeState()
        if exchange and #exchange.actions == 0 then
            exchange = nil
        end
        if snapshot.area == "bags" and snapshot.complete and type(oldScope) == "table" and oldScope.complete then
            settleExchange(exchange, snapshot, grouped, nextRecords)
        end
        local nextAreas = {}
        for key, state in pairs(raw.areas) do
            nextAreas[key] = state
        end
        nextAreas[scopeKey] = {
            seenAt = snapshot.seenAt,
            checkID = (type(oldScope) == "table" and oldScope.checkID or 0) + 1,
            complete = snapshot.complete,
            character = snapshot.character,
            realm = snapshot.realm,
        }
        saveFields({
            records = nextRecords,
            areas = nextAreas,
            vendor = vendor,
            exchange = exchange,
            evidence = evidence,
        })
        for key, record in pairs(nextRecords) do
            if valid[key] or grouped[key] then
                valid[key] = copyRecord(record)
            end
        end
        return true
    end

    -- Count incoming candidate signals at the public boundary, across all
    -- channels for each character. Overflow is retained before it can match.
    local function validCandidate(name, detail, actor)
        if name == "questPrepared" then
            return isInteger(detail) and detail > 0
        end
        if type(detail) ~= "table" then
            return false
        end
        if name == "lootOpen" then
            if
                not isInteger(detail.level)
                or type(detail.place) ~= "string"
                or not validPlaceKind(detail.placeKind)
                or type(detail.slots) ~= "table"
            then
                return false
            end
            for _, slot in ipairs(detail.slots) do
                if
                    type(slot) ~= "table"
                    or type(slot.key) ~= "string"
                    or not validLootSource(slot.source)
                    or (slot.quantity ~= nil and (not isInteger(slot.quantity) or slot.quantity < 1))
                then
                    return false
                end
            end
            return true
        end
        if type(detail.key) ~= "string" or not isInteger(detail.quantity) or detail.quantity < 1 then
            return false
        end
        if name == "lootReceipt" or name == "vendorReceipt" then
            return true
        end
        if not isInteger(actor.level) or type(actor.place) ~= "string" or not validPlaceKind(actor.placeKind) then
            return false
        end
        if name == "rewardReceipt" then
            return (detail.method == "Quest" or detail.method == "Crafted")
                and validRewardContext(detail.context, detail.method)
                and (detail.preview == nil or type(detail.preview) == "boolean")
                and (
                    detail.choiceGroup == nil
                    or (isName(detail.choiceGroup) and detail.method == "Quest" and detail.preview == true)
                )
        end
        if
            not isInteger(detail.itemID)
            or detail.itemID < 1
            or addon.Item.key(detail.link, detail.itemID) ~= detail.key
        then
            return false
        end
        if name == "vendorAction" then
            return vendorKinds[detail.kind] == true
                and (detail.area == nil or detail.area == "bags" or detail.area == "equipped")
                and (actor.vendorName == nil or isName(actor.vendorName))
        end
        return (detail.channel == "mail" or detail.channel == "trade")
            and (detail.direction == "in" or detail.direction == "out")
            and (detail.peerName == nil or isName(detail.peerName))
            and (detail.peerRealm == nil or isName(detail.peerRealm))
    end
    for _, name in ipairs({
        "lootOpen",
        "lootReceipt",
        "rewardReceipt",
        "questPrepared",
        "vendorAction",
        "vendorReceipt",
        "exchangeIntent",
    }) do
        local command = store[name]
        store[name] = function(self, detail, at, actor, ...)
            if name == "lootOpen" then
                actor = detail
                at = type(detail) == "table" and detail.at or nil
            end
            if
                readable
                and isInteger(at)
                and at >= 0
                and type(actor) == "table"
                and isName(actor.character)
                and isName(actor.realm)
                and validCandidate(name, detail, actor)
            then
                local payload = type(detail) == "table" and detail or { value = detail }
                local cost = name == "lootOpen" and type(payload.slots) == "table" and #payload.slots or 1
                if not reserveCandidate(name, payload, at, actor, math.max(1, cost)) then
                    return false
                end
            end
            local result = command(self, detail, at, actor, ...)
            if
                not result
                and (name == "lootReceipt" or name == "vendorReceipt")
                and readable
                and type(detail) == "table"
                and type(detail.key) == "string"
                and isInteger(detail.quantity)
                and detail.quantity > 0
                and isInteger(at)
                and at >= 0
                and type(actor) == "table"
                and isName(actor.character)
                and isName(actor.realm)
            then
                local evidence = evidenceState()
                if evidence then
                    retain(evidence, name, "unmatched", at, actor, detail)
                    saveFields({ evidence = evidence })
                end
            end
            return result
        end
    end

    return store
end

addon.Schema = Schema
