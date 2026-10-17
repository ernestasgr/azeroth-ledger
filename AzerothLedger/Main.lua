local addonName, addon = ...

local REVISION = "0.11.6"
local store
local client = addon.Client.inspect(_G)
local merchantOpen = false
local lootCaptured = false
local merchantName
local merchantSlots
local merchantEquippedSlots
local buybackItems
local craftRecipeID
local questOfferSequence = 0
local inboxItems
local outboxItems
local mailOpen = false
local tradeOpen = false
local tradePrepared = false
local tradePreparedIDs
local tradePeer
local mailTake
local mailTakeAmbiguous = false
local mailAwaitingIDs
local mailSendIDs
local inventory
local Trace = addon.Trace

local function updateMailProgress()
    if mailAwaitingIDs and store:mailProgress(mailAwaitingIDs) ~= "waiting" then
        mailAwaitingIDs = nil
    end
end

local function initializeStore()
    if store then
        return
    end
    store = addon.Schema.open(AzerothLedgerDB, function(nextValue)
        AzerothLedgerDB = nextValue
    end)
    addon.store = store
    if addon.Presentation then
        local ok, registered, failure = pcall(addon.Presentation.register, _G, store)
        if not ok or not registered then
            client.issues[#client.issues + 1] = tostring(ok and failure or registered)
        end
    end
    if addon.Settings then
        local ok, registered, failure = pcall(addon.Settings.register, _G, store)
        if not ok or not registered then
            client.issues[#client.issues + 1] = tostring(ok and failure or registered)
        end
    end
    if #client.issues == 0 then
        store:setEnvironment({
            build = client.build,
            interface = client.interface,
            locale = client.locale,
            revision = REVISION,
        })
    end
end

local function identity()
    if type(UnitName) ~= "function" or type(GetRealmName) ~= "function" then
        return nil, nil
    end
    return UnitName("player"), GetRealmName()
end

local function readMerchantName()
    if type(UnitName) ~= "function" then
        return nil
    end
    local ok, name = pcall(UnitName, "npc")
    return ok and type(name) == "string" and name ~= "" and name or nil
end

local function traceStored(snapshot, accepted)
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
    if snapshot.area == "equipped" then
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
end

inventory = addon.Inventory.new(_G, function(snapshot)
    local accepted = store:scan(snapshot)
    if Trace.enabled then
        traceStored(snapshot, accepted)
    end
    if snapshot.area == "bags" and merchantOpen then
        merchantSlots = addon.Vendor.slots(_G)
    elseif snapshot.area == "equipped" and merchantOpen then
        merchantEquippedSlots = addon.Vendor.equippedSlots(_G)
    end
    addon.Collection.refresh(store, snapshot.character, snapshot.realm)
end, function()
    updateMailProgress()
    if not mailTake and not mailAwaitingIDs then
        mailTakeAmbiguous = false
    end
end)

local function now()
    return type(GetServerTime) == "function" and GetServerTime() or nil
end

local function playerContext()
    local character, realm = identity()
    local at = now()
    if not character or not realm or not at then
        return nil
    end
    local level = type(UnitLevel) == "function" and UnitLevel("player") or 0
    local place, placeKind = addon.Client.place(_G)
    return { character = character, realm = realm, at = at, level = level, place = place, placeKind = placeKind }
end

local function lootOpen()
    local context = playerContext()
    local slots = addon.Loot.open(_G)
    if not context or not slots then
        return
    end
    context.slots = slots
    -- Fast loot can finish at READY. OPENED must keep that pre-gain baseline.
    if lootCaptured then
        if store:lootSourceProof(slots, context.at, context) then
            addon.Collection.refresh(store, context.character, context.realm)
        end
    elseif #slots > 0 then
        lootCaptured = store:lootOpen(context)
    end
end

local function lootMessage(message)
    local receipt = addon.Loot.receipt(_G, message)
    local at = now()
    local character, realm = identity()
    if receipt and at and character and realm then
        local actor = { character = character, realm = realm }
        local accepted
        if merchantOpen then
            accepted = store:vendorReceipt(receipt, at, actor)
        else
            accepted = store:lootReceipt(receipt, at, actor)
        end
        if accepted then
            addon.Collection.refresh(store, character, realm)
        end
    end
end

local function vendorAction(action)
    local context = playerContext()
    if context then
        context.vendorName = merchantName or readMerchantName()
    end
    if merchantOpen and action and context and store:vendorAction(action, context.at, context) then
        addon.Collection.refresh(store, context.character, context.realm)
    end
end

local function containerAction(kind, bag, slot, isEquipped)
    if isEquipped then
        local cached = merchantEquippedSlots and merchantEquippedSlots[slot]
        if cached then
            merchantEquippedSlots[slot] = nil
        end
        return cached or addon.Vendor.equipped(_G, slot)
    end
    local slotKey = tostring(bag) .. ":" .. tostring(slot)
    local cached = merchantSlots and merchantSlots[slotKey]
    if cached then
        merchantSlots[slotKey] = nil
        cached.kind = kind
        return cached
    end
    return addon.Vendor.container(_G, kind, bag, slot, isEquipped)
end

local function hookVendor(target, method, callback)
    if type(hooksecurefunc) ~= "function" or type(target) ~= "table" or type(target[method]) ~= "function" then
        client.issues[#client.issues + 1] = method .. " (vendor hook unavailable)"
        return
    end
    local ok = pcall(hooksecurefunc, target, method, callback)
    if not ok then
        client.issues[#client.issues + 1] = method .. " (vendor hook unusable)"
    end
end

hookVendor(_G, "BuyMerchantItem", function(index, count)
    vendorAction(addon.Vendor.purchase(_G, index, count))
end)
hookVendor(_G, "PickupMerchantItem", function(index)
    vendorAction(addon.Vendor.purchase(_G, index))
end)
hookVendor(_G, "BuybackItem", function(index)
    local cached = buybackItems and buybackItems[index]
    if cached then
        buybackItems[index] = nil
    end
    vendorAction(cached or addon.Vendor.buyback(_G, index))
end)
if type(C_Container) == "table" then
    hookVendor(C_Container, "UseContainerItem", function(bag, slot)
        if merchantOpen then
            vendorAction(containerAction("sale", bag, slot))
        end
    end)
    hookVendor(C_Container, "ContainerRefundItemPurchase", function(bag, slot, isEquipped)
        vendorAction(containerAction("refund", bag, slot, isEquipped))
    end)
end

local function exchangeIntent(intent)
    local context = playerContext()
    if context and intent then
        return store:exchangeIntent(intent, context.at, context)
    end
end

local function exchangeConfirm(channel, direction, ids)
    local context = playerContext()
    if context and store:exchangeConfirm(channel, direction, context.at, context, ids) then
        inventory:check("bags")
    end
end

local function hookExchange(method, callback)
    if type(hooksecurefunc) ~= "function" or type(_G[method]) ~= "function" then
        client.issues[#client.issues + 1] = method .. " (exchange hook unavailable)"
        return
    end
    local ok = pcall(hooksecurefunc, method, callback)
    if not ok then
        client.issues[#client.issues + 1] = method .. " (exchange hook unusable)"
    end
end

local function abandonMailTake()
    local context = playerContext()
    if context and mailTake then
        for _, intent in ipairs(mailTake.selected) do
            store:exchangeMarkUnresolved(intent.id, context)
        end
    end
    mailTake = nil
end

local function abandonAwaitingMail()
    local context = playerContext()
    if context and mailAwaitingIDs then
        for id in pairs(mailAwaitingIDs) do
            store:exchangeMarkUnresolved(id, context)
        end
    end
    mailAwaitingIDs = nil
end

local function takeMail(index, attachment)
    if mailOpen and inboxItems then
        updateMailProgress()
        if mailTake and mailTake.progress and not mailAwaitingIDs then
            abandonMailTake()
        end
        if mailTake or mailAwaitingIDs then
            mailTakeAmbiguous = true
            abandonMailTake()
            abandonAwaitingMail()
        end
        local selected = {}
        for slot = attachment or 1, attachment or 12 do
            local intent = inboxItems[index .. ":" .. slot]
            local id = intent and exchangeIntent(intent)
            if id then
                local captured = {}
                for key, value in pairs(intent) do
                    captured[key] = value
                end
                captured.id = id
                selected[#selected + 1] = captured
                if mailTakeAmbiguous then
                    store:exchangeMarkUnresolved(id, playerContext())
                end
            end
        end
        if #selected > 0 and not mailTakeAmbiguous then
            mailTake = { before = inboxItems, selected = selected, succeeded = false }
        end
    end
end

local function finishMailTake()
    if not mailTake or not mailTake.succeeded or mailTakeAmbiguous then
        return
    end
    local after = addon.Exchange.inbox(_G)
    local ids = addon.Exchange.taken(mailTake.before, after, mailTake.selected)
    if next(ids) then
        exchangeConfirm("mail", "in", ids)
        inboxItems = after
        local remaining = {}
        for _, intent in ipairs(mailTake.selected) do
            if not ids[intent.id] then
                remaining[#remaining + 1] = intent
            end
        end
        mailTake.selected = remaining
        mailTake.before = after
        mailTake.progress = true
        if #remaining == 0 then
            mailTake = nil
        end
        if store:mailProgress(ids) == "waiting" then
            mailAwaitingIDs = mailAwaitingIDs or {}
            for id in pairs(ids) do
                mailAwaitingIDs[id] = true
            end
        end
    end
end

hookExchange("TakeInboxItem", takeMail)
hookExchange("AutoLootMailItem", function(index)
    takeMail(index)
end)
-- These actions also emit MAIL_SUCCESS; never let their success complete a take.
for _, method in ipairs({ "TakeInboxMoney", "ReturnInboxItem", "DeleteInboxItem" }) do
    if type(_G[method]) == "function" then
        hookExchange(method, function()
            if mailTake or mailAwaitingIDs then
                mailTakeAmbiguous = true
                abandonMailTake()
                abandonAwaitingMail()
            end
        end)
    end
end
hookExchange("SendMail", function(recipient)
    if not mailOpen then
        return
    end
    if mailTake or mailAwaitingIDs then
        mailTakeAmbiguous = true
        abandonMailTake()
        abandonAwaitingMail()
    end
    local _, realm = identity()
    local peer = addon.Exchange.player(recipient, nil, realm)
    local items = outboxItems and #outboxItems > 0 and outboxItems or addon.Exchange.outbox(_G)
    if mailSendIDs then
        mailSendIDs = nil
        return
    end
    mailSendIDs = {}
    for _, intent in ipairs(items or {}) do
        intent.peerName = peer and peer.name or nil
        intent.peerRealm = peer and peer.realm or nil
        local id = exchangeIntent(intent)
        if id then
            mailSendIDs[id] = true
        end
    end
    outboxItems = nil
end)

local function prepareTrade()
    if not tradeOpen or tradePrepared then
        return
    end
    tradePreparedIDs = {}
    for _, direction in ipairs({ "in", "out" }) do
        for _, intent in ipairs(addon.Exchange.trade(_G, direction, tradePeer) or {}) do
            local id = exchangeIntent(intent)
            if id then
                tradePreparedIDs[id] = true
            end
        end
    end
    tradePrepared = true
end

local function rewardReceipt(receipt)
    local context = playerContext()
    if not receipt or not context then
        return
    end
    if store:rewardReceipt(receipt, context.at, context) then
        if receipt.method == "Quest" then
            inventory:check("possessions")
        end
        addon.Collection.refresh(store, context.character, context.realm)
    end
end

local function questOffer()
    inventory:check("possessions")
    local offer = addon.Reward.offer(_G)
    local context = playerContext()
    if not context then
        return
    end
    local questID = offer and offer.questID or nil
    if not questID and type(_G.GetQuestID) == "function" then
        local ok, id = pcall(_G.GetQuestID)
        if ok then
            questID = id
        end
    end
    if questID then
        store:questPrepared(questID, context.at, context)
    end
    if not offer then
        return
    end
    questOfferSequence = questOfferSequence + 1
    local choiceGroup =
        table.concat({ context.character, context.realm, offer.questID, context.at, questOfferSequence }, ":")
    local changed = false
    for _, receipt in ipairs(offer.choices) do
        receipt.preview = true
        receipt.choiceGroup = choiceGroup
        changed = store:rewardReceipt(receipt, context.at, context) or changed
    end
    for _, receipt in ipairs(offer.fixed) do
        receipt.preview = true
        changed = store:rewardReceipt(receipt, context.at, context) or changed
    end
    if changed then
        addon.Collection.refresh(store, context.character, context.realm)
    end
end

local function printStatus()
    local diagnostic = store:diagnostic()
    print("Azeroth Ledger:", diagnostic.kind)
    print("Azeroth Ledger build/interface/locale/revision:", client.build, client.interface, client.locale, REVISION)
    print(
        "Azeroth Ledger schema/marker/records:",
        diagnostic.schema or "<unsupported>",
        store:marker() or "<absent>",
        store:count()
    )
    if diagnostic.kind == "damaged" then
        print("Azeroth Ledger: damaged values:", diagnostic.damagedCount)
    elseif diagnostic.kind == "unsupported" then
        print("Azeroth Ledger: unsupported saved data is read-only and unchanged")
    end
    if #client.issues > 0 then
        print("Azeroth Ledger: missing or unusable required APIs:", table.concat(client.issues, ", "))
    end
    local evidence = store:evidenceSummary()
    print("Azeroth Ledger: unresolved evidence:", #evidence.unresolved)
    if evidence.discarded > 0 then
        print(
            "Azeroth Ledger WARNING: unresolved evidence discarded:",
            evidence.discarded,
            date("%Y-%m-%d %H:%M", evidence.firstDiscarded),
            date("%Y-%m-%d %H:%M", evidence.lastDiscarded)
        )
    end
end

local function traceState()
    local character, realm = identity()
    Trace.log(
        "state",
        "character=" .. tostring(character),
        "realm=" .. tostring(realm),
        "level=" .. tostring(type(UnitLevel) == "function" and UnitLevel("player") or nil),
        "revision=" .. REVISION,
        "client=" .. client.build,
        "records=" .. store:count()
    )
    local cachedCheck = C_Item and C_Item.IsItemDataCachedByID
    for slot = 1, 19 do
        local id = type(GetInventoryItemID) == "function" and GetInventoryItemID("player", slot) or nil
        local link = type(GetInventoryItemLink) == "function" and GetInventoryItemLink("player", slot) or nil
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
    for _, area in ipairs({ "bags", "equipped", "bank" }) do
        local state = character and store:area(character, realm, area)
        Trace.log(
            "state-area",
            "area=" .. area,
            "complete=" .. tostring(state and state.complete),
            "seenAt=" .. tostring(state and state.seenAt),
            "lastCompleteAt=" .. tostring(state and state.lastCompleteAt)
        )
    end
    local filter = store:book().filter or {}
    local filterParts = {}
    for field, value in pairs(filter) do
        filterParts[#filterParts + 1] = field .. "=" .. tostring(value)
    end
    table.sort(filterParts)
    Trace.log("state-filter", table.concat(filterParts, " "))
    for _, record in ipairs(store:list()) do
        for _, seen in ipairs(record.characters) do
            if seen.name == character and seen.realm == realm then
                local metadata = addon.Client.itemMetadata(_G, record)
                local areaParts = {}
                for _, observation in ipairs(record.observations or {}) do
                    if observation.character == character and observation.realm == realm then
                        areaParts[#areaParts + 1] = tostring(observation.area) .. ":" .. tostring(observation.quantity)
                    end
                end
                Trace.log(
                    "state-record",
                    "key=" .. record.key,
                    "first=" .. tostring(seen.firstSeenUnits),
                    "gained=" .. tostring(record.totalGained),
                    "category=" .. tostring(metadata.category),
                    "seen=" .. table.concat(areaParts, ","),
                    tostring(record.links[1])
                )
            end
        end
    end
end

_G.BINDING_HEADER_AZEROTHLEDGER = "Azeroth Ledger"
_G.BINDING_NAME_AZEROTHLEDGER_TOGGLE = "Toggle Ledger"
_G.AzerothLedgerToggle = function()
    initializeStore()
    local character, realm = identity()
    if character and realm then
        addon.Book.toggle(_G, store, character, realm)
    end
end

local function createMinimapButton()
    local minimap = rawget(_G, "Minimap")
    local createFrame = rawget(_G, "CreateFrame")
    if not minimap or type(createFrame) ~= "function" then
        return
    end

    local database = rawget(_G, "AzerothLedgerMinimapButtonDB")
    if type(database) ~= "table" then
        database = {}
        rawset(_G, "AzerothLedgerMinimapButtonDB", database)
    end

    local position = rawget(database, "minimapPos")
    if type(position) ~= "number" or position ~= position or position == math.huge or position == -math.huge then
        position = 315
    end
    position = position % 360

    local button = createFrame("Button", nil, minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(minimap:GetFrameLevel() + 1)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -5)

    local function updatePosition()
        button:ClearAllPoints()
        local width = minimap:GetWidth()
        local radius = type(width) == "number" and width > 0 and width / 2 + 10 or 80
        local radians = math.rad(position)
        button:SetPoint("CENTER", minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
    end

    local function updatePositionFromCursor()
        local getCursorPosition = rawget(_G, "GetCursorPosition")
        if type(getCursorPosition) ~= "function" then
            return
        end
        local cursorX, cursorY = getCursorPosition()
        local centerX, centerY = minimap:GetCenter()
        local scale = minimap:GetEffectiveScale()
        if
            type(cursorX) ~= "number"
            or type(cursorY) ~= "number"
            or not centerX
            or not centerY
            or type(scale) ~= "number"
            or scale <= 0
        then
            return
        end
        position = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)) % 360
        updatePosition()
    end

    button:SetScript("OnClick", function()
        _G.AzerothLedgerToggle()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", updatePositionFromCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        updatePositionFromCursor()
        self:SetScript("OnUpdate", nil)
        database.minimapPos = position
    end)

    local tooltip = rawget(_G, "GameTooltip")
    if tooltip then
        button:SetScript("OnEnter", function(self)
            local centerX = self:GetCenter()
            local parent = rawget(_G, "UIParent")
            local anchor = parent and centerX and centerX > parent:GetWidth() / 2 and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
            tooltip:SetOwner(self, anchor)
            tooltip:AddLine("Azeroth Ledger")
            tooltip:AddLine("Left-click to open or close", 1, 1, 1)
            tooltip:AddLine("Drag to move this button", 0.8, 0.8, 0.8)
            tooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            tooltip:Hide()
        end)
    end

    database.minimapPos = position
    updatePosition()
end

SLASH_AZEROTHLEDGER1 = "/al"
SlashCmdList.AZEROTHLEDGER = function(message)
    message = (message or ""):match("^%s*(.-)%s*$")
    if message == "" or message == "collection" or message:match("^collection%s+") then
        local character, realm = identity()
        if character and realm then
            local filterRealm = message:match("^collection%s+realm%s+(.+)$")
            local filterCharacter
            if not filterRealm then
                filterCharacter, filterRealm = message:match("^collection%s+(%S+)%s+(.+)$")
            end
            addon.Collection.open(_G, store, character, realm, filterCharacter, filterRealm)
        end
    elseif message == "status" then
        printStatus()
    elseif message == "profile" then
        print("Azeroth Ledger: session timings in milliseconds; frame budget 2 ms; open target 250 ms")
        for label, timing in pairs(addon.Work.timings) do
            print(label, "samples", timing.frames, "total", timing.total, "maximum", timing.maximum)
        end
    elseif message == "trace" or message:match("^trace%s") then
        local action = message:match("^trace%s+(%S+)") or "status"
        if action == "on" then
            Trace.setEnabled(true)
            Trace.log("trace-on", "revision=" .. REVISION, "client=" .. client.build, "locale=" .. client.locale)
            print("Azeroth Ledger: trace on; it stays on for every character until /al trace off")
        elseif action == "off" then
            Trace.log("trace-off")
            Trace.setEnabled(false)
            print("Azeroth Ledger: trace off")
        elseif action == "clear" then
            Trace.clear()
            print("Azeroth Ledger: trace cleared")
        elseif action == "dump" then
            if not Trace.enabled then
                print("Azeroth Ledger: trace is off; /al trace on first")
            else
                traceState()
                print("Azeroth Ledger: state written to the trace;", Trace.count(), "lines. /reload to save it to disk")
            end
        else
            print("Azeroth Ledger: trace", Trace.enabled and "on" or "off", "with", Trace.count(), "lines")
            print("Azeroth Ledger: /al trace on, /al trace off, /al trace dump, /al trace clear")
        end
    elseif message == "scan" then
        inventory:check("all")
        print("Azeroth Ledger: readable storage checked")
    else
        local marker = message:match("^mark%s+(.+)$")
        if marker then
            print(
                store:setMarker(marker) and "Azeroth Ledger: marker saved"
                    or "Azeroth Ledger: marker rejected; use 1-64 characters and current schema"
            )
        else
            print("Azeroth Ledger: /al collection [character realm], /al collection realm <realm>")
            print("Azeroth Ledger: /al status, /al scan, /al mark <token>, /al trace")
        end
    end
end

if client.frame then
    for _, event in ipairs({
        "ADDON_LOADED",
        "PLAYER_LOGIN",
        "PLAYER_ENTERING_WORLD",
        "BAG_UPDATE_DELAYED",
        "BAG_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_INVENTORY_CHANGED",
        "BANKFRAME_OPENED",
        "BANKFRAME_CLOSED",
        "MERCHANT_SHOW",
        "MERCHANT_CLOSED",
        "MERCHANT_UPDATE",
        "LOOT_READY",
        "LOOT_OPENED",
        "LOOT_CLOSED",
        "LOOT_SLOT_CHANGED",
        "CHAT_MSG_LOOT",
        "GET_ITEM_INFO_RECEIVED",
        "ITEM_DATA_LOAD_RESULT",
        "QUEST_LOOT_RECEIVED",
        "QUEST_COMPLETE",
        "QUEST_TURNED_IN",
        "TRADE_SKILL_ITEM_CRAFTED_RESULT",
        "TRADE_SKILL_CRAFT_BEGIN",
        "UPDATE_TRADESKILL_CAST_STOPPED",
        "TRADE_SKILL_CLOSE",
        "MAIL_SHOW",
        "MAIL_CLOSED",
        "MAIL_INBOX_UPDATE",
        "MAIL_SEND_INFO_UPDATE",
        "MAIL_SEND_SUCCESS",
        "MAIL_FAILED",
        "MAIL_SUCCESS",
        "TRADE_SHOW",
        "TRADE_ACCEPT_UPDATE",
        "TRADE_PLAYER_ITEM_CHANGED",
        "TRADE_TARGET_ITEM_CHANGED",
        "TRADE_CLOSED",
        "UI_INFO_MESSAGE",
        "PLAYER_LOGOUT",
    }) do
        local ok = pcall(client.frame.RegisterEvent, client.frame, event)
        if not ok then
            client.issues[#client.issues + 1] = event .. " (unusable)"
        end
    end
    local function handleEvent(_, event, ...)
        if event == "PLAYER_LOGOUT" then
            addon.Book.save()
        elseif event == "ADDON_LOADED" then
            if ... == addonName then
                Trace.attach(AzerothLedgerTraceDB, function(value)
                    AzerothLedgerTraceDB = value
                end)
                Trace.log(
                    "addon-loaded",
                    "revision=" .. REVISION,
                    "client=" .. client.build,
                    "features=pending-gear,trace"
                )
                initializeStore()
            end
            return
        end
        if not store then
            return
        end
        if Trace.enabled then
            Trace.log("event", event, ...)
        end
        local eventAt = now()
        if eventAt then
            store:expireEvidence(eventAt)
        end
        if event == "PLAYER_LOGIN" then
            createMinimapButton()
            inventory:check("all")
            printStatus()
        elseif event == "PLAYER_ENTERING_WORLD" then
            local isInitialLogin = ...
            if isInitialLogin then
                inventory:check("possessions")
                inventory:event(event)
            end
        elseif
            event == "BAG_UPDATE"
            or event == "BAG_UPDATE_DELAYED"
            or event == "PLAYER_EQUIPMENT_CHANGED"
            or event == "UNIT_INVENTORY_CHANGED"
            or event == "BANKFRAME_OPENED"
            or event == "BANKFRAME_CLOSED"
        then
            inventory:event(event, ...)
        elseif event == "MERCHANT_SHOW" then
            merchantOpen = true
            merchantName = readMerchantName()
            inventory:check("bags")
            inventory:check("equipped")
            buybackItems = addon.Vendor.buybacks(_G)
        elseif event == "MERCHANT_CLOSED" then
            inventory:check("bags")
            inventory:check("equipped")
            merchantOpen = false
            merchantName = nil
            merchantSlots = nil
            merchantEquippedSlots = nil
            buybackItems = nil
        elseif event == "MERCHANT_UPDATE" then
            buybackItems = addon.Vendor.buybacks(_G)
        elseif event == "MAIL_SHOW" then
            mailOpen = true
            mailTake = nil
            mailTakeAmbiguous = false
            mailSendIDs = nil
            inventory:check("bags")
            updateMailProgress()
            inboxItems = addon.Exchange.inbox(_G)
            outboxItems = addon.Exchange.outbox(_G)
        elseif event == "MAIL_CLOSED" then
            mailOpen = false
            inboxItems = nil
            outboxItems = nil
            abandonMailTake()
            mailSendIDs = nil
        elseif event == "MAIL_INBOX_UPDATE" then
            finishMailTake()
            inboxItems = addon.Exchange.inbox(_G)
        elseif event == "MAIL_SEND_INFO_UPDATE" then
            outboxItems = addon.Exchange.outbox(_G)
        elseif event == "MAIL_SEND_SUCCESS" then
            if mailSendIDs then
                exchangeConfirm("mail", "out", mailSendIDs)
                mailSendIDs = nil
            end
        elseif event == "MAIL_SUCCESS" then
            if mailTake and not mailTakeAmbiguous then
                mailTake.succeeded = true
                finishMailTake()
            end
        elseif event == "MAIL_FAILED" then
            abandonMailTake()
            abandonAwaitingMail()
            mailTakeAmbiguous = false
            inboxItems = addon.Exchange.inbox(_G)
        elseif event == "TRADE_SHOW" then
            tradeOpen = true
            tradePrepared = false
            tradePreparedIDs = nil
            local character, realm = identity()
            if character and realm then
                store:exchangeCancel("trade", { character = character, realm = realm })
            end
            inventory:check("bags")
            local getUnitName = rawget(_G, "GetUnitName")
            local ok, name = false, nil
            if type(getUnitName) == "function" then
                ok, name = pcall(getUnitName, "NPC", true)
            end
            tradePeer = ok and addon.Exchange.player(name) or nil
        elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" then
            local character, realm = identity()
            if tradePrepared and character and realm then
                store:exchangeCancel("trade", { character = character, realm = realm })
            end
            tradePrepared = false
            tradePreparedIDs = nil
        elseif event == "TRADE_ACCEPT_UPDATE" then
            local playerAccepted, targetAccepted = ...
            if playerAccepted == 1 and targetAccepted == 1 then
                prepareTrade()
            end
        elseif event == "TRADE_CLOSED" then
            tradeOpen = false
        elseif event == "UI_INFO_MESSAGE" then
            local messageID, message = ...
            local completed = rawget(_G, "ERR_TRADE_COMPLETE")
            if tradePrepared and type(completed) == "string" and (message == completed or messageID == completed) then
                exchangeConfirm("trade", "in", tradePreparedIDs)
                exchangeConfirm("trade", "out", tradePreparedIDs)
                tradePrepared = false
                tradePreparedIDs = nil
            end
        elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
            lootOpen()
        elseif event == "LOOT_SLOT_CHANGED" then
            local context = playerContext()
            local slots = addon.Loot.open(_G)
            if context and slots and store:lootSourceProof(slots, context.at, context) then
                addon.Collection.refresh(store, context.character, context.realm)
            end
        elseif event == "LOOT_CLOSED" then
            lootCaptured = false
            local at = now()
            if at then
                store:lootClose(at)
            end
        elseif event == "CHAT_MSG_LOOT" then
            lootMessage(...)
        elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
            local _, success = ...
            inventory:event(event, success)
        elseif event == "QUEST_LOOT_RECEIVED" then
            rewardReceipt(addon.Reward.quest(_G, ...))
        elseif event == "QUEST_COMPLETE" then
            questOffer()
        elseif event == "QUEST_TURNED_IN" then
            local questID = ...
            local context = playerContext()
            if context and store:questTurnedIn(questID, context.at, context) then
                inventory:check("possessions")
            end
        elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
            rewardReceipt(addon.Reward.craft(_G, ..., craftRecipeID))
        elseif event == "TRADE_SKILL_CRAFT_BEGIN" then
            craftRecipeID = ...
        elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" or event == "TRADE_SKILL_CLOSE" then
            craftRecipeID = nil
        end
    end
    local ok = pcall(client.frame.SetScript, client.frame, "OnEvent", function(frame, event, ...)
        local arguments = { n = select("#", ...), ... }
        addon.Work.measure(_G, "Event " .. event, function()
            handleEvent(frame, event, unpack(arguments, 1, arguments.n))
        end)
    end)
    if not ok then
        client.issues[#client.issues + 1] = "CreateFrame events (unusable)"
    end
    local elapsed = 0
    local timerOK = pcall(client.frame.SetScript, client.frame, "OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 1 then
            elapsed = 0
            local at = now()
            if store and at then
                store:expireEvidence(at)
            end
        end
    end)
    if not timerOK then
        client.issues[#client.issues + 1] = "CreateFrame timer (unusable)"
    end
else
    print("Azeroth Ledger: event frame unavailable; saved data was not opened")
end

addon.name = addonName
AzerothLedger = addon
