local _, addon = ...
local Presentation = {}

---@param store ALStore
---@param link string
---@param character string
---@param realm string
---@return string?
function Presentation.line(store, link, character, realm)
    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    local key = itemID and addon.Item.key(link, itemID)
    local record = key and store:describe(key)
    local summary = key and store:tooltipFacts(key)
    if not record or not summary then
        return nil
    end
    local lastSeen = addon.LastSeen.project(store, record, character, realm)
    local facts = {}
    if record.firstSeenUnits > 0 or not summary.hasGains then
        facts[#facts + 1] = "Seen"
    end
    local methods = summary.methods
    if methods.Looted then
        facts[#facts + 1] = "Looted"
    end
    for _, method in ipairs({ "Quest", "Crafted", "Vendor", "Obtained" }) do
        if methods[method] then
            facts[#facts + 1] = method == "Obtained" and "Obtained (way unknown)" or ("Obtained (" .. method .. ")")
        end
    end
    local observations = {}
    for _, check in ipairs(lastSeen.checks) do
        if check.observedQuantity ~= nil then
            observations[#observations + 1] = addon.Collection.checkText(check)
        end
    end
    return "Azeroth Ledger: "
        .. table.concat(facts, ", ")
        .. " • total gained "
        .. record.totalGained
        .. " • status "
        .. addon.Collection.ownershipText(lastSeen)
        .. " • source "
        .. summary.source
        .. (#observations > 0 and ("\n" .. table.concat(observations, "\n")) or "")
end

---@param api table
---@param store ALStore
---@return boolean, string?
function Presentation.register(api, store)
    local processor = api.TooltipDataProcessor
    local itemType = api.Enum and api.Enum.TooltipDataType and api.Enum.TooltipDataType.Item
    if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or itemType == nil then
        return false, "Item tooltip post-call unavailable"
    end
    local tooltipUtil = api.TooltipUtil
    if type(tooltipUtil) ~= "table" or type(tooltipUtil.GetDisplayedItem) ~= "function" then
        return false, "TooltipUtil.GetDisplayedItem unavailable"
    end
    for _, name in ipairs({ "CreateFrame", "UnitName", "GetRealmName" }) do
        if type(api[name]) ~= "function" then
            return false, "Presentation: " .. name .. " unavailable"
        end
    end
    processor.AddTooltipPostCall(itemType, function(tooltip)
        if not store:display().tooltips or tooltip:IsForbidden() then
            return
        end
        -- Inspect actual visible text: ClearLines may rebuild the same item
        -- asynchronously, so an item-key flag alone cannot prevent duplicates.
        for _, region in ipairs({ tooltip:GetRegions() }) do
            if type(region.GetText) == "function" then
                local text = region:GetText()
                if type(text) == "string" and text:find("Azeroth Ledger: ", 1, true) == 1 then
                    return
                end
            end
        end
        local _, link = tooltipUtil.GetDisplayedItem(tooltip)
        local character, realm = api.UnitName("player"), api.GetRealmName()
        if type(link) ~= "string" or type(character) ~= "string" or type(realm) ~= "string" then
            return
        end
        local line = Presentation.line(store, link, character, realm)
        if line then
            tooltip:AddLine(line, 0.85, 0.75, 0.45, true)
        end
    end)

    local driver = api.CreateFrame("Frame")
    local toast = api.CreateFrame("Button", nil, api.UIParent)
    toast:SetSize(340, 64)
    toast:SetPoint("TOP", api.UIParent, "TOP", 0, -150)
    toast:SetFrameStrata("DIALOG")
    toast:EnableMouse(true)
    toast:RegisterForClicks("LeftButtonUp")
    local background = toast:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.06, 0.03, 0.95)
    local heading = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOP", toast, "TOP", 0, -10)
    heading:SetText("New Collection discovery")
    local item = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    item:SetPoint("TOP", heading, "BOTTOM", 0, -8)
    item:SetWidth(320)
    local queue, remaining = {}, 0
    toast:SetScript("OnClick", function()
        local link = item:GetText()
        toast:Hide()
        remaining = 0
        if addon.Book and type(addon.Book.openDiscovery) == "function" then
            addon.Book.openDiscovery(api, store, api.UnitName("player"), api.GetRealmName(), link)
        end
    end)
    toast:Hide()
    driver:SetScript("OnUpdate", function(_, elapsed)
        local discoveries = store:takeDiscoveries()
        if not store:display().toasts then
            queue, remaining = {}, 0
            toast:Hide()
            return
        end
        for _, record in ipairs(discoveries) do
            -- Bound transient display work; permanent discoveries stay in the Collection.
            if #queue < 20 then
                queue[#queue + 1] = record.links[1]
            end
        end
        remaining = math.max(0, remaining - elapsed)
        if remaining == 0 then
            local link = table.remove(queue, 1)
            if link then
                item:SetText(link)
                remaining = 5
                toast:Show()
            else
                toast:Hide()
            end
        end
    end)
    return true
end

addon.Presentation = Presentation
