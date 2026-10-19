local _, addon = ...

-- Owns the item changes the Collection asks a player to review: what each
-- unconfirmed change was, why it is unconfirmed, and what may still confirm it.
local CollectionEvidence = {}

local evidenceActions = {
    loot = "Loot pickup",
    lootOpen = "Loot pickup",
    lootReceipt = "Loot pickup",
    rewards = "Quest reward",
    rewardReceipt = "Quest reward",
    quest = "Quest reward",
    questPrepared = "Quest reward",
    vendor = "Vendor action",
    vendorAction = "Vendor action",
    vendorReceipt = "Vendor action",
    exchange = "Mail or trade",
    exchangeIntent = "Mail or trade",
    identity = "Bag, bank, or gear check",
}
local evidenceReasons = {
    expired = "The addon could not confirm this item gain in time.",
    reload = "You logged out or reloaded before the addon could confirm this item gain.",
    overflow = "Too many item changes happened at once for the addon to confirm this one.",
    unreadable = "The game did not provide a readable item name.",
    unmatched = "The item change did not match an action the addon saw.",
    stopped = "The addon could not tell which action caused this item change.",
}

local sourceUncertainty = "The addon could not identify one clear loot source. "
    .. "It also needs to see the item gain."

---@param entry ALEvidenceViewEntry
local function evidenceReason(entry)
    local reason = evidenceReasons[entry.reason]
    if entry.kind == "loot" and not entry.sourceKnown then
        return reason and (reason .. " " .. sourceUncertainty) or sourceUncertainty
    end
    if reason then
        return reason
    elseif entry.kind == "vendor" then
        return "The vendor action and matching item change could not both be confirmed."
    elseif entry.kind == "exchange" then
        return "The mail or trade, item change, or other character could not be confirmed."
    end
    return "The addon could not confirm both the action and the item change."
end

---@param entry ALEvidenceViewEntry
local function evidenceNextStep(entry)
    if entry.reason == "expired" or entry.reason == "reload" or entry.reason == "overflow" then
        return "This old item change can no longer be confirmed. Future checks will not add it to Total gained."
    elseif entry.kind == "identity" then
        local area = entry.area == "bank" and "the bank" or entry.area == "equipped" and "equipped gear" or "bags"
        return "Wait for the item name to load, then check "
            .. area
            .. " again. The item may be added as Seen, but that will not count as a gain."
    elseif entry.reason == "unmatched" then
        return "The addon did not see a matching action. This receipt alone does not confirm a gain."
    elseif entry.reason == "stopped" then
        return "The addon will not retry this action. Future checks will not confirm it."
    elseif entry.reason ~= "active" then
        return "This saved entry does not show whether the addon can still confirm the item change."
    end
    return "The addon can still match this while its check is open. "
        .. "Checking bags, bank, or gear may help, but might not confirm a gain."
end

-- Public read-only projection: saved evidence and live candidates share one
-- presentation, with stable IDs independent of Collection item identity.
function CollectionEvidence.query(store, filter, pause)
    pause = pause or function() end
    local candidates, actors, seenActors, representedPreparations = {}, {}, {}, {}
    local summary = store:visitEvidence(function(entry)
        candidates[#candidates + 1] = entry
        if entry.kind == "rewards" and entry.preparationID then
            local key = entry.character .. "\031" .. entry.realm .. "\031" .. entry.preparationID
            representedPreparations[key] = true
        end
        local actorKey = entry.character .. "\031" .. entry.realm
        if not seenActors[actorKey] then
            seenActors[actorKey] = true
            actors[#actors + 1] = { character = entry.character, realm = entry.realm }
        end
    end, pause)
    local rows, positions, total = {}, {}, 0
    local search = string.lower(filter.search or "")
    for _, entry in ipairs(candidates) do
        local preparationKey = entry.preparationID
            and (entry.character .. "\031" .. entry.realm .. "\031" .. entry.preparationID)
        if entry.kind ~= "quest" or not representedPreparations[preparationKey] then
            total = total + 1
            local record = entry.key and store:find(entry.key)
            local link = entry.link or (record and record.links[1])
            local itemID = entry.itemID
                or (record and record.itemID)
                or (entry.key and tonumber(entry.key:match("^(%d+):")))
            local readableLink = link and addon.Item.key(link, itemID)
            local name = readableLink and link:match("%[([^%]]+)%]")
                or (itemID and ("Item " .. itemID .. (not readableLink and " • unresolved variant" or "")))
                or entry.key
                or "Unresolved item identity"
            local action = evidenceActions[entry.kind] or "Item evidence"
            if (entry.kind == "vendor" or entry.kind == "vendorAction") and entry.action then
                action = "Vendor " .. entry.action
            elseif entry.kind == "exchange" or entry.kind == "exchangeIntent" then
                action = ({ mail = "Mail", trade = "Trade", guild = "Guild bank" })[entry.channel] or "Mail or trade"
                if entry.direction == "in" then
                    action = action .. " received"
                elseif entry.direction == "out" then
                    action = action .. " sent"
                end
            elseif entry.method then
                action = ({ Crafted = "Craft", Obtained = "Item received" })[entry.method] or "Quest reward"
            end
            if
                (not filter.character or entry.character == filter.character)
                and (not filter.realm or entry.realm == filter.realm)
                and string
                    .lower(name .. " " .. (link or "") .. " " .. (entry.key or "") .. " " .. (entry.itemID or ""))
                    :find(search, 1, true)
            then
                rows[#rows + 1] = {
                    id = entry.id,
                    key = entry.key,
                    link = readableLink and link or nil,
                    name = name,
                    character = entry.character,
                    realm = entry.realm,
                    at = entry.at,
                    action = action,
                    reason = evidenceReason(entry),
                    nextStep = evidenceNextStep(entry),
                    quantity = entry.quantity,
                    location = entry.location,
                    status = entry.reason == "expired" and "Timed out"
                        or entry.reason == "reload" and "Login interrupted"
                        or entry.reason == "overflow" and "Too many changes"
                        or entry.kind == "identity" and "Item name unavailable"
                        or entry.reason == "stopped" and "Could not match"
                        or entry.reason == "unmatched" and "No matching action"
                        or entry.reason == "active" and "Still checking"
                        or "Needs review",
                }
            end
        end
        pause()
    end
    addon.Work.sort(rows, function(left, right)
        return left.at > right.at or (left.at == right.at and left.id < right.id)
    end, pause)
    addon.Work.sort(actors, function(left, right)
        return left.realm < right.realm or (left.realm == right.realm and left.character < right.character)
    end, pause)
    for index, row in ipairs(rows) do
        positions[row.id] = index
        pause()
    end
    return {
        rows = rows,
        positions = positions,
        actors = actors,
        total = total,
        discarded = summary.discarded,
        firstDiscarded = summary.firstDiscarded,
        lastDiscarded = summary.lastDiscarded,
        categories = {},
        places = {},
        loading = 0,
        matchedCount = #rows,
        discoveryCount = store:count(),
    }
end

addon.CollectionEvidence = CollectionEvidence
