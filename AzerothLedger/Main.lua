local addonName, addon = ...

local REVISION = "0.3.0"
local store = addon.Schema.open(AzerothLedgerDB, function(nextValue)
    AzerothLedgerDB = nextValue
end)
local client = addon.Client.inspect(_G)
local bankOpen = false

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

local function scan(area)
    local snapshot = addon.Scan.capture(_G, area, bankOpen)
    if snapshot then
        store:scan(snapshot)
        addon.Collection.refresh(store, snapshot.character, snapshot.realm)
    end
end

local function now()
    return type(GetServerTime) == "function" and GetServerTime() or nil
end

local function lootOpen()
    local character, realm = identity()
    local at = now()
    local slots = addon.Loot.open(_G)
    if not character or not realm or not at or not slots then
        return
    end
    local level = type(UnitLevel) == "function" and UnitLevel("player") or 0
    local place = type(GetRealZoneText) == "function" and GetRealZoneText() or "Unknown"
    if type(place) ~= "string" or place == "" then
        place = "Unknown"
    end
    store:lootOpen({
        character = character,
        realm = realm,
        at = at,
        level = level,
        place = place,
        slots = slots,
    })
end

local function lootMessage(message)
    local receipt = addon.Loot.receipt(_G, message)
    local at = now()
    local character, realm = identity()
    if receipt and at and character and realm and store:lootReceipt(receipt, at, character, realm) then
        addon.Collection.refresh(store, character, realm)
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
        scan("bags")
        scan("equipped")
        scan("bank")
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
    }) do
        local ok = pcall(client.frame.RegisterEvent, client.frame, event)
        if not ok then
            client.issues[#client.issues + 1] = event .. " (unusable)"
        end
    end
    local ok = pcall(client.frame.SetScript, client.frame, "OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then
            scan("bags")
            scan("equipped")
            scan("bank")
            printStatus()
        elseif event == "BAG_UPDATE_DELAYED" then
            scan("bags")
            if bankOpen then
                scan("bank")
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            scan("equipped")
        elseif event == "BANKFRAME_OPENED" then
            bankOpen = true
            scan("bank")
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
