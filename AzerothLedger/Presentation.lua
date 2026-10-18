local _, addon = ...
local Presentation = {}
local controllers = setmetatable({}, { __mode = "k" })

function Presentation.refresh(store)
    if controllers[store] then
        controllers[store].refresh()
    end
end

function Presentation.preview(store)
    if controllers[store] then
        controllers[store].preview()
    end
end

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
    local facts = addon.LastSeen.tooltipFacts(record, summary)
    local observations = {}
    local showDetails = store:display().tooltipDetails
    for _, check in ipairs(lastSeen.checks) do
        if showDetails and check.observedQuantity ~= nil then
            observations[#observations + 1] = addon.Collection.checkText(check)
        end
    end
    return "Azeroth Ledger: "
        .. table.concat(facts, ", ")
        .. " • total gained "
        .. record.totalGained
        .. " • status "
        .. addon.LastSeen.ownershipText(lastSeen)
        .. " • source "
        .. summary.source
        .. (#observations > 0 and ("\n" .. table.concat(observations, "\n")) or "")
end

---@param api table
---@param store ALStore
---@return boolean, string?
function Presentation.register(api, store)
    local preferences = store:display()
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
        preferences = store:display()
        if not preferences.tooltips or tooltip:IsForbidden() then
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
            local color = preferences.gold
            tooltip:AddLine(line, color[1], color[2], color[3], true)
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
    local queue, remaining, isPreview = {}, 0, false
    local preferencesRevision
    local function refresh()
        preferences = store:display()
        preferencesRevision = store:displayRevision()
        local width, height = api.UIParent:GetWidth(), api.UIParent:GetHeight()
        local scale = math.min(preferences.toastScale, width / 340, height / 64)
        toast:SetScale(scale)
        local maxX = math.max(0, (width - 340 * scale) / 2)
        local maxY = math.max(0, height - 64 * scale)
        toast:ClearAllPoints()
        toast:SetPoint(
            "TOP",
            api.UIParent,
            "TOP",
            math.max(-maxX, math.min(maxX, preferences.toastX)) / scale,
            -math.min(maxY, preferences.toastY) / scale
        )
        local color = preferences.canvas
        background:SetColorTexture(color[1], color[2], color[3], preferences.backgroundOpacity)
        heading:SetTextColor(unpack(preferences.gold))
        item:SetTextColor(unpack(preferences.text))
        if not preferences.toasts then
            queue = {}
            if not isPreview then
                remaining = 0
                toast:Hide()
            end
        end
    end
    refresh()
    controllers[store] = {
        refresh = refresh,
        preview = function()
            refresh()
            heading:SetText("Notification preview")
            item:SetText("Your next Collection discovery will appear here")
            isPreview, remaining = true, preferences.toastDuration
            toast:Show()
        end,
    }
    toast:SetScript("OnClick", function()
        local link = item:GetText()
        toast:Hide()
        remaining = 0
        if isPreview then
            isPreview = false
            return
        end
        if addon.Book and type(addon.Book.openDiscovery) == "function" then
            addon.Book.openDiscovery(api, store, api.UnitName("player"), api.GetRealmName(), link)
        end
    end)
    toast:Hide()
    driver:RegisterEvent("DISPLAY_SIZE_CHANGED")
    driver:RegisterEvent("UI_SCALE_CHANGED")
    driver:SetScript("OnEvent", refresh)
    driver:SetScript("OnUpdate", function(_, elapsed)
        if preferencesRevision ~= store:displayRevision() then
            refresh()
        end
        local discoveries = store:takeDiscoveries()
        -- External store callers can change preferences without visiting Settings.
        if not preferences.toasts and not isPreview then
            queue, remaining = {}, 0
            toast:Hide()
            return
        end
        for _, record in ipairs(preferences.toasts and discoveries or {}) do
            -- Bound transient display work; permanent discoveries stay in the Collection.
            if #queue < 20 then
                queue[#queue + 1] = record.links[1]
            end
        end
        if not isPreview and not preferences.toastCombat and api.InCombatLockdown and api.InCombatLockdown() then
            toast:Hide()
            return
        end
        remaining = math.max(0, remaining - elapsed)
        if remaining > 0 then
            toast:Show()
        end
        if remaining == 0 then
            isPreview = false
            local link = table.remove(queue, 1)
            if link then
                refresh()
                heading:SetText("New Collection discovery")
                item:SetText(preferences.qualityColors and link or link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
                remaining = preferences.toastDuration
                if preferences.toastSound and api.PlaySound and api.SOUNDKIT and api.SOUNDKIT.UI_EPICLOOT_TOAST then
                    api.PlaySound(api.SOUNDKIT.UI_EPICLOOT_TOAST, "SFX")
                end
                toast:Show()
            else
                toast:Hide()
            end
        end
    end)
    return true
end

addon.Presentation = Presentation
