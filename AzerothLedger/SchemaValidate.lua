local _, addon = ...

-- Pure saved-data validators, copy helpers, source grouping and the display,
-- color, book and retention option tables. Nothing here reads or writes a store.

local displayOptions = {
    { key = "tooltips", name = "Show Collection facts in item tooltips", default = true, section = "Tooltips" },
    { key = "tooltipDetails", name = "Show dated storage checks in tooltips", default = true, section = "Tooltips" },
    { key = "toasts", name = "Show first-discovery notifications", default = true, section = "Notifications" },
    { key = "toastCombat", name = "Show notifications during combat", default = true, section = "Notifications" },
    { key = "toastSound", name = "Play a discovery sound", default = false, section = "Notifications" },
    {
        key = "toastDuration",
        name = "Notification duration (seconds)",
        default = 5,
        minimum = 2,
        maximum = 15,
        step = 1,
        section = "Notifications",
    },
    {
        key = "toastScale",
        name = "Notification size",
        default = 1,
        minimum = 0.7,
        maximum = 1.5,
        step = 0.05,
        section = "Notifications",
    },
    {
        key = "toastX",
        name = "Notification horizontal offset",
        default = 0,
        minimum = -800,
        maximum = 800,
        step = 10,
        section = "Notifications",
    },
    {
        key = "toastY",
        name = "Notification distance from top",
        default = 150,
        minimum = 0,
        maximum = 800,
        step = 10,
        section = "Notifications",
    },
    { key = "lockWindow", name = "Lock window position", default = false, section = "Appearance" },
    { key = "reducedMotion", name = "Reduce motion", default = false, section = "Appearance" },
    { key = "qualityColors", name = "Use item-quality colors for item names", default = true, section = "Appearance" },
    {
        key = "backgroundOpacity",
        name = "Background opacity",
        default = 1,
        minimum = 0.3,
        maximum = 1,
        step = 0.05,
        section = "Appearance",
    },
}
local colorOptions = {
    { key = "canvas", name = "Window background", default = { 0.065, 0.07, 0.075, 1 } },
    { key = "panel", name = "Panel background", default = { 0.105, 0.11, 0.115, 1 } },
    { key = "raised", name = "Control background", default = { 0.15, 0.15, 0.145, 1 } },
    { key = "edge", name = "Borders and dividers", default = { 0.28, 0.26, 0.22, 1 } },
    { key = "text", name = "Main text", default = { 0.94, 0.91, 0.85, 1 } },
    { key = "muted", name = "Secondary text", default = { 0.67, 0.66, 0.62, 1 } },
    { key = "gold", name = "Accent and headings", default = { 0.87, 0.72, 0.46, 1 } },
    { key = "selected", name = "Selected row", default = { 0.25, 0.215, 0.15, 1 } },
    { key = "green", name = "Present status", default = { 0.49, 0.75, 0.54, 1 } },
}
local displayDefaults, displayDefinitions = {}, {}
for _, definition in ipairs(displayOptions) do
    displayDefaults[definition.key], displayDefinitions[definition.key] = definition.default, definition
end
for _, definition in ipairs(colorOptions) do
    displayDefaults[definition.key], displayDefinitions[definition.key] = definition.default, definition
end
local function validDisplayField(key, value)
    local definition = displayDefinitions[key]
    if not definition then
        return false
    end
    if type(definition.default) == "boolean" then
        return type(value) == "boolean"
    elseif type(definition.default) == "number" then
        return type(value) == "number" and value >= definition.minimum and value <= definition.maximum
    end
    if type(value) ~= "table" then
        return false
    end
    for index in pairs(value) do
        if type(index) ~= "number" or index < 1 or index > 4 or index ~= math.floor(index) then
            return false
        end
    end
    for index = 1, 4 do
        if type(value[index]) ~= "number" or not (value[index] >= 0 and value[index] <= 1) then
            return false
        end
    end
    return value[4] == 1
end
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
---@field transferredUnits? integer Units first seen here that arrived from another of your characters.

