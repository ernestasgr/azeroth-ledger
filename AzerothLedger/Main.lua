local addonName, addon = ...

local REVISION = "0.4.3"
local store
local client = addon.Client.inspect(_G)
local bankOpen = false
local merchantOpen = false
local merchantName
local merchantSlots
local merchantEquippedSlots
local buybackItems
local craftRecipeID
local questOfferSequence = 0

local function initializeStore()
    if store then
        return
    end
    store = addon.Schema.open(AzerothLedgerDB, function(nextValue)
        AzerothLedgerDB = nextValue
    end)
    addon.store = store
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

local function scan(area, checkedAt)
    local snapshot = addon.Scan.capture(_G, area, bankOpen)
    if snapshot then
        if checkedAt then
            snapshot.seenAt = checkedAt
        end
        store:scan(snapshot)
        if area == "bags" and merchantOpen then
            merchantSlots = addon.Vendor.slots(_G)
        elseif area == "equipped" and merchantOpen then
            merchantEquippedSlots = addon.Vendor.equippedSlots(_G)
        end
        addon.Collection.refresh(store, snapshot.character, snapshot.realm)
    end
end

local function scanAll()
    local checkedAt = type(GetServerTime) == "function" and GetServerTime() or nil
    scan("bags", checkedAt)
    scan("equipped", checkedAt)
    scan("bank", checkedAt)
end

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
    local place = type(GetRealZoneText) == "function" and GetRealZoneText() or "Unknown"
    if type(place) ~= "string" or place == "" then
        place = "Unknown"
    end
    return { character = character, realm = realm, at = at, level = level, place = place }
end

local function lootOpen()
    local context = playerContext()
    local slots = addon.Loot.open(_G)
    if not context or not slots then
        return
    end
    context.slots = slots
    store:lootOpen(context)
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

local function rewardReceipt(receipt)
    local context = playerContext()
    if not receipt or not context then
        return
    end
    if store:rewardReceipt(receipt, context.at, context) then
        addon.Collection.refresh(store, context.character, context.realm)
    end
end

local function questOffer()
    scan("bags")
    local offer = addon.Reward.offer(_G)
    local context = playerContext()
    if not offer or not context then
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
        #store:list()
    )
    if diagnostic.kind == "damaged" then
        print("Azeroth Ledger: damaged values:", diagnostic.damagedCount)
    elseif diagnostic.kind == "unsupported" then
        print("Azeroth Ledger: unsupported saved data is read-only and unchanged")
    end
    if #client.issues > 0 then
        print("Azeroth Ledger: missing or unusable required APIs:", table.concat(client.issues, ", "))
    end
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
    elseif message == "scan" then
        scanAll()
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
            print("Azeroth Ledger: /al status, /al scan, /al mark <token>")
        end
    end
end

if client.frame then
    for _, event in ipairs({
        "ADDON_LOADED",
        "PLAYER_LOGIN",
        "BAG_UPDATE_DELAYED",
        "PLAYER_EQUIPMENT_CHANGED",
        "BANKFRAME_OPENED",
        "BANKFRAME_CLOSED",
        "MERCHANT_SHOW",
        "MERCHANT_CLOSED",
        "MERCHANT_UPDATE",
        "LOOT_OPENED",
        "LOOT_CLOSED",
        "CHAT_MSG_LOOT",
        "QUEST_LOOT_RECEIVED",
        "QUEST_COMPLETE",
        "QUEST_TURNED_IN",
        "TRADE_SKILL_ITEM_CRAFTED_RESULT",
        "TRADE_SKILL_CRAFT_BEGIN",
        "UPDATE_TRADESKILL_CAST_STOPPED",
        "TRADE_SKILL_CLOSE",
    }) do
        local ok = pcall(client.frame.RegisterEvent, client.frame, event)
        if not ok then
            client.issues[#client.issues + 1] = event .. " (unusable)"
        end
    end
    local ok = pcall(client.frame.SetScript, client.frame, "OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" then
            if ... == addonName then
                initializeStore()
            end
            return
        end
        if not store then
            return
        end
        if event == "PLAYER_LOGIN" then
            scanAll()
            printStatus()
        elseif event == "BAG_UPDATE_DELAYED" then
            if bankOpen then
                scanAll()
            else
                scan("bags")
                if merchantOpen then
                    scan("equipped")
                end
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            scanAll()
        elseif event == "BANKFRAME_OPENED" then
            bankOpen = true
            scanAll()
        elseif event == "BANKFRAME_CLOSED" then
            bankOpen = false
            scan("bank")
        elseif event == "MERCHANT_SHOW" then
            merchantOpen = true
            merchantName = readMerchantName()
            scan("bags")
            scan("equipped")
            buybackItems = addon.Vendor.buybacks(_G)
        elseif event == "MERCHANT_CLOSED" then
            scan("bags")
            scan("equipped")
            merchantOpen = false
            merchantName = nil
            merchantSlots = nil
            merchantEquippedSlots = nil
            buybackItems = nil
        elseif event == "MERCHANT_UPDATE" then
            buybackItems = addon.Vendor.buybacks(_G)
        elseif event == "LOOT_OPENED" then
            lootOpen()
        elseif event == "LOOT_CLOSED" then
            local at = now()
            if at then
                store:lootClose(at)
            end
        elseif event == "CHAT_MSG_LOOT" then
            lootMessage(...)
        elseif event == "QUEST_LOOT_RECEIVED" then
            rewardReceipt(addon.Reward.quest(_G, ...))
        elseif event == "QUEST_COMPLETE" then
            questOffer()
        elseif event == "QUEST_TURNED_IN" then
            local questID = ...
            local context = playerContext()
            if context and store:questTurnedIn(questID, context.at, context) then
                scan("bags")
            end
        elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
            rewardReceipt(addon.Reward.craft(_G, ..., craftRecipeID))
        elseif event == "TRADE_SKILL_CRAFT_BEGIN" then
            craftRecipeID = ...
        elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" or event == "TRADE_SKILL_CLOSE" then
            craftRecipeID = nil
        end
    end)
    if not ok then
        client.issues[#client.issues + 1] = "CreateFrame events (unusable)"
    end
else
    print("Azeroth Ledger: event frame unavailable; saved data was not opened")
end

addon.name = addonName
AzerothLedger = addon
