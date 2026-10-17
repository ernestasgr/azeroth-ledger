local _, addon = ...

local Exchange = {}

local function item(link, quantity, channel, direction, peer)
    local itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
    local key = itemID and addon.Item.key(link, itemID)
    if not key or type(quantity) ~= "number" or quantity < 1 or quantity ~= math.floor(quantity) then
        return nil
    end
    return {
        channel = channel,
        direction = direction,
        key = key,
        itemID = itemID,
        link = link,
        quantity = quantity,
        peerName = peer and peer.name or nil,
        peerRealm = peer and peer.realm or nil,
    }
end

function Exchange.player(name, realm, localRealm)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local bare, qualified = name:match("^([^-]+)%-(.+)$")
    if bare then
        name, realm = bare, qualified
    elseif type(realm) ~= "string" or realm == "" then
        realm = localRealm
    end
    -- Forever shows a surname after the character name, which never contains a space.
    name = name:match("^(%S+)") or name
    if type(realm) ~= "string" or realm == "" then
        return { name = name }
    end
    return { name = name, realm = realm }
end

function Exchange.inbox(api, localRealm)
    if
        type(api.GetInboxNumItems) ~= "function"
        or type(api.GetInboxHeaderInfo) ~= "function"
        or type(api.GetInboxItemLink) ~= "function"
        or type(api.GetInboxItem) ~= "function"
    then
        return nil
    end
    local ok, count = pcall(api.GetInboxNumItems)
    if not ok or type(count) ~= "number" or count < 0 or count > 500 or count ~= math.floor(count) then
        return nil
    end
    local result = {}
    for index = 1, count do
        local headerOK, _, stationery, sender, subject, _, _, _, itemCount, _, returned, _, canReply =
            pcall(api.GetInboxHeaderInfo, index)
        if headerOK then
            local readableCount = 0
            local invoice
            if type(api.GetInboxInvoiceInfo) == "function" then
                local invoiceOK, value = pcall(api.GetInboxInvoiceInfo, index)
                invoice = invoiceOK and value or nil
            end
            local peer = Exchange.player(sender, nil, localRealm)
            for attachment = 1, 12 do
                local linkOK, link = pcall(api.GetInboxItemLink, index, attachment)
                local infoOK, name, itemID, _, quantity = pcall(api.GetInboxItem, index, attachment)
                local intent = linkOK and infoOK and item(link, quantity, "mail", "in", peer) or nil
                if intent then
                    readableCount = readableCount + 1
                    intent.mailKind = returned and "return"
                        or invoice == "buyer" and "auction-purchase"
                        or (invoice ~= nil or canReply ~= true) and "unresolved"
                        or nil
                    -- Inbox indexes move when a message disappears. Compare total units
                    -- with the same header and variant instead of trusting a later index.
                    intent.mailIdentity = table.concat({
                        tostring(sender),
                        tostring(subject),
                        tostring(stationery),
                        tostring(returned),
                        tostring(canReply),
                        tostring(invoice),
                        intent.key,
                    }, "\031")
                    result[index .. ":" .. attachment] = intent
                elseif not linkOK or not infoOK or link ~= nil or quantity ~= nil or name ~= nil or itemID ~= nil then
                    return nil -- unreadable attachments cannot prove disappearance
                end
            end
            if type(itemCount) == "number" and itemCount ~= readableCount then
                return nil
            end
        else
            return nil
        end
    end
    return result
end

-- A generic success event alone cannot identify which attachments were taken.
-- Return only the unique subset of whole attachments proven absent from the inbox.
function Exchange.taken(before, after, selected)
    if not before or not after then
        return {}
    end
    local totals, groups, proven = {}, {}, {}
    for _, intent in pairs(before) do
        totals[intent.mailIdentity] = (totals[intent.mailIdentity] or 0) + intent.quantity
    end
    for _, intent in pairs(after) do
        totals[intent.mailIdentity] = (totals[intent.mailIdentity] or 0) - intent.quantity
    end
    for _, intent in ipairs(selected) do
        local group = groups[intent.mailIdentity] or {}
        groups[intent.mailIdentity] = group
        group[#group + 1] = intent
    end
    for identity, group in pairs(groups) do
        local removed = totals[identity] or 0
        local matches, unique = 0, {}
        local function subsets(index, quantity, chosen)
            if quantity > removed or matches > 1 then
                return
            end
            if index > #group then
                if quantity == removed then
                    matches = matches + 1
                    unique = {}
                    for id in pairs(chosen) do
                        unique[id] = true
                    end
                end
                return
            end
            subsets(index + 1, quantity, chosen)
            chosen[group[index].id] = true
            subsets(index + 1, quantity + group[index].quantity, chosen)
            chosen[group[index].id] = nil
        end
        if removed > 0 then
            subsets(1, 0, {})
            if matches == 1 then
                for id in pairs(unique) do
                    proven[id] = true
                end
            end
        end
    end
    return proven
end

function Exchange.outbox(api)
    if type(api.GetSendMailItem) ~= "function" then
        return nil
    end
    local result = {}
    for attachment = 1, 12 do
        local infoOK, _, itemID, _, quantity = pcall(api.GetSendMailItem, attachment)
        local link
        if type(api.GetSendMailItemLink) == "function" then
            local ok, value = pcall(api.GetSendMailItemLink, attachment)
            link = ok and value or nil
        elseif type(api.GetItemInfo) == "function" and type(itemID) == "number" then
            local ok, _, value = pcall(api.GetItemInfo, itemID)
            link = ok and value or nil
        end
        local intent = infoOK and item(link, quantity, "mail", "out") or nil
        if intent then
            result[#result + 1] = intent
        end
    end
    return result
end

function Exchange.trade(api, direction, peer)
    local linkAPI = direction == "in" and api.GetTradeTargetItemLink or api.GetTradePlayerItemLink
    local infoAPI = direction == "in" and api.GetTradeTargetItemInfo or api.GetTradePlayerItemInfo
    if type(linkAPI) ~= "function" or type(infoAPI) ~= "function" then
        return nil
    end
    local byKey = {}
    for slot = 1, 6 do
        local linkOK, link = pcall(linkAPI, slot)
        local infoOK, _, _, quantity = pcall(infoAPI, slot)
        local intent = linkOK and infoOK and item(link, quantity, "trade", direction, peer) or nil
        if intent then
            local existing = byKey[intent.key]
            if existing then
                existing.quantity = existing.quantity + intent.quantity
            else
                byKey[intent.key] = intent
            end
        end
    end
    local result = {}
    for _, intent in pairs(byKey) do
        result[#result + 1] = intent
    end
    return result
end

addon.Exchange = Exchange