---@class AzerothLedgerAreaState
---@field seenAt integer
---@field complete boolean
---@field lastCompleteAt? integer
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
---@field openedAt? integer Loot session open time, used to avoid double counting a first snapshot
---@field baselinePossessionsComplete? boolean
---@field quantity integer
---@field character string
---@field realm string
---@field level integer
---@field place string
---@field placeKind? 'zone'|'dungeon'
---@field method 'Looted'|'Quest'|'Crafted'|'Vendor'|'Obtained'
---@field mailKind? 'auction-purchase'
---@field channel? 'mail'|'trade'
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
---@field baselinePossessions? table<string, integer>
---@field baselineEquipmentUncertain? boolean
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
---@field stage? "accept"
---@field acceptedAt? integer
---@field level? integer
---@field place? string
---@field placeKind? "zone"|"dungeon"
---@field name? string

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
---@field level? integer
---@field place? string
---@field placeKind? 'zone'|'dungeon'
---@field linkedGainID? string
---@field linkedSaleID? integer
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
---@field level? integer
---@field place? string
---@field placeKind? 'zone'|'dungeon'
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
---@field firstSeenLater? boolean
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
---@field display? table
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

---@class ALEvidenceViewEntry
---@field id string
---@field kind string
---@field reason string
---@field at integer
---@field character string
---@field realm string
---@field key? string
---@field link? string
---@field itemID? integer
---@field quantity? integer
---@field action? string
---@field method? string
---@field channel? string
---@field direction? string
---@field area? string
---@field location? string
---@field confirmed? boolean
---@field sourceKnown boolean
---@field preparationID? integer

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

---@class ALRecordDescription
---@field key string
---@field itemID integer
---@field firstSeen integer
---@field lastSeen integer
---@field firstSeenUnits integer
---@field totalGained integer
---@field evidencedDiscovery? boolean
---@field firstGained? integer
---@field lastGained? integer
---@field links string[]
---@field characters AzerothLedgerCharacterSeen[]
---@field observations AzerothLedgerObservation[]

---@class ALTooltipFacts
---@field methods table<string, boolean>
---@field hasGains boolean
---@field source string

---@class AzerothLedgerStore
---@field diagnostic fun(self: AzerothLedgerStore): AzerothLedgerDiagnostic
---@field marker fun(self: AzerothLedgerStore): string?
---@field environment fun(self: AzerothLedgerStore): AzerothLedgerEnvironment?
---@field list fun(self: AzerothLedgerStore): AzerothLedgerRecord[]
---@field describe fun(self: AzerothLedgerStore, key: string): ALRecordDescription?
---@field tooltipFacts fun(self: ALStore, key: string): ALTooltipFacts?
---@field count fun(self: AzerothLedgerStore): integer
---@field revision fun(self: AzerothLedgerStore): integer
---@field cursor fun(self: AzerothLedgerStore, pause?: fun()): fun(): AzerothLedgerRecord?
---@field find fun(self: AzerothLedgerStore, key: string, pause?: fun()): AzerothLedgerRecord?
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
---@field questOffered fun(self: AzerothLedgerStore, questID: integer, at: integer, actor: ALActor): boolean
---@field questAccepted fun(self: AzerothLedgerStore, questID: integer, at: integer, actor: table): boolean
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
---@field book fun(self: ALStore): ALBookPreferences
---@field setBook fun(self: ALStore, preferences: ALBookPreferences): boolean
---@field display fun(self: ALStore): table
---@field displayRevision fun(self: ALStore): integer
---@field setDisplay fun(self: ALStore, control: string, value: any): boolean
---@field takeDiscoveries fun(self: ALStore): AzerothLedgerRecord[]
---@field journal fun(self: ALStore, pause?: fun()): table[]
---@field unresolved fun(self: AzerothLedgerStore): AzerothLedgerEvidence[]
---@field visitEvidence fun(self: AzerothLedgerStore, visit: fun(entry: ALEvidenceViewEntry), pause?: fun()): table
---@field evidenceStatus fun(self: AzerothLedgerStore): table
---@field evidenceSummary fun(self: AzerothLedgerStore): AzerothLedgerEvidenceState
---@field expireEvidence fun(self: AzerothLedgerStore, at: integer): boolean
---@field correctGain fun(self: AzerothLedgerStore, proof: AzerothLedgerGainCorrection): boolean
---@field breakdown fun(self: ALStore, key: string, scope?: ALCountScope, pause?: fun()): AzerothLedgerBreakdown?
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

