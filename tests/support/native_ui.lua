-- A native frame port used by interaction tests and the layout preview.
local Native = {}

function Native.create(options)
    local controls = {}
    local function create(kind, name, parent, template)
        local control = {
            kind = kind,
            name = name,
            parent = parent,
            template = template,
            scripts = {},
            shown = true,
            enabled = true,
            width = 0,
            height = 0,
            text = "",
            points = {},
            level = 1,
        }
        controls[#controls + 1] = control
        for _, method in ipairs({
            "EnableMouse",
            "SetFrameStrata",
            "SetAllPoints",
            "SetMovable",
            "RegisterForDrag",
            "RegisterEvent",
            "SetClampedToScreen",
            "RegisterForClicks",
            "SetAutoFocus",
            "SetMaxLetters",
            "EnableMouseWheel",
            "EnableKeyboard",
            "SetShadowColor",
            "SetShadowOffset",
            "SetTexCoord",
            "StartMoving",
            "StopMovingOrSizing",
        }) do
            control[method] = function() end
        end
        function control:SetPoint(point, relative, relativePoint, x, y)
            if type(relative) == "number" then
                x, y, relative, relativePoint = relative, relativePoint, self.parent, point
            end
            self.points[#self.points + 1] = {
                point = point,
                relative = relative or self.parent,
                relativePoint = relativePoint or point,
                x = x or 0,
                y = y or 0,
            }
        end
        function control:ClearAllPoints()
            self.points = {}
        end
        function control:SetSize(width, height)
            self.width, self.height = width, height
        end
        function control:SetWidth(value)
            self.width = value
        end
        function control:SetHeight(value)
            self.height = value
        end
        function control:GetWidth()
            return self.width
        end
        function control:GetHeight()
            return self.height
        end
        function control:SetColorTexture(...)
            self.color = { ... }
        end
        function control:SetTexture(value)
            if options and options.rejectedTextures and options.rejectedTextures[value] then
                self.texture = nil
                return false
            end
            self.texture = value
            return true
        end
        function control:SetTextColor(...)
            self.textColor = { ... }
        end
        function control:SetFont(path, size)
            self.font, self.fontSize = path, size
        end
        function control:SetJustifyH(value)
            self.justify = value
        end
        function control:SetJustifyV(value)
            self.vertical = value
        end
        function control:SetWordWrap(value)
            self.wrap = value
        end
        function control:GetStringHeight()
            local size = self.fontSize or 12
            local plain = self.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
            local lines = 0
            for line in (plain .. "\n"):gmatch("(.-)\n") do
                lines = lines
                    + (self.wrap and math.max(1, math.ceil(#line * size * 0.53 / math.max(self.width, 1))) or 1)
            end
            return lines * (size + 2)
        end
        function control:SetFontString(value)
            self.fontString = value
        end
        function control:GetFontString()
            return self.fontString
        end
        function control:SetText(value)
            self.text = value
            if self.fontString then
                self.fontString:SetText(value)
            end
            if self.scripts.OnTextChanged then
                self.scripts.OnTextChanged(self)
            end
        end
        function control:GetText()
            return self.text
        end
        function control:SetScript(event, callback)
            self.scripts[event] = callback
        end
        function control:SetPropagateKeyboardInput(value)
            self.propagate = value
        end
        function control:SetScale(value)
            self.scale = value
        end
        function control:GetScale()
            return self.scale or 1
        end
        function control:SetAlpha(value)
            self.alpha = value
        end
        function control.CreateAnimationGroup(region)
            local group = { scripts = {}, animations = {}, plays = 0, playing = false }
            region.animationGroups = region.animationGroups or {}
            region.animationGroups[#region.animationGroups + 1] = group
            function group.CreateAnimation(animationGroup, animationKind)
                local animation = { kind = animationKind }
                function animation:SetFromAlpha(value)
                    self.fromAlpha = value
                end
                function animation:SetToAlpha(value)
                    self.toAlpha = value
                end
                function animation:SetDuration(value)
                    self.duration = value
                end
                function animation:SetSmoothing(value)
                    self.smoothing = value
                end
                animationGroup.animations[#animationGroup.animations + 1] = animation
                return animation
            end
            function group:SetScript(event, callback)
                self.scripts[event] = callback
            end
            function group:Play()
                self.playing = true
                self.plays = self.plays + 1
            end
            function group:Stop()
                if self.playing then
                    self.playing = false
                    if self.scripts.OnStop then
                        self.scripts.OnStop(self)
                    end
                end
            end
            function group:Finish()
                self.playing = false
                if self.scripts.OnFinished then
                    self.scripts.OnFinished(self)
                end
            end
            return group
        end
        function control:SetFrameLevel(value)
            self.level = value
        end
        function control:GetFrameLevel()
            return self.level
        end
        function control:SetShown(value)
            local previous = self.shown
            self.shown = value
            if previous and not value and self.scripts.OnHide then
                self.scripts.OnHide(self)
            end
        end
        function control:Show()
            self:SetShown(true)
        end
        function control:Hide()
            self:SetShown(false)
        end
        function control:IsShown()
            return self.shown
        end
        function control:IsVisible()
            return self.shown and (not self.parent or self.parent:IsVisible())
        end
        function control:SetEnabled(value)
            self.enabled = value
        end
        function control:IsEnabled()
            return self.enabled
        end
        function control:SetFocus()
            self.focus = true
            if self.scripts.OnEditFocusGained then
                self.scripts.OnEditFocusGained(self)
            end
        end
        function control:ClearFocus()
            self.focus = false
            if self.scripts.OnEditFocusLost then
                self.scripts.OnEditFocusLost(self)
            end
        end
        function control:HasFocus()
            return self.focus
        end
        function control:Click(mouseButton)
            if self:IsVisible() and self.enabled then
                self.scripts.OnClick(self, mouseButton or "LeftButton")
            end
        end
        function control:SetHighlightTexture(texture)
            self.highlight = texture
        end
        function control:LockHighlight()
            self.highlighted = true
        end
        function control:UnlockHighlight()
            self.highlighted = false
        end
        function control:SetScrollChild(child)
            self.scrollChild = child
        end
        function control:GetVerticalScroll()
            return self.scroll or 0
        end
        function control:SetVerticalScroll(value)
            self.scroll = value
        end
        function control:CreateFontString(regionName, layer)
            local region = create("FontString", regionName, self)
            region.layer = layer
            return region
        end
        function control:CreateTexture(regionName, layer, regionTemplate, subLevel)
            local region = create("Texture", regionName, self)
            region.layer = layer
            region.template = regionTemplate
            region.subLevel = subLevel or 0
            return region
        end
        function control:GetDrawLayer()
            return self.layer, self.subLevel
        end
        function control:GetRegions()
            local regions = {}
            for _, region in ipairs(controls) do
                if region.parent == self and (region.kind == "Texture" or region.kind == "FontString") then
                    regions[#regions + 1] = region
                end
            end
            return unpack(regions)
        end
        return control
    end
    local parent = create("Frame", "UIParent")
    parent:SetSize(1600, 900)
    return {
        api = {
            UIParent = parent,
            CreateFrame = create,
            UISpecialFrames = {},
            STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
            ITEM_QUALITY_COLORS = {
                [0] = { r = 0.62, g = 0.62, b = 0.62 },
                [1] = { r = 0.9, g = 0.87, b = 0.81 },
                [2] = { r = 0.35, g = 0.82, b = 0.43 },
                [3] = { r = 0.38, g = 0.63, b = 1 },
            },
        },
        controls = controls,
    }
end

return Native
