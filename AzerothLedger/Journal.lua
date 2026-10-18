local _, addon = ...
local Journal = {}

local function actor(name, realm)
    return name and (name .. (realm and ("-" .. realm) or "")) or "Unknown character"
end

local gainSourceText, gainAction = addon.LastSeen.gainSourceText, addon.LastSeen.gainAction

-- How each channel names a move between your own characters.
local altActions = { mail = "Alt mail", trade = "Alt trade", guild = "Alt guild bank" }

local function location(row)
    return row.place and row.place ~= "" and row.place or "Unknown"
end

---@param store ALStore
---@param filter? AzerothLedgerCollectionFilter
---@param pause? fun()
---@return table[]
function Journal.query(store, filter, pause)
    filter = filter or {}
    local result = {}
    local purchases, sales = {}, {}
    local search = (filter.search or ""):lower()
    local function matchesActor(name, realm)
        return (not filter.character or filter.character == name) and (not filter.realm or filter.realm == realm)
    end
    local function matchesAction(action)
        return not filter.action or filter.action == action
    end
    for _, row in ipairs(store:journal(pause)) do
        local record = store:describe(row.key)
        row.link = record and record.links[#record.links] or nil
        row.name = row.link and row.link:match("%[([^%]]+)%]") or "Unknown item"
        local scopeMatches = false
        if row.category == "gain" then
            local first = row.contributions[1]
            row.quantity, row.refunded = 0, 0
            row.actors = actor(first.character, first.realm)
            row.action = gainAction(first)
            row.place, row.level = first.place, first.level
            row.details = {}
            local evidence, seen = {}, {}
            for _, gain in ipairs(row.contributions) do
                if matchesActor(gain.character, gain.realm) and matchesAction(gainAction(gain)) then
                    scopeMatches = true
                end
                row.quantity = row.quantity + gain.quantity
                row.refunded = row.refunded + (gain.refunded or 0)
                local label = gainAction(gain) .. ": " .. gainSourceText(gain)
                row.details[#row.details + 1] = {
                    actor = actor(gain.character, gain.realm),
                    at = gain.at,
                    quantity = gain.quantity,
                    place = location(gain),
                    level = gain.level,
                    method = gainAction(gain),
                    source = gainSourceText(gain),
                }
                if not seen[label] then
                    evidence[#evidence + 1], seen[label] = label, true
                end
            end
            table.sort(evidence)
            row.netQuantity = row.quantity - row.refunded
            row.refundSequences = {}
            purchases[row.key .. ":" .. row.id] = row
            if #evidence > 1 then
                row.action = "Gained"
            end
            row.evidence = "Matched item gain; " .. table.concat(evidence, "; ")
        elseif row.category == "transfer" then
            scopeMatches = (
                matchesActor(row.sender, row.senderRealm) or matchesActor(row.recipient, row.recipientRealm)
            ) and matchesAction(altActions[row.channel])
            row.actors = actor(row.sender, row.senderRealm) .. " → " .. actor(row.recipient, row.recipientRealm)
            row.action = altActions[row.channel]
            row.evidence = "Confirmed send and matching receipt; no external gain"
            row.sourceText = actor(row.sender, row.senderRealm)
        else
            row.actors = actor(row.character, row.realm)
            row.action = ({ sale = "Sale", refund = "Refund", buyback = "Buyback" })[row.kind]
            scopeMatches = matchesActor(row.character, row.realm) and matchesAction(row.action)
            row.evidence = "Matched vendor action; " .. (row.vendorName or "Unknown vendor")
            row.sourceText = row.vendorName or "Unknown vendor"
            if row.kind == "sale" then
                sales[row.key .. ":" .. row.id] = row
            end
        end
        row.placeText = location(row)
        local text = row.name .. " " .. row.actors .. " " .. row.action .. " " .. row.evidence
        if
            scopeMatches
            and (not filter.historyKey or row.key == filter.historyKey)
            and (not filter.dateFrom or row.at >= filter.dateFrom)
            and (not filter.dateTo or row.at < filter.dateTo)
            and text:lower():find(search, 1, true)
        then
            result[#result + 1] = row
        end
        if pause then
            pause()
        end
    end
    for _, row in ipairs(result) do
        local purchase = row.linkedAcquisitionID and purchases[row.key .. ":" .. row.linkedAcquisitionID]
        if purchase then
            row.purchaseSequence = purchase.sequence
            purchase.refundSequences[#purchase.refundSequences + 1] = row.sequence
        end
        local sale = row.linkedSaleID and sales[row.key .. ":" .. row.linkedSaleID]
        row.saleSequence = sale and sale.sequence or nil
        if pause then
            pause()
        end
    end
    return result
end

addon.Journal = Journal