local function trimHistory(rows, limit, sorted)
    if not sorted then
        table.sort(rows, chronological)
    end
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
            or (session.baselineEquipmentUncertain ~= nil and type(session.baselineEquipmentUncertain) ~= "boolean")
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
        if session.baselinePossessions ~= nil then
            if type(session.baselinePossessions) ~= "table" then
                return false
            end
            for key, quantity in pairs(session.baselinePossessions) do
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

-- Keep the first positive check per actor and the latest check per storage area.
-- Earlier quantity changes do not add ownership evidence or lifetime gains.
local function compactObservations(observations)
    local first, latest, last, keep = {}, {}, {}, {}
    for index, observation in ipairs(observations) do
        local actor = areaKey(observation.character, observation.realm, "")
        local scope = areaKey(observation.character, observation.realm, observation.area)
        if observation.quantity > 0 and not first[actor] then
            first[actor], keep[index] = index, true
        end
        if not latest[scope] or observation.seenAt >= observations[latest[scope]].seenAt then
            latest[scope] = index
        end
        last[scope] = index
    end
    for _, index in pairs(latest) do
        keep[index] = true
    end
    -- Scan reconciliation uses array order; dated projections use timestamps.
    -- Valid input need not be chronological, so preserve both interpretations.
    for _, index in pairs(last) do
        keep[index] = true
    end
    local result = {}
    for index, observation in ipairs(observations) do
        if keep[index] then
            result[#result + 1] = copyValue(observation)
        end
    end
    return result
end

-- Internal scans share unchanged gains and stage only the current acquisition root.
-- Public copies materialize staged roots and may yield once per contribution.
local function copyRecord(record, shareGains, pause)
    local source = record.gains
    if record.baseGains and not shareGains then
        source = {}
        local inserted = {}
        for _, gain in ipairs(record.baseGains) do
            local root = gainRoot(gain.id)
            if not record.gainEdits[root] then
                source[#source + 1] = gain
            elseif not inserted[root] then
                for _, entry in ipairs(record.gainEdits[root]) do
                    source[#source + 1] = entry
                end
                inserted[root] = true
            end
        end
        for root, entries in pairs(record.gainEdits) do
            if not inserted[root] then
                for _, entry in ipairs(entries) do
                    source[#source + 1] = entry
                end
            end
        end
    end
    local gains = shareGains and record.gains or {}
    for index, gain in ipairs(not shareGains and source or {}) do
        gains[index] = {
            id = gain.id,
            at = gain.at,
            openedAt = gain.openedAt,
            baselinePossessionsComplete = gain.baselinePossessionsComplete,
            quantity = gain.quantity,
            character = gain.character,
            realm = gain.realm,
            level = gain.level,
            place = gain.place,
            placeKind = gain.placeKind,
            method = gain.method,
            mailKind = gain.mailKind,
            channel = gain.channel,
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
        if pause then
            pause()
        end
    end
    local result = {
        key = record.key,
        itemID = record.itemID,
        firstSeen = record.firstSeen,
        lastSeen = record.lastSeen,
        firstSeenUnits = record.firstSeenUnits,
        firstSeenLater = record.firstSeenLater,
        totalGained = record.totalGained,
        evidencedDiscovery = record.evidencedDiscovery,
        gains = gains,
        firstGained = record.firstGained,
        lastGained = record.lastGained,
        links = copyArray(record.links),
        characters = copyArray(record.characters),
        observations = copyArray(record.observations),
    }
    if shareGains then
        result.baseGains, result.gainEdits = record.baseGains, record.gainEdits
    end
    return result
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
            or (gain.channel ~= nil and gain.channel ~= "mail" and gain.channel ~= "trade")
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

-- A turn-in preparation lasts 60 seconds. An accept preparation waits up to
-- ten minutes for QUEST_ACCEPTED, then 60 seconds for the handed-over items.
local function preparationLive(preparation, at)
    if preparation.stage == "accept" then
        if isInteger(preparation.acceptedAt) then
            return at >= preparation.acceptedAt and at - preparation.acceptedAt < 60
        end
        return at >= preparation.at and at - preparation.at < 600
    end
    return at >= preparation.at and at - preparation.at < 60
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
            or (preparation.stage ~= nil and preparation.stage ~= "accept")
            or (preparation.acceptedAt ~= nil and not isInteger(preparation.acceptedAt))
            or (preparation.level ~= nil and not isInteger(preparation.level))
            or (preparation.place ~= nil and type(preparation.place) ~= "string")
            or not validPlaceKind(preparation.placeKind)
            or (preparation.name ~= nil and not isName(preparation.name))
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
            or (entry.level ~= nil and not isInteger(entry.level))
            or (entry.place ~= nil and type(entry.place) ~= "string")
            or not validPlaceKind(entry.placeKind)
            or (entry.linkedGainID ~= nil and type(entry.linkedGainID) ~= "string")
            or (entry.linkedSaleID ~= nil and (not isInteger(entry.linkedSaleID) or entry.linkedSaleID < 1))
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
            or (activity.level ~= nil and not isInteger(activity.level))
            or (activity.place ~= nil and type(activity.place) ~= "string")
            or not validPlaceKind(activity.placeKind)
        then
            return false
        end
    end
    return true
end

local Validate = {}

function Validate.displayOptions()
    return copyValue(displayOptions)
end

function Validate.colorOptions()
    return copyValue(colorOptions)
end

-- The entry ID identifies the creature/container type; the final field identifies a
-- particular spawn. Keep the complete GUID in the gain as its original proof.
local function entryID(source)
    if not source or (source.kind ~= "container" and source.kind ~= "mob") then
        return nil
    end
    local prefix = source.kind == "container" and "GameObject" or "Creature"
    local id = source.guid:match("^" .. prefix .. "%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    local entry = id and tonumber(id)
    return entry and entry > 0 and entry <= 4294967295 and tostring(entry) or nil
end

---@param source? AzerothLedgerLootSource|AzerothLedgerVendorSource|AzerothLedgerPlayerSource
---@return string
function Validate.sourceText(source)
    if not source then
        return "Unknown"
    elseif source.kind == "player" then
        return source.name .. "-" .. source.realm
    end
    local id = entryID(source)
    local kind = source.kind == "container" and "Container" or "Mob"
    return source.name or (id and (kind .. " #" .. id)) or ("Unnamed " .. source.kind)
end

-- Identity is independent of its display name. Unparseable GUIDs remain
-- separate spawn evidence; vendor names explicitly carry no proven ID.
---@param gain AzerothLedgerGain
---@return string key
---@return string neutral
---@return string? name
function Validate.sourceIdentity(gain)
    local context = gain.context
    if context then
        local kind = context.kind == "quest" and "Quest" or "Recipe"
        return context.kind .. ":" .. context.id, kind .. " #" .. context.id, context.name
    elseif gain.mailKind == "auction-purchase" then
        return "auction", "Auction purchase"
    end
    local source = gain.source
    if not source then
        return "unknown", "Unknown"
    elseif source.kind == "player" then
        local label = source.name .. "-" .. source.realm
        return "player:" .. label, "Player: " .. label
    elseif source.kind == "vendor" then
        return "vendor:" .. source.name, "Vendor: " .. source.name
    end
    local id = entryID(source)
    local kind = source.kind == "container" and "Container" or "Mob"
    return source.kind .. ":" .. (id or source.guid),
        id and (kind .. " #" .. id) or ("Unknown " .. source.kind),
        source.name
end

---@class ALSourceGroup
---@field key string
---@field neutral string
---@field quantity integer
---@field names table<string, boolean>
---@field label? string

---@param groups table<string, ALSourceGroup>
---@param gain AzerothLedgerGain
---@param quantity integer
function Validate.addSource(groups, gain, quantity)
    if quantity <= 0 then
        return
    end
    local key, neutral, name = Validate.sourceIdentity(gain)
    local group = groups[key] or { key = key, neutral = neutral, quantity = 0, names = {} }
    groups[key] = group
    group.quantity = group.quantity + quantity
    if name then
        group.names[name] = true
    end
end

---@param groups table<string, ALSourceGroup>
---@param pause? fun()
---@return ALSourceGroup[]
function Validate.sourceGroups(groups, pause)
    -- Source comparisons are small; checkpoint in bounded batches rather than
    -- spending a coroutine resume on each comparison of a large source list.
    local steps = 0
    local checkpoint = pause
            and function()
                steps = steps + 1
                if steps == 8 then
                    steps = 0
                    pause()
                end
            end
        or nil
    local rows, labels = {}, {}
    for _, group in pairs(groups) do
        local name = next(group.names)
        group.label = name and not next(group.names, name) and name or group.neutral
        labels[group.label] = (labels[group.label] or 0) + 1
        rows[#rows + 1] = group
        if checkpoint then
            checkpoint()
        end
    end
    addon.Work.sort(rows, function(left, right)
        return left.key < right.key
    end, checkpoint)
    local used = { ["Initial stock"] = true, ["Appeared later"] = true, ["Your characters"] = true }
    for index, group in ipairs(rows) do
        if labels[group.label] > 1 or used[group.label] then
            local identity = group.key:match("^(%a+:%d+)$")
            group.label = group.label
                .. " ("
                .. (identity and identity:gsub(":", " #", 1) or ("recorded source " .. index))
                .. ")"
        end
        while used[group.label] do
            group.label = group.label .. " (recorded source " .. index .. ")"
        end
        used[group.label] = true
        if checkpoint then
            checkpoint()
        end
    end
    addon.Work.sort(rows, function(left, right)
        return left.label < right.label or (left.label == right.label and left.key < right.key)
    end, checkpoint)
    return rows
end

local bookChoices = {
    ownership = {
        { label = "Any status" },
        { label = "Present", value = "present" },
        { label = "Unknown", value = "unknown" },
        { label = "Historical only", value = "historical" },
    },
    quality = {
        { label = "Any quality" },
        { label = "Poor", value = 0 },
        { label = "Common", value = 1 },
        { label = "Uncommon", value = 2 },
        { label = "Rare", value = 3 },
        { label = "Epic", value = 4 },
        { label = "Legendary", value = 5 },
        { label = "Artifact", value = 6 },
        { label = "Heirloom", value = 7 },
        { label = "WoW Token", value = 8 },
        { label = "Unknown quality", value = "unknown" },
    },
    method = {
        { label = "Any method" },
        { label = "Already had", value = "Seen" },
        { label = "Appeared later", value = "Appeared" },
        { label = "Looted", value = "Looted" },
        { label = "Quest reward", value = "Quest" },
        { label = "Crafted", value = "Crafted" },
        { label = "Vendor purchase", value = "Vendor" },
        { label = "Obtained", value = "Obtained" },
    },
    sort = {
        { label = "Name A-Z", value = "name" },
        { label = "Discovery: newest", value = "discovered" },
        { label = "Latest gain: newest", value = "gained" },
        { label = "Quantity: largest", value = "quantity" },
    },
    action = {
        { label = "All activity" },
        { label = "Looted", value = "Looted" },
        { label = "Quest reward", value = "Quest" },
        { label = "Crafted", value = "Crafted" },
        { label = "Purchase", value = "Purchase" },
        { label = "Auction purchase", value = "Auction purchase" },
        { label = "Mail", value = "Mail" },
        { label = "Trade", value = "Trade" },
        { label = "Obtained (way unknown)", value = "Obtained (way unknown)" },
        { label = "Alt mail", value = "Alt mail" },
        { label = "Alt trade", value = "Alt trade" },
        { label = "Sale", value = "Sale" },
        { label = "Refund", value = "Refund" },
        { label = "Buyback", value = "Buyback" },
    },
}

-- The book and saved-preference validation share the same filter values.
function Validate.bookChoices()
    return copyValue(bookChoices)
end

---@class ALBookPreferences
---@field version integer
---@field scale number
---@field x number Horizontal offset in UIParent coordinates
---@field y number Vertical offset in UIParent coordinates
---@field guided boolean
---@field developerMode boolean
---@field filter table<string, string|number|boolean|nil>

---@param value any
---@return ALBookPreferences
local function bookPreferences(value)
    local result = { version = 1, scale = 1, x = 0, y = 0, guided = false, developerMode = false, filter = {} }
    if type(value) ~= "table" or value.version ~= 1 then
        return result
    end
    local function finite(number)
        return type(number) == "number" and number == number and math.abs(number) < math.huge
    end
    for _, field in ipairs({ "scale", "x", "y" }) do
        if finite(value[field]) then
            result[field] = field == "scale" and math.max(0.6, math.min(1.1, value[field])) or value[field]
        end
    end
    result.guided = value.guided == true
    result.developerMode = value.developerMode == true
    local filter = type(value.filter) == "table" and value.filter or {}
    local choices = {
        view = { "Collection", "Gallery", "Discoveries", "Journal", "Evidence" },
        category = { "Weapons", "Armour", "Recipes", "Materials", "Consumables", "Junk", "Other", "Unknown" },
        placeKind = { "zone", "dungeon", "place" },
        dateRange = { "Last 24 hours", "Last 7 days", "Last 30 days" },
    }
    for field, definitions in pairs(bookChoices) do
        choices[field] = {}
        for _, definition in ipairs(definitions) do
            if definition.value ~= nil then
                choices[field][#choices[field] + 1] = definition.value
            end
        end
    end
    for field, allowed in pairs(choices) do
        for _, choice in ipairs(allowed) do
            if filter[field] == choice then
                result.filter[field] = choice
            end
        end
    end
    for _, field in ipairs({ "search", "character", "realm", "place", "source" }) do
        if type(filter[field]) == "string" and #filter[field] <= 160 then
            result.filter[field] = filter[field]
        end
    end
    return result
end

function Validate.retentionOptions()
    return copyValue(retentionDefinitions)
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

-- Loot and correction proofs compare source identity, not display text.
local function sameSource(left, right)
    if not left or not right then
        return left == right
    end
    return left.kind == right.kind and left.guid == right.guid and left.name == right.name and left.realm == right.realm
end

local function canEnrichLootSource(current, proof)
    return not current
        or (current.guid == proof.guid and current.kind == proof.kind and (current.name == nil or proof.name ~= nil))
end

-- Shared with the store kernel and domain files.
Validate.CURRENT_SCHEMA = CURRENT_SCHEMA
Validate.areas = areas
Validate.gainMethods = gainMethods
Validate.retentionDefaults = retentionDefaults
Validate.retentionMaximums = retentionMaximums
Validate.displayDefaults = displayDefaults
Validate.vendorKinds = vendorKinds
Validate.isInteger = isInteger
Validate.validCheckID = validCheckID
Validate.validRetention = validRetention
Validate.gainRoot = gainRoot
Validate.chronological = chronological
Validate.trimHistory = trimHistory
Validate.isName = isName
Validate.areaKey = areaKey
Validate.copyArray = copyArray
Validate.copyValue = copyValue
Validate.validEvidence = validEvidence
Validate.validLootSource = validLootSource
Validate.validLootState = validLootState
Validate.compactObservations = compactObservations
Validate.copyRecord = copyRecord
Validate.validPlaceKind = validPlaceKind
Validate.validRecord = validRecord
Validate.recoverableRecord = recoverableRecord
Validate.validEnvironment = validEnvironment
Validate.validRewardContext = validRewardContext
Validate.validRewardSession = validRewardSession
Validate.validRewardState = validRewardState
Validate.preparationLive = preparationLive
Validate.validVendorState = validVendorState
Validate.validMailKind = validMailKind
Validate.validExchangeState = validExchangeState
Validate.validDisplayField = validDisplayField
Validate.validDisplay = validDisplay
Validate.bookPreferences = bookPreferences
Validate.validJournal = validJournal
Validate.sameSource = sameSource
Validate.canEnrichLootSource = canEnrichLootSource

addon.SchemaValidate = Validate
