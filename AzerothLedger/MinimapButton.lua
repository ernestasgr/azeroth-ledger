local _, addon = ...

-- The Ledger's button on the minimap rim. Its angle is saved per account in
-- AzerothLedgerMinimapButtonDB; geometry is kept in pure functions.
local MinimapButton = {}

MinimapButton.DEFAULTS = { minimapPos = 315 }

local SIZE, ICON_SIZE, BORDER_SIZE = 31, 20, 53
local FALLBACK_RADIUS, RIM_OFFSET = 80, 10

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A saved angle in degrees, or the default when missing or not a finite number.
---@param value any
---@return number
function MinimapButton.angle(value)
    return (finite(value) and value or MinimapButton.DEFAULTS.minimapPos) % 360
end

-- The button's center offset from the minimap center.
---@param angle number
---@param minimapWidth any
---@return number, number
function MinimapButton.offset(angle, minimapWidth)
    local radius = type(minimapWidth) == "number" and minimapWidth > 0 and minimapWidth / 2 + RIM_OFFSET
        or FALLBACK_RADIUS
    local radians = math.rad(angle)
    return math.cos(radians) * radius, math.sin(radians) * radius
end

-- The angle from the minimap center to the cursor, or nil when unreadable.
---@return number?
function MinimapButton.cursorAngle(cursorX, cursorY, centerX, centerY, scale)
    if not (finite(cursorX) and finite(cursorY) and finite(centerX) and finite(centerY) and finite(scale)) then
        return nil
    end
    if scale <= 0 then
        return nil
    end
    return math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)) % 360
end

-- Returns the saved-variable table, creating it with defaults when absent.
---@param api table
---@return table
local function database(api)
    local saved = rawget(api, "AzerothLedgerMinimapButtonDB")
    if type(saved) ~= "table" then
        saved = {}
        rawset(api, "AzerothLedgerMinimapButtonDB", saved)
    end
    saved.minimapPos = MinimapButton.angle(rawget(saved, "minimapPos"))
    return saved
end

local function texture(button, layer, size, path, x, y)
    local region = button:CreateTexture(nil, layer)
    region:SetSize(size, size)
    region:SetTexture(path)
    region:SetPoint("TOPLEFT", x, y)
    return region
end

local function attachTooltip(api, button)
    local tooltip = rawget(api, "GameTooltip")
    if not tooltip then
        return
    end
    button:SetScript("OnEnter", function(self)
        local centerX = self:GetCenter()
        local parent = rawget(api, "UIParent")
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

-- Creates the button; returns nil when the client has no minimap or frames.
---@param api table
---@param onClick fun()
---@return table?
function MinimapButton.create(api, onClick)
    local minimap = rawget(api, "Minimap")
    local createFrame = rawget(api, "CreateFrame")
    if not minimap or type(createFrame) ~= "function" then
        return nil
    end
    local saved = database(api)

    -- Named so minimap button collectors such as EllesmereUI can find it.
    local button = createFrame("Button", "AzerothLedgerMinimapButton", minimap)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(minimap:GetFrameLevel() + 1)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    texture(button, "OVERLAY", BORDER_SIZE, "Interface\\Minimap\\MiniMap-TrackingBorder", 0, 0)
    texture(button, "BACKGROUND", ICON_SIZE, "Interface\\Minimap\\UI-Minimap-Background", 7, -5)
    texture(button, "ARTWORK", ICON_SIZE, "Interface\\Icons\\INV_Misc_Book_09", 7, -5):SetTexCoord(
        0.05,
        0.95,
        0.05,
        0.95
    )

    local function place()
        button:ClearAllPoints()
        local x, y = MinimapButton.offset(saved.minimapPos, minimap:GetWidth())
        button:SetPoint("CENTER", minimap, "CENTER", x, y)
    end

    local function followCursor()
        local cursor = rawget(api, "GetCursorPosition")
        if type(cursor) ~= "function" then
            return
        end
        local cursorX, cursorY = cursor()
        local centerX, centerY = minimap:GetCenter()
        local angle = MinimapButton.cursorAngle(cursorX, cursorY, centerX, centerY, minimap:GetEffectiveScale())
        if angle then
            saved.minimapPos = angle
            place()
        end
    end

    button:SetScript("OnClick", function()
        onClick()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", followCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        followCursor()
        self:SetScript("OnUpdate", nil)
    end)
    attachTooltip(api, button)
    place()
    return button
end

addon.MinimapButton = MinimapButton
