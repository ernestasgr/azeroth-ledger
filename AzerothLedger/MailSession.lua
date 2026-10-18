local _, addon = ...
addon.Sessions = addon.Sessions or {}

-- Mail taken from or sent through the mailbox. A take is proven only when the
-- client reports MAIL_SUCCESS and the attachment left the inbox. Overlapping
-- takes, returns, deletions, and money takes all report MAIL_SUCCESS too, so
-- any overlap marks pending takes unresolved instead of guessing.
local MailSession = {}

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

---@param runtime ALRuntime
function MailSession.new(runtime)
    local api = runtime.api
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
        local _, realm = runtime.identity()
        return addon.Exchange.inbox(api, realm)
    end

    local function updateProgress()
        if awaiting and runtime.store():mailProgress(awaiting) ~= "waiting" then
            awaiting = nil
        end
    end

    local function markUnresolved(ids)
        for _, id in ipairs(ids) do
            runtime.command("exchangeMarkUnresolved", id)
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
            local id = intent and runtime.exchangeIntent(intent)
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
        local ids = addon.Exchange.taken(take.before, after, take.selected)
        if not next(ids) then
            return
        end
        runtime.exchangeConfirm("mail", "in", ids)
        inbox = after
        take.selected = remaining(take.selected, ids)
        take.before = after
        take.progress = true
        if #take.selected == 0 then
            take = nil
        end
        if runtime.store():mailProgress(ids) == "waiting" then
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
        local _, realm = runtime.identity()
        local peer = addon.Exchange.player(recipient, nil, realm)
        local items = outbox and #outbox > 0 and outbox or addon.Exchange.outbox(api)
        -- A second SendMail before MAIL_SEND_SUCCESS cannot be told apart.
        if sending then
            sending = nil
            return
        end
        sending = {}
        for _, intent in ipairs(items or {}) do
            intent.peerName = peer and peer.name or nil
            intent.peerRealm = peer and peer.realm or nil
            local id = runtime.exchangeIntent(intent)
            if id then
                sending[id] = true
            end
        end
        outbox = nil
    end

    local hook = addon.Events.hook
    hook(api, runtime.issues, "exchange", api, "TakeInboxItem", takeMail)
    hook(api, runtime.issues, "exchange", api, "AutoLootMailItem", function(index)
        takeMail(index)
    end)
    -- These actions also emit MAIL_SUCCESS; never let their success complete a take.
    for _, method in ipairs({ "TakeInboxMoney", "ReturnInboxItem", "DeleteInboxItem" }) do
        if type(api[method]) == "function" then
            hook(api, runtime.issues, "exchange", api, method, overlap)
        end
    end
    hook(api, runtime.issues, "exchange", api, "SendMail", send)

    local session = {}

    -- Runs once after each full inventory flush, when taken mail may have landed.
    function session.flushed()
        updateProgress()
        if not take and not awaiting then
            ambiguous = false
        end
    end

    session.events = {
        MAIL_SHOW = function()
            open = true
            take, ambiguous, sending = nil, false, nil
            runtime.inventory:check("bags")
            updateProgress()
            inbox = readInbox()
            outbox = addon.Exchange.outbox(api)
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
            outbox = addon.Exchange.outbox(api)
        end,
        MAIL_SEND_SUCCESS = function()
            if sending then
                runtime.exchangeConfirm("mail", "out", sending)
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

    return session
end

addon.Sessions.Mail = MailSession
