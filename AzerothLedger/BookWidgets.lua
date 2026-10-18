local _, addon = ...

local Widgets = {}
Widgets.colors = {}
for _, definition in ipairs(addon.StorePreferences.colorOptions()) do
    Widgets.colors[definition.key] = definition.default
end
local colors = Widgets.colors
local bindings = setmetatable({}, { __mode = "k" })
Widgets.preferences = {}

-- Keep palette tables stable: controls refer to roles, including their current
-- selection state, rather than snapshots of RGB values.
function Widgets.tint(region, color, texture)
    bindings[region] = { color = color, texture = texture }
    local opacity = 1
    if texture and (color == colors.canvas or color == colors.panel or color == colors.raised) then
        opacity = Widgets.preferences.backgroundOpacity or 1
    end
    if texture then
        region:SetColorTexture(color[1], color[2], color[3], color[4] * opacity)
    else
        region:SetTextColor(unpack(color))
    end
end

function Widgets.applyPreferences(preferences)
    Widgets.preferences = preferences
    for key, color in pairs(colors) do
        local value = preferences[key]
        if value then
            for index = 1, 4 do
                color[index] = value[index]
            end
        end
    end
    for region, binding in pairs(bindings) do
        Widgets.tint(region, binding.color, binding.texture)
    end
end

-- Native, finite animations do no Lua work on idle frames. Reuse each group,
-- and restore opacity on interruption so rapid input never leaves dim content.
function Widgets.fade(book, region, duration, from)
    if Widgets.preferences.reducedMotion then
        Widgets.stopMotion(book)
        region:SetAlpha(1)
        return
    end
    if not book.frame:IsShown() or not region:IsShown() then
        return
    end
    local group = region.ledgerFade
    if not group then
        group = region:CreateAnimationGroup()
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetFromAlpha(from)
        alpha:SetToAlpha(1)
        alpha:SetDuration(duration)
        alpha:SetSmoothing("OUT")
        local function restore()
            region:SetAlpha(1)
        end
        group:SetScript("OnFinished", restore)
        group:SetScript("OnStop", restore)
        region.ledgerFade = group
        book.motionGroups = book.motionGroups or {}
        book.motionGroups[#book.motionGroups + 1] = group
    end
    group:Stop()
    group:Play()
end

function Widgets.stopMotion(book)
    for _, group in ipairs(book.motionGroups or {}) do
        group:Stop()
    end
end

-- Same contract as the client's Mixin: copy each mixin's fields onto object.
-- Kept local so the book does not depend on a FrameXML global at load time.
function Widgets.mixin(object, ...)
    for index = 1, select("#", ...) do
        for key, value in pairs((select(index, ...))) do
            object[key] = value
        end
    end
    return object
end

function Widgets.fill(parent, color, x, y, width, height, layer, subLevel)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, subLevel or 0)
    texture:SetPoint("TOPLEFT", x, -y)
    texture:SetSize(width, height)
    Widgets.tint(texture, color, true)
    return texture
end

function Widgets.text(api, parent, value, x, y, width, size, color)
    local font = parent:CreateFontString(nil, "OVERLAY")
    font:SetPoint("TOPLEFT", x, -y)
    font:SetWidth(width)
    font:SetFont(api.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "")
    font:SetJustifyH("LEFT")
    font:SetJustifyV("TOP")
    font:SetWordWrap(true)
    Widgets.tint(font, color or colors.text)
    font:SetShadowColor(0, 0, 0, 0.4)
    font:SetShadowOffset(0, -1)
    font:SetText(value)
    return font
end

function Widgets.panel(api, parent, x, y, width, height, color)
    local frame = api.CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", x, -y)
    frame:SetSize(width, height)
    frame.background = Widgets.fill(frame, color or colors.panel, 0, 0, width, height)
    local line = Widgets.fill(frame, colors.gold, 0, 0, width, 1, "ARTWORK")
    line:SetAlpha(0.14)
    return frame
end

