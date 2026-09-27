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
    if type(realm) ~= "string" or realm == "" then
        return { name = name }
    end
    return { name = name, realm = realm }
end

function Exchange.inbox(api)
    if
        type(api.GetInboxNumItems) ~= "function"
        or type(api.GetInboxHeaderInfo) ~= "function"
        or type(api.GetInboxItemLink) ~= "function"
        or type(api.GetInboxItem) ~= "function"
    then
        return nil
    end
    local ok, count = pcall(api.GetInboxNumItems)
    if not ok or type(count) ~= "number" or count < 0 or count > 500 then
        return nil
    end
    local result = {}
    for index = 1, count do
        local headerOK, _, _, sender = pcall(api.GetInboxHeaderInfo, index)
        if headerOK then
            for attachment = 1, 12 do
                local linkOK, link = pcall(api.GetInboxItemLink, index, attachment)
                local infoOK, _, _, _, quantity = pcall(api.GetInboxItem, index, attachment)
                local intent = linkOK and infoOK and item(link, quantity, "mail", "in", Exchange.player(sender)) or nil
                if intent then
                    result[index .. ":" .. attachment] = intent
                end
            end
        end
    end
    return result
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
