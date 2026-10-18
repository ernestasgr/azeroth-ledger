-- One fake WoW client for offline specs: the addon's event frame, build info,
-- locale and slash command table. A spec sets the reads it drives (time, bags,
-- loot, quests...) as globals itself, then fires events through `event`.
local Client = {}

local function setGlobal(name, value)
    rawset(_G, name, value)
end

-- Installs the client globals and returns { frame, event, boot }. Calling it
-- again, as a relog does, replaces the frame so the reloaded addon gets its own.
---@param options? { build?: integer }
function Client.install(options)
    options = options or {}
    local frame = { registered = {}, scripts = {} }
    function frame:RegisterEvent(name)
        self.registered[name] = true
    end
    function frame:SetScript(name, handler)
        self.scripts[name] = handler
    end
    setGlobal("CreateFrame", function()
        return frame
    end)
    setGlobal("GetBuildInfo", function()
        return "1.60.1", options.build or 70009, "fixture", 16001
    end)
    setGlobal("GetLocale", function()
        return "enUS"
    end)
    setGlobal("SlashCmdList", {})

    local client = { frame = frame }

    -- Fires an event the addon registered; a replay of an unregistered event
    -- would prove nothing.
    function client.event(name, ...)
        assert(frame.registered[name], name .. " is not registered")
        frame.scripts.OnEvent(frame, name, ...)
    end

    -- Loads the addon into `addon` and logs in: the SavedVariables load, the
    -- player is known, and the first bag update settles the possessions.
    function client.boot(addon, load)
        load.addon("Main", addon)
        client.event("ADDON_LOADED", "AzerothLedger")
        client.event("PLAYER_LOGIN")
        client.event("BAG_UPDATE_DELAYED")
        return addon
    end

    return client
end

return Client
