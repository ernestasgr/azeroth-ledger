local _, addon = ...

-- Status lines for /al status and the opt-in trace of stored scans and state.
-- Status is assembled as data so callers decide where it is shown.
local Diagnostics = {}

-- One print call's arguments; n keeps trailing nil values printable.
local function line(...)
    return { n = select("#", ...), ... }
end

---@param store ALStore
---@param client AzerothLedgerClientInspection
---@param revision string
---@param formatDate fun(format: string, at: integer): string
---@return {n: integer}[] lines Each line is the argument list for one print call.
function Diagnostics.status(store, client, revision, formatDate)
    local diagnostic = store:diagnostic()
    local lines = {
        line("Azeroth Ledger:", diagnostic.kind),
        line(
            "Azeroth Ledger build/interface/locale/revision:",
            client.build,
            client.interface,
            client.locale,
            revision
        ),
        line(
            "Azeroth Ledger schema/marker/records:",
            diagnostic.schema or "<unsupported>",
            store:marker() or "<absent>",
            store:count()
        ),
    }
    if diagnostic.kind == "damaged" then
        lines[#lines + 1] = line("Azeroth Ledger: damaged values:", diagnostic.damagedCount)
    elseif diagnostic.kind == "unsupported" then
        lines[#lines + 1] = line("Azeroth Ledger: unsupported saved data is read-only and unchanged")
    end
    if #client.issues > 0 then
        lines[#lines + 1] =
            line("Azeroth Ledger: missing or unusable required APIs:", table.concat(client.issues, ", "))
    end
    local evidence = store:evidenceSummary()
    lines[#lines + 1] = line("Azeroth Ledger: unresolved evidence:", #evidence.unresolved)
    if evidence.discarded > 0 then
        lines[#lines + 1] = line(
            "Azeroth Ledger WARNING: unresolved evidence discarded:",
            evidence.discarded,
            formatDate("%Y-%m-%d %H:%M", evidence.firstDiscarded),
            formatDate("%Y-%m-%d %H:%M", evidence.lastDiscarded)
        )
    end
    return lines
end

---@param store ALStore
---@param snapshot AzerothLedgerSnapshot
---@param accepted boolean
function Diagnostics.traceStored(store, snapshot, accepted)
    local Trace = addon.Trace
    local state = store:area(snapshot.character, snapshot.realm, snapshot.area)
    Trace.log(
        "stored",
        "area=" .. snapshot.area,
        "accepted=" .. tostring(accepted),
        "complete=" .. tostring(snapshot.complete),
        "items=" .. #snapshot.items,
        "saved-complete=" .. tostring(state and state.complete),
        "saved-at=" .. tostring(state and state.seenAt)
    )
    if snapshot.area ~= "equipped" then
        return
    end
    for _, item in ipairs(snapshot.items) do
        local key = addon.Item.key(item.link, item.itemID)
        local record = key and store:find(key)
        Trace.log(
            "stored-item",
            "slot=" .. tostring(item.location),
            "key=" .. tostring(key),
            "record=" .. tostring(record ~= nil),
            item.link
        )
    end
end

local function traceSlots(api, store)
    local Trace = addon.Trace
    local cachedCheck = api.C_Item and api.C_Item.IsItemDataCachedByID
    for slot = 1, 19 do
        local id = type(api.GetInventoryItemID) == "function" and api.GetInventoryItemID("player", slot) or nil
        local link = type(api.GetInventoryItemLink) == "function" and api.GetInventoryItemLink("player", slot) or nil
        if id or link then
            local cached = id and type(cachedCheck) == "function" and cachedCheck(id)
            local key = link and addon.Item.key(link, tonumber(link:match("item:(%d+)")) or -1)
            Trace.log(
                "state-slot",
                "slot=" .. slot,
                "id=" .. tostring(id),
                "cached=" .. tostring(cached),
                "key=" .. tostring(key),
                "record=" .. tostring(key and store:find(key) ~= nil),
                tostring(link)
            )
        end
    end
end

local function traceAreas(store, character, realm)
    for _, area in ipairs({ "bags", "equipped", "bank" }) do
        local state = character and store:area(character, realm, area)
        addon.Trace.log(
            "state-area",
            "area=" .. area,
            "complete=" .. tostring(state and state.complete),
            "seenAt=" .. tostring(state and state.seenAt),
            "lastCompleteAt=" .. tostring(state and state.lastCompleteAt)
        )
    end
end

local function traceFilter(store)
    local parts = {}
    for field, value in pairs(store:book().filter or {}) do
        parts[#parts + 1] = field .. "=" .. tostring(value)
    end
    table.sort(parts)
    addon.Trace.log("state-filter", table.concat(parts, " "))
end

local function observedAreas(record, character, realm)
    local parts = {}
    for _, observation in ipairs(record.observations or {}) do
        if observation.character == character and observation.realm == realm then
            parts[#parts + 1] = tostring(observation.area) .. ":" .. tostring(observation.quantity)
        end
    end
    return table.concat(parts, ",")
end

local function traceRecords(api, store, character, realm)
    for _, record in ipairs(store:list()) do
        for _, seen in ipairs(record.characters) do
            if seen.name == character and seen.realm == realm then
                local metadata = addon.Client.itemMetadata(api, record)
                addon.Trace.log(
                    "state-record",
                    "key=" .. record.key,
                    "first=" .. tostring(seen.firstSeenUnits),
                    "gained=" .. tostring(record.totalGained),
                    "category=" .. tostring(metadata.category),
                    "seen=" .. observedAreas(record, character, realm),
                    tostring(record.links[1])
                )
            end
        end
    end
end

-- Writes the current character's gear, checks, filter, and records to the trace.
---@param api table
---@param store ALStore
---@param client AzerothLedgerClientInspection
---@param revision string
function Diagnostics.traceState(api, store, client, revision)
    local character, realm = addon.Runtime.identity(api)
    addon.Trace.log(
        "state",
        "character=" .. tostring(character),
        "realm=" .. tostring(realm),
        "level=" .. tostring(type(api.UnitLevel) == "function" and api.UnitLevel("player") or nil),
        "revision=" .. revision,
        "client=" .. client.build,
        "records=" .. store:count()
    )
    traceSlots(api, store)
    traceAreas(store, character, realm)
    traceFilter(store)
    traceRecords(api, store, character, realm)
end

addon.Diagnostics = Diagnostics
