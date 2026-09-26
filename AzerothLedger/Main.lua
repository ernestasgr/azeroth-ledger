local addonName, addon = ...

local REVISION = "0.3.0"
local store = addon.Schema.open(AzerothLedgerDB, function(nextValue)
    AzerothLedgerDB = nextValue
end)
local client = addon.Client.inspect(_G)
local bankOpen = false
local craftRecipeID
local questOfferSequence = 0

if #client.issues == 0 then
    store:setEnvironment({
        build = client.build,
        interface = client.interface,
        locale = client.locale,
        revision = REVISION,
    })
end

local function identity()
    if type(UnitName) ~= "function" or type(GetRealmName) ~= "function" then
        return nil, nil
    end
    return UnitName("player"), GetRealmName()
end

local function scan(area, checkedAt)
    local snapshot = addon.Scan.capture(_G, area, bankOpen)
    if snapshot then
        if checkedAt then
            snapshot.seenAt = checkedAt
        end
        store:scan(snapshot)
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
    if
        receipt
        and at
        and character
        and realm
        and store:lootReceipt(receipt, at, { character = character, realm = realm })
    then
        addon.Collection.refresh(store, character, realm)
    end
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
        "PLAYER_LOGIN",
        "BAG_UPDATE_DELAYED",
        "PLAYER_EQUIPMENT_CHANGED",
        "BANKFRAME_OPENED",
        "BANKFRAME_CLOSED",
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
        if event == "PLAYER_LOGIN" then
            scanAll()
            printStatus()
        elseif event == "BAG_UPDATE_DELAYED" then
            if bankOpen then
                scanAll()
            else
                scan("bags")
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            scanAll()
        elseif event == "BANKFRAME_OPENED" then
            bankOpen = true
            scanAll()
        elseif event == "BANKFRAME_CLOSED" then
            bankOpen = false
            scan("bank")
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
    printStatus()
end

addon.name = addonName
addon.store = store
AzerothLedger = addon
