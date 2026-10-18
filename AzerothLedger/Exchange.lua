local _, addon = ...

-- The mail and trade channel: items exchanged with other players.
--
-- Mail is taken from or sent through the mailbox. A take is proven only when
-- the client reports MAIL_SUCCESS and the attachment left the inbox.
-- Overlapping takes, returns, deletions, and money takes all report MAIL_SUCCESS
-- too, so any overlap marks pending takes unresolved instead of guessing.
--
-- In the trade window both sides are recorded once both players accept, and
-- confirmed only by the client's trade-complete message. Any item change after
-- acceptance cancels the prepared intents.
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

-- Copies an inbox intent and attaches the store's exchange id.
local function withID(intent, id)
    local captured = {}
    for key, value in pairs(intent) do
        captured[key] = value
    end
    captured.id = id
    return captured
end

-- Splits taken intents from those still waiting in the inbox.
local function remaining(selected, takenIDs)
    local rows = {}
    for _, intent in ipairs(selected) do
        if not takenIDs[intent.id] then
            rows[#rows + 1] = intent
        end
    end
    return rows
end

-- Mail taken from the inbox and sent through the mailbox.
local function mail(deps, write)
    local api, commands = deps.api, deps.commands
    local open = false
    local inbox, outbox
    -- take: { before = inbox, selected = intents, succeeded = boolean, progress? = true }
    local take
    local ambiguous = false
    -- Taken mail whose items have not yet appeared in bags.
    local awaiting
    local sending

    -- Same-realm senders carry no realm suffix.
    local function readInbox()
        local _, realm = addon.Runtime.identity(api)
        return Exchange.inbox(api, realm)
    end

    local function updateProgress()
        if awaiting and deps.mailProgress(awaiting) ~= "waiting" then
            awaiting = nil
        end
    end

    local function markUnresolved(ids)
        for _, id in ipairs(ids) do
            commands.exchangeMarkUnresolved(id)
        end
    end

    local function abandonTake()
        if take then
            local ids = {}
            for _, intent in ipairs(take.selected) do
                ids[#ids + 1] = intent.id
            end
            markUnresolved(ids)
        end
        take = nil
    end

    local function abandonAwaiting()
        if awaiting then
            local ids = {}
            for id in pairs(awaiting) do
                ids[#ids + 1] = id
            end
            markUnresolved(ids)
        end
        awaiting = nil
    end

    local function overlap()
        if take or awaiting then
            ambiguous = true
            abandonTake()
            abandonAwaiting()
        end
    end

    local function takeMail(index, attachment)
        if not open or not inbox then
            return
        end
        updateProgress()
        if take and take.progress and not awaiting then
            abandonTake()
        end
        overlap()
        local selected = {}
        for slot = attachment or 1, attachment or 12 do
            local intent = inbox[index .. ":" .. slot]
            local id = intent and write.intent(intent)
            if id then
                selected[#selected + 1] = withID(intent, id)
                if ambiguous then
                    markUnresolved({ id })
                end
            end
        end
        if #selected > 0 and not ambiguous then
            take = { before = inbox, selected = selected, succeeded = false }
        end
    end

    local function finishTake()
        if not take or not take.succeeded or ambiguous then
            return
        end
        local after = readInbox()
        local ids = Exchange.taken(take.before, after, take.selected)
        if not next(ids) then
            return
        end
        write.confirm("mail", "in", ids)
        inbox = after
        take.selected = remaining(take.selected, ids)
        take.before = after
        take.progress = true
        if #take.selected == 0 then
            take = nil
        end
        if deps.mailProgress(ids) == "waiting" then
            awaiting = awaiting or {}
            for id in pairs(ids) do
                awaiting[id] = true
            end
        end
    end

    local function send(recipient)
        if not open then
            return
        end
        overlap()
        local _, realm = addon.Runtime.identity(api)
        local peer = Exchange.player(recipient, nil, realm)
        local items = outbox and #outbox > 0 and outbox or Exchange.outbox(api)
        -- A second SendMail before MAIL_SEND_SUCCESS cannot be told apart.
        if sending then
            sending = nil
            return
        end
        sending = {}
        for _, intent in ipairs(items or {}) do
            intent.peerName = peer and peer.name or nil
            intent.peerRealm = peer and peer.realm or nil
            local id = write.intent(intent)
            if id then
                sending[id] = true
            end
        end
        outbox = nil
    end

    local hook = addon.Events.hook
    hook(api, deps.issues, "exchange", api, "TakeInboxItem", takeMail)
    hook(api, deps.issues, "exchange", api, "AutoLootMailItem", function(index)
        takeMail(index)
    end)
    -- These actions also emit MAIL_SUCCESS; never let their success complete a take.
    for _, method in ipairs({ "TakeInboxMoney", "ReturnInboxItem", "DeleteInboxItem" }) do
        if type(api[method]) == "function" then
            hook(api, deps.issues, "exchange", api, method, overlap)
        end
    end
    hook(api, deps.issues, "exchange", api, "SendMail", send)

    local channel = {}

    -- Runs once after each full inventory flush, when taken mail may have landed.
    function channel.flushed()
        updateProgress()
        if not take and not awaiting then
            ambiguous = false
        end
    end

    channel.events = {
        MAIL_SHOW = function()
            open = true
            take, ambiguous, sending = nil, false, nil
            deps.check("bags")
            updateProgress()
            inbox = readInbox()
            outbox = Exchange.outbox(api)
        end,
        MAIL_CLOSED = function()
            open = false
            inbox, outbox = nil, nil
            abandonTake()
            sending = nil
        end,
        MAIL_INBOX_UPDATE = function()
            finishTake()
            inbox = readInbox()
        end,
        MAIL_SEND_INFO_UPDATE = function()
            outbox = Exchange.outbox(api)
        end,
        MAIL_SEND_SUCCESS = function()
            if sending then
                write.confirm("mail", "out", sending)
                sending = nil
            end
        end,
        MAIL_SUCCESS = function()
            if take and not ambiguous then
                take.succeeded = true
                finishTake()
            end
        end,
        MAIL_FAILED = function()
            abandonTake()
            abandonAwaiting()
            ambiguous = false
            inbox = readInbox()
        end,
    }

    return channel
end

-- The trade partner, read when the window opens.
local function partner(api, localRealm)
    local read = rawget(api, "GetUnitName")
    if type(read) ~= "function" then
        return nil
    end
    local ok, name = pcall(read, "NPC", true)
    return ok and Exchange.player(name, nil, localRealm) or nil
end

local function isTradeComplete(api, messageID, message)
    local completed = rawget(api, "ERR_TRADE_COMPLETE")
    return type(completed) == "string" and (message == completed or messageID == completed)
end

-- Items exchanged in the trade window.
local function trade(deps, write)
    local api, commands = deps.api, deps.commands
    local open, prepared = false, false
    local preparedIDs, peer

    local function cancel()
        commands.exchangeCancel("trade")
    end

    local function prepare()
        if not open or prepared then
            return
        end
        preparedIDs = {}
        for _, direction in ipairs({ "in", "out" }) do
            for _, intent in ipairs(Exchange.trade(api, direction, peer) or {}) do
                local id = write.intent(intent)
                if id then
                    preparedIDs[id] = true
                end
            end
        end
        prepared = true
    end

    local function itemChanged()
        if prepared then
            cancel()
        end
        prepared, preparedIDs = false, nil
    end

    return {
        events = {
            TRADE_SHOW = function()
                open, prepared, preparedIDs = true, false, nil
                cancel()
                deps.check("bags")
                local _, realm = addon.Runtime.identity(api)
                peer = partner(api, realm)
            end,
            TRADE_PLAYER_ITEM_CHANGED = itemChanged,
            TRADE_TARGET_ITEM_CHANGED = itemChanged,
            TRADE_ACCEPT_UPDATE = function(playerAccepted, targetAccepted)
                if playerAccepted == 1 and targetAccepted == 1 then
                    prepare()
                end
            end,
            TRADE_CLOSED = function()
                open = false
            end,
            UI_INFO_MESSAGE = function(messageID, message)
                if prepared and isTradeComplete(api, messageID, message) then
                    write.confirm("trade", "in", preparedIDs)
                    write.confirm("trade", "out", preparedIDs)
                    prepared, preparedIDs = false, nil
                end
            end,
        },
    }
end

-- The store commands this channel writes through.
---@type ALCommandName[]
Exchange.commands = { "exchangeIntent", "exchangeConfirm", "exchangeMarkUnresolved", "exchangeCancel" }

---@class ALExchangeDependencies
---@field api table
---@field issues string[]
---@field commands ALCommands Built from `Exchange.commands`
---@field mailProgress fun(ids: table<string, true>): string
---@field check fun(area: string)

---@param deps ALExchangeDependencies
function Exchange.new(deps)
    local commands = deps.commands
    local write = {}

    function write.intent(intent)
        if intent then
            return (commands.exchangeIntent(intent))
        end
    end

    -- A confirmed exchange moved items in or out of bags.
    function write.confirm(channel, direction, ids)
        if commands.exchangeConfirm({ channel = channel, direction = direction, ids = ids }) then
            deps.check("bags")
        end
    end

    local mailbox = mail(deps, write)
    local events = {}
    for _, channel in ipairs({ mailbox, trade(deps, write) }) do
        for event, handler in pairs(channel.events) do
            assert(not events[event], "exchange event handled twice: " .. event)
            events[event] = handler
        end
    end
    return { events = events, flushed = mailbox.flushed }
end

addon.Exchange = Exchange
