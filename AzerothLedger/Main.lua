local addonName, addon = ...

local REVISION = "0.1.0"
local store = addon.Schema.open(AzerothLedgerDB, function(nextValue)
    AzerothLedgerDB = nextValue
end)

local client = addon.Client.inspect(_G)

if #client.issues == 0 then
    store:setEnvironment({
        build = client.build,
        interface = client.interface,
        locale = client.locale,
        revision = REVISION,
    })
end

-- Prints the current schema, client, environment, and capability diagnostics.
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
    local environment = store:environment()
    if environment then
        print(
            "Azeroth Ledger recorded environment:",
            environment.build,
            environment.interface,
            environment.locale,
            environment.revision
        )
    end

    if diagnostic.kind == "damaged" then
        print(
            "Azeroth Ledger: damaged current-schema values:",
            diagnostic.damagedCount,
            "(valid records remain readable)"
        )
    elseif diagnostic.kind == "unsupported" then
        print("Azeroth Ledger: unsupported saved data is read-only and unchanged")
    end

    if #client.issues > 0 then
        print("Azeroth Ledger: missing or unusable required APIs:", table.concat(client.issues, ", "))
    end
end

SLASH_AZEROTHLEDGER1 = "/al"
-- Handles status, marker, and small manual observation commands.
SlashCmdList.AZEROTHLEDGER = function(message)
    message = (message or ""):match("^%s*(.-)%s*$")
    if message == "" or message == "status" then
        printStatus()
        return
    end

    if #client.issues > 0 then
        print("Azeroth Ledger: writes disabled while required APIs are missing")
        return
    end

    local marker = message:match("^mark%s+(.+)$")
    if marker then
        print(
            store:setMarker(marker) and "Azeroth Ledger: marker saved"
                or "Azeroth Ledger: marker rejected; use 1-64 characters and current schema"
        )
        return
    end

    local itemID = message:match("^seen%s+(%d+)$")
    if itemID then
        local ok, timestamp = pcall(GetServerTime)
        if ok and store:recordSeen(tonumber(itemID), timestamp) then
            print("Azeroth Ledger: test item recorded:", itemID)
        else
            print("Azeroth Ledger: item could not be recorded")
        end
        return
    end

    if message == "list" then
        for _, record in ipairs(store:list()) do
            print("Azeroth Ledger item:", record.itemID, "first seen:", record.firstSeen)
        end
        print("Azeroth Ledger records:", #store:list())
        return
    end

    print("Azeroth Ledger: /al status, /al mark <token>, /al seen <itemID>, /al list")
end

if client.frame then
    local registered = pcall(client.frame.RegisterEvent, client.frame, "PLAYER_LOGIN")
    local scripted = pcall(client.frame.SetScript, client.frame, "OnEvent", printStatus)
    if not registered or not scripted then
        client.issues[#client.issues + 1] = "CreateFrame events (unusable)"
        printStatus()
    end
else
    printStatus()
end

addon.name = addonName
addon.store = store
