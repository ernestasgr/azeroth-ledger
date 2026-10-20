local _, addon = ...

-- The guild bank channel: items you deposit or withdraw while the guild bank
-- is open. Each move you make is an exchange intent that the next bag check
-- settles. A withdrawal of your own earlier deposit is a transfer or a return;
-- anything else came from the guild.
--
-- The client empties a slot after the action, so guild and bag slots are cached
-- when they change and read from the cache when you act.
local GuildBank = {}

local slotsPerTab = 98

---@class AzerothLedgerGuildBankApi
---@field GetCurrentGuildBankTab? fun(): integer?
---@field GetGuildBankItemLink? fun(tab: integer, slot: integer): string?
---@field GetGuildBankItemInfo? fun(tab: integer, slot: integer): any, integer?, boolean?
---@field GetCursorInfo? fun(): string?

local function intent(link, quantity, direction)
    local itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
    local key = itemID and addon.Item.key(link, itemID)
    if not key or type(quantity) ~= "number" or quantity < 1 or quantity ~= math.floor(quantity) then
        return nil
    end
    return { channel = "guild", direction = direction, key = key, itemID = itemID, link = link, quantity = quantity }
end

-- Reads one guild bank tab, or nil when the client cannot show it whole.
---@param api AzerothLedgerGuildBankApi
---@param tab integer
---@return table<integer, {link: string, quantity: integer}>?
function GuildBank.tab(api, tab)
    if type(api.GetGuildBankItemLink) ~= "function" or type(api.GetGuildBankItemInfo) ~= "function" then
        return nil
    end
    local result = {}
    for slot = 1, slotsPerTab do
        local linkOK, link = pcall(api.GetGuildBankItemLink, tab, slot)
        local infoOK, _, count = pcall(api.GetGuildBankItemInfo, tab, slot)
        if not linkOK or not infoOK then
            return nil
        end
        if type(count) == "number" and count > 0 then
            if type(link) ~= "string" then
                return nil
            end
            result[slot] = { link = link, quantity = count }
        end
    end
    return result
end

-- The store commands this channel writes through.
---@type ALCommandName[]
GuildBank.commands = { "exchangeIntent", "exchangeConfirm" }

---@class ALGuildBankDependencies
---@field api AzerothLedgerGuildBankApi|table
---@field issues string[]
---@field commands ALCommands Built from `GuildBank.commands`
---@field check fun(area: string)

---@param deps ALGuildBankDependencies
function GuildBank.new(deps)
    local api, commands = deps.api, deps.commands
    local open = false
    local tabs, bags = {}, nil
    -- A bag stack on the cursor, waiting to be placed in the guild bank.
    local held

    local function current()
        local ok, tab = pcall(api.GetCurrentGuildBankTab)
        return ok and type(tab) == "number" and tab or nil
    end

    local function refresh()
        local tab = type(api.GetCurrentGuildBankTab) == "function" and current() or nil
        if tab then
            tabs[tab] = GuildBank.tab(api, tab)
        end
    end

    local function move(action)
        if not open or not action then
            return
        end
        local id = commands.exchangeIntent(action)
        if
            id and commands.exchangeConfirm({ channel = "guild", direction = action.direction, ids = { [id] = true } })
        then
            deps.check("possessions")
        end
    end

    local function guildSlot(tab, slot, quantity)
        local cached = tabs[tab] and tabs[tab][slot]
        if cached then
            tabs[tab][slot] = nil
            return intent(cached.link, quantity or cached.quantity, "in")
        end
    end

    local function bagSlot(bag, slot, quantity)
        local cached = bags and bags[bag .. ":" .. slot]
        if cached then
            return intent(cached.link, quantity or cached.quantity, "out")
        end
    end

    local function cursorEmpty()
        if type(api.GetCursorInfo) ~= "function" then
            return false
        end
        local ok, kind = pcall(api.GetCursorInfo)
        return ok and kind == nil
    end

    local hook = addon.Events.hook
    hook(api, deps.issues, "guild bank", api, "AutoStoreGuildBankItem", function(tab, slot)
        move(guildSlot(tab, slot))
    end)
    hook(api, deps.issues, "guild bank", api, "SplitGuildBankItem", function(tab, slot, amount)
        move(guildSlot(tab, slot, amount))
    end)
    -- Picks up a guild stack, or places the held bag stack (taking any stack it swaps with).
    hook(api, deps.issues, "guild bank", api, "PickupGuildBankItem", function(tab, slot)
        if held then
            move(held)
            held = nil
            if not cursorEmpty() then
                move(guildSlot(tab, slot))
            end
        elseif not cursorEmpty() then
            move(guildSlot(tab, slot))
        end
    end)
    local containers = api.C_Container
    if type(containers) == "table" then
        -- Right-clicking a bag stack deposits it whole.
        hook(api, deps.issues, "guild bank", containers, "UseContainerItem", function(bag, slot)
            if open then
                move(bagSlot(bag, slot))
            end
        end)
        hook(api, deps.issues, "guild bank", containers, "PickupContainerItem", function(bag, slot)
            if open then
                held = not cursorEmpty() and bagSlot(bag, slot) or nil
            end
        end)
        hook(api, deps.issues, "guild bank", containers, "SplitContainerItem", function(bag, slot, amount)
            if open then
                held = bagSlot(bag, slot, amount)
            end
        end)
    end

    local channel = {}

    function channel.isOpen()
        return open
    end

    ---@param snapshot AzerothLedgerSnapshot
    function channel.snapshot(snapshot)
        if open and snapshot.area == "bags" then
            bags = addon.Vendor.slots(api)
        end
    end

    local function show()
        if not open then
            open, tabs, held = true, {}, nil
            deps.check("possessions")
            bags = addon.Vendor.slots(api)
            refresh()
        end
    end

    local function hide()
        open, tabs, bags, held = false, {}, nil, nil
    end

    local interaction = type(api.Enum) == "table" and api.Enum.PlayerInteractionType
    local guildBanker = type(interaction) == "table" and interaction.GuildBanker or 10
    channel.events = {
        GUILDBANKFRAME_OPENED = show,
        GUILDBANKFRAME_CLOSED = hide,
        PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind)
            if kind == guildBanker then
                show()
            end
        end,
        PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(kind)
            if kind == guildBanker then
                hide()
            end
        end,
        GUILDBANKBAGSLOTS_CHANGED = function()
            if open then
                refresh()
            end
        end,
    }

    return channel
end

addon.GuildBank = GuildBank
