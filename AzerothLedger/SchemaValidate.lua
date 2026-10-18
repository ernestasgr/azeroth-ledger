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
---@field firstSeenLater? boolean This character's first units arrived after its earlier complete check.

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
---@field command fun(self: ALStore, name: ALCommandName, payload: any, at: integer, actor: ALActor): any
---@field setCharacter fun(self: ALStore, character: string, realm: string): boolean
---@field vendorActivity fun(self: AzerothLedgerStore): AzerothLedgerVendorActivity[]
---@field vendorUnresolved fun(self: AzerothLedgerStore): AzerothLedgerVendorEvidence[]
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

---@alias ALLootSlots AzerothLedgerLootSlot[]

-- The writes store:command accepts. Each is declared by the domain that owns it.
---@alias ALCommandName
---| 'lootOpen' # {slots}; the actor carries level and place
---| 'lootSourceProof' # {slots} read after the window opened
---| 'lootReceipt' # {key, quantity}
---| 'lootClose' # nil
---| 'questPrepared' # quest id
---| 'questOffered' # quest id
---| 'questAccepted' # quest id; the actor may carry questName
---| 'questTurnedIn' # quest id
---| 'rewardReceipt' # AzerothLedgerRewardReceipt
---| 'vendorAction' # AzerothLedgerVendorIntent; the actor may carry vendorName
---| 'vendorReceipt' # {key, quantity}
---| 'exchangeIntent' # AzerothLedgerExchangeIntent
---| 'exchangeConfirm' # {channel, direction, ids?}
---| 'exchangeCancel' # channel
---| 'exchangeMarkUnresolved' # exchange id

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

local function validLootSource(source)
    return source == nil
        or (
            type(source) == "table"
            and (source.kind == "mob" or source.kind == "container")
            and isName(source.guid)
            and (source.name == nil or isName(source.name))
        )
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

-- The level and place a gain records for the acting character.
local function validGainActor(actor)
    return isInteger(actor.level) and type(actor.place) == "string" and validPlaceKind(actor.placeKind)
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

local vendorKinds = { purchase = true, sale = true, refund = true, buyback = true }
local Validate = {}

function Validate.displayOptions()
    return copyValue(displayOptions)
end

function Validate.colorOptions()
    return copyValue(colorOptions)
end

local bookChoices = {
    ownership = addon.LastSeen.ownershipChoices(),
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
    method = addon.LastSeen.methodChoices(),
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
Validate.validLootSource = validLootSource
Validate.compactObservations = compactObservations
Validate.copyRecord = copyRecord
Validate.validPlaceKind = validPlaceKind
Validate.validGainActor = validGainActor
Validate.validRewardContext = validRewardContext
Validate.validDisplayField = validDisplayField
Validate.validDisplay = validDisplay
Validate.bookPreferences = bookPreferences
Validate.sameSource = sameSource
Validate.canEnrichLootSource = canEnrichLootSource

addon.SchemaValidate = Validate