-- Navigation and rows use restrained highlights; only selection receives the gold accent.
function Widgets.button(book, parent, value, x, y, width, height, callback, bordered)
    local control = book.api.CreateFrame("Button", nil, parent)
    control:SetPoint("TOPLEFT", x, -y)
    control:SetSize(width, height)
    control.book = book
    control.baseColor = bordered and colors.raised or colors.panel
    control.background = Widgets.fill(control, control.baseColor, 0, 0, width, height)
    local highlight = Widgets.fill(control, colors.gold, 0, 0, width, height, "HIGHLIGHT")
    highlight:SetAlpha(0.065)
    control:SetHighlightTexture(highlight)
    control.accent = Widgets.fill(control, colors.gold, 0, 0, 2, height, "ARTWORK")
    control.accent:Hide()
    local font = Widgets.text(book.api, control, value, 12, (height - 13) / 2, width - 24, 12)
    font:SetWordWrap(false)
    control:SetFontString(font)
    control:SetText(value)
    control:SetScript("OnClick", callback)
    book.controls[#book.controls + 1] = control
    return control
end

function Widgets.tab(book, parent, value, x, y, width, callback)
    local control = Widgets.button(book, parent, value, x, y, width, 32, callback)
    control.baseColor = colors.canvas
    control.accent:ClearAllPoints()
    control.accent:SetPoint("BOTTOMLEFT", 0, 0)
    control.accent:SetSize(width, 2)
    return control
end

function Widgets.select(control, selected)
    Widgets.tint(control.background, selected and colors.selected or control.baseColor, true)
    Widgets.tint(control:GetFontString(), control.nameColor or (selected and colors.gold or colors.text))
    control.accent:SetShown(selected)
    if selected and not control.selected then
        Widgets.fade(control.book, control.accent, 0.25, 0.35)
    elseif not selected and control.accent.ledgerFade then
        control.accent.ledgerFade:Stop()
    end
    control.selected = selected
end

function Widgets.enable(control, enabled)
    control:SetEnabled(enabled)
    control:SetAlpha(enabled and 1 or 0.35)
end

function Widgets.dropdown(book, parent, value, x, y, width, callback)
    local control = Widgets.button(book, parent, value, x, y, width, 32, callback, true)
    control:GetFontString():SetWidth(width - 38)
    local arrow = control:CreateTexture(nil, "ARTWORK")
    arrow:SetPoint("TOPRIGHT", -8, -8)
    arrow:SetSize(16, 16)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    return control
end

function Widgets.checkbox(book, parent, value, x, y, width, callback)
    local control = Widgets.button(book, parent, value, x, y, width, 26, callback)
    control:GetFontString():ClearAllPoints()
    control:GetFontString():SetPoint("TOPLEFT", 26, -7)
    control:GetFontString():SetWidth(width - 26)
    Widgets.fill(control, colors.edge, 4, 5, 15, 15, "ARTWORK")
    Widgets.fill(control, colors.canvas, 5, 6, 13, 13, "ARTWORK", 1)
    control.mark = Widgets.fill(control, colors.gold, 8, 9, 7, 7, "OVERLAY")
    control.mark:Hide()
    return control
end

function Widgets.icon(parent, x, y, size)
    Widgets.fill(parent, colors.edge, x - 1, y - 1, size + 2, size + 2, "ARTWORK")
    -- Equal-layer textures can be batched out of creation order by WoW.
    -- Keep the image explicitly above its opaque backing.
    local texture = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    texture:SetPoint("TOPLEFT", x, -y)
    texture:SetSize(size, size)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    return texture
end

function Widgets.itemIcon(texture, icon)
    local fallback = "Interface\\Icons\\INV_Misc_QuestionMark"
    if texture:SetTexture(icon or fallback) == false then
        texture:SetTexture(fallback)
    end
end

function Widgets.quality(api, quality)
    if Widgets.preferences.qualityColors == false then
        return colors.text
    end
    local itemColors = api.ITEM_QUALITY_COLORS
    local color = itemColors and itemColors[quality or 1]
    return color and { color.r, color.g, color.b, 1 } or colors.text
end

function Widgets.tooltip(api, control, link)
    if api.GameTooltip and link then
        api.GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        api.GameTooltip:SetHyperlink(link)
        api.GameTooltip:Show()
    end
end

function Widgets.hideTooltip(api)
    if api.GameTooltip then
        api.GameTooltip:Hide()
    end
end

function Widgets.openLink(api, link, mouseButton)
    if api.HandleModifiedItemClick and api.HandleModifiedItemClick(link) then
        return
    end
    local payload = link and link:match("|H(.-)|h")
    if payload and api.SetItemRef then
        api.SetItemRef(payload, link, mouseButton or "LeftButton")
    end
end

addon.BookWidgets = Widgets
