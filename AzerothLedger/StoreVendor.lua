local _, addon = ...

-- Vendor purchases, sales, refunds and buybacks.

local V = addon.SchemaValidate
local vendorKinds, isInteger, isName, copyArray = V.vendorKinds, V.isInteger, V.isName, V.copyArray
local copyValue, copyRecord, validPlaceKind = V.copyValue, V.copyRecord, V.validPlaceKind
local Evidence = addon.StoreEvidence

local StoreVendor = {}

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
            level = action.level,
            place = action.place,
            placeKind = action.placeKind,
            linkedGainID = action.linkedGainID,
            linkedSaleID = action.linkedSaleID,
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

---@type AzerothLedgerSlice
StoreVendor.slice = { name = "vendor", validate = validVendorState, journal = "vendor" }

local function activeAction(action)
    return action.status == "pending" or action.status == "unresolved"
end

-- Returns the correlation engine a possessions check and evidence expiry use.
function StoreVendor.install(store, kernel, slice)
    local valid, readable, saveFields, gainRecord = kernel.valid, kernel.readable, kernel.save, kernel.gain
    local refundRecord = kernel.refund
    local recordHealthy, vendorHealthy, savedState = kernel.recordHealthy, slice.healthy, slice.state
    local areaQuantity, bagQuantity = kernel.areaQuantity, kernel.bagQuantity

    local function vendorState()
        if savedState() == nil then
            return { nextID = 1, actions = {}, journal = {} }
        end
        if vendorHealthy then
            return savedState()
        end
        return nil
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
        if record and not recordHealthy[action.key] then
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
                            records[action.key] = gainRecord(record, {
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
                            }, not valid[action.key])
                            vendorResult(state, action, "confirmed")
                        end
                    end
                elseif action.kind == "refund" and delta == -action.quantity and record then
                    local refunded = refundRecord(record, action.linkedGainID, action.quantity, "Vendor")
                    if refunded then
                        records[action.key] = refunded
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
        local state = copyValue(vendorState())
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
            valid[receipt.key] = copyRecord(records[receipt.key], true)
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

    local function healthyState()
        return savedState() and vendorHealthy and savedState() or nil
    end

    local function stale(at)
        local state = healthyState()
        return Evidence.staleEntries(state and state.actions, at, activeAction)
    end

    local function expire(at, reason, retain)
        local original = healthyState()
        if type(original) ~= "table" then
            return nil, false
        end
        local state = copyValue(original)
        local changed = Evidence.expireEntries(state.actions, at, reason, activeAction, function(entry, openedAt)
            retain("vendor", reason, openedAt, entry, entry)
        end)
        return state, changed
    end

    local function visit(emit, pause)
        local state = healthyState()
        if not readable or not state then
            return
        end
        for _, entry in ipairs(state.actions) do
            if activeAction(entry) then
                local reason = entry.status == "unresolved" and "stopped" or "active"
                emit("vendor:" .. entry.id, "vendor", reason, entry.at, entry, entry)
            end
            pause()
        end
    end

    -- Settles vendor actions against a complete check after a complete one.
    ---@param scan AzerothLedgerCheck
    local function check(scan)
        local snapshot, oldScope = scan.snapshot, scan.oldScope
        local handler, vendor = {}, nil
        function handler.finish()
            vendor = vendorState()
            if vendor and #vendor.actions == 0 then
                vendor = nil
            elseif vendor then
                vendor = copyValue(vendor)
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
                    scan.grouped,
                    scan.records
                )
            end
        end
        function handler.commit(fields)
            fields.vendor = vendor
        end
        return handler
    end

    return { engine = { stale = stale, expire = expire, visit = visit, check = check } }
end

addon.StoreVendor = StoreVendor
