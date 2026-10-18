local load = assert(loadfile("tests/support/addon.lua"))()
local addon = {}
local frame = { registered = {} }
local link = "|Hitem:4540::::::::|h[Tough Hunk of Bread]|h"
local minimapButton
local minimapButtonDatabase = { minimapPos = 135 }
local minimap = {
    GetFrameLevel = function()
        return 3
    end,
    GetWidth = function()
        return 140
    end,
    GetCenter = function()
        return 100, 100
    end,
    GetEffectiveScale = function()
        return 1
    end,
}
local function texture()
    return {
        SetSize = function() end,
        SetTexture = function() end,
        SetPoint = function() end,
        SetTexCoord = function() end,
    }
end
rawset(_G, "Minimap", minimap)
rawset(_G, "AzerothLedgerMinimapButtonDB", minimapButtonDatabase)
CreateFrame = function(frameType, _, parent)
    assert(frameType == "Button" and parent == minimap)
    minimapButton = { scripts = {} }
    minimapButton.SetSize = function() end
    minimapButton.SetFrameStrata = function() end
    minimapButton.SetFrameLevel = function() end
    minimapButton.RegisterForClicks = function() end
    minimapButton.RegisterForDrag = function() end
    minimapButton.SetHighlightTexture = function() end
    minimapButton.CreateTexture = function()
        return texture()
    end
    minimapButton.ClearAllPoints = function() end
    function minimapButton:SetPoint(...)
        self.position = { ... }
    end
    function minimapButton:SetScript(name, handler)
        self.scripts[name] = handler
    end
    return minimapButton
end
rawset(_G, "GetCursorPosition", function()
    return 150, 100
end)

function frame:RegisterEvent(event)
    self.registered[event] = true
end

function frame:SetScript(script, handler)
    if script == "OnEvent" then
        self.onEvent = handler
    end
end

load.addon("Schema", addon)

addon.Client = {
    inspect = function()
        return { frame = frame, issues = {}, build = "1.60.1.70009", interface = "16001", locale = "enUS" }
    end,
}
addon.Scan = {
    reader = function()
        return { capture = function() end }
    end,
}
SlashCmdList = {}

local key = assert(addon.Item.key(link, 4540))
local saved = {
    schema = 2,
    areas = {},
    records = {
        [key] = {
            key = key,
            itemID = 4540,
            firstSeen = 100,
            lastSeen = 101,
            firstSeenUnits = 0,
            totalGained = 1,
            firstGained = 101,
            lastGained = 101,
            links = { link },
            characters = { { name = "Ada", realm = "Realm", firstSeen = 100, lastSeen = 101, firstSeenUnits = 0 } },
            observations = { { character = "Ada", realm = "Realm", area = "bags", quantity = 1, seenAt = 101 } },
            gains = {
                {
                    id = "vendor:1:" .. key,
                    at = 101,
                    quantity = 1,
                    character = "Ada",
                    realm = "Realm",
                    level = 12,
                    place = "Elwynn Forest",
                    method = "Vendor",
                    source = { kind = "vendor", name = "Dermot Johns" },
                },
            },
        },
    },
}

AzerothLedgerDB = nil
-- Everything after Scan, so the Client and Scan stubs above stay in place. Collection loads
-- with the rest, so its stub replaces it afterwards; the addon looks Collection up per call.
load.addon("Main", addon, "Scan")
addon.Collection = {
    refresh = function() end,
    open = function() end,
}
assert(frame.registered.ADDON_LOADED)
assert(AzerothLedgerDB == nil, "addon must not initialize SavedVariables while Lua files load")
frame.onEvent(frame, "ADDON_LOADED", "AnotherAddon")
assert(addon.store == nil, "another addon's load event must not initialize the ledger")

AzerothLedgerDB = saved
frame.onEvent(frame, "ADDON_LOADED", "AzerothLedger")
local restored = assert(addon.store:find(key), "saved record must load when ADDON_LOADED fires")
assert(restored.totalGained == 1)
assert(restored.gains[1].source.name == "Dermot Johns")
assert(AzerothLedgerDB.records[key].gains[1].source.name == "Dermot Johns")
frame.onEvent(frame, "PLAYER_LOGIN")
assert(minimapButton, "PLAYER_LOGIN must create the Ledger minimap button")
assert(minimapButton.position, "minimap button must be positioned beside the minimap")
assert(minimapButtonDatabase.minimapPos == 135, "existing minimap position must be retained")

print("saved_variables_event_spec: passed")

local toggles, savedBook, slashOpens = 0, 0, 0
addon.Book = {
    toggle = function(_, receivedStore, character, realm)
        assert(receivedStore == addon.store and character == "Ada" and realm == "Realm")
        toggles = toggles + 1
    end,
    save = function()
        savedBook = savedBook + 1
    end,
}
rawset(_G, "UnitName", function()
    return "Ada"
end)
rawset(_G, "GetRealmName", function()
    return "Realm"
end)
addon.Book.open = function()
    slashOpens = slashOpens + 1
end
_G.AzerothLedgerToggle()
_G.AzerothLedgerToggle()
SlashCmdList.AZEROTHLEDGER("")
assert(toggles == 2 and slashOpens == 1)
minimapButton.scripts.OnClick(minimapButton, "LeftButtonUp")
assert(toggles == 3, "clicking the minimap button must toggle the Ledger")
minimapButton.scripts.OnDragStart(minimapButton)
assert(type(minimapButton.scripts.OnUpdate) == "function", "dragging must track the cursor")
minimapButton.scripts.OnDragStop(minimapButton)
assert(minimapButton.scripts.OnUpdate == nil, "dragging must stop cursor tracking")
assert(minimapButtonDatabase.minimapPos == 0, "dragging must save the new minimap position")
assert(_G.BINDING_NAME_AZEROTHLEDGER_TOGGLE == "Toggle Ledger")
assert(frame.registered.PLAYER_LOGOUT)
frame.onEvent(frame, "PLAYER_LOGOUT")
assert(savedBook == 1)
print("saved_variables_event_spec: native binding entry, slash command and reload save passed")
