local _, addon = ...

local Collection = {}
local frame
local content
local activeFilterCharacter
local activeFilterRealm

---@class AzerothLedgerCollectionApi
---@field CreateFrame? fun(frameType: string, name?: string, parent?: table, template?: string): table
---@field UIParent table
---@field GameFontNormal table

local function stamp(seconds)
    return date("%Y-%m-%d %H:%M", seconds)
end

local function matchesFilter(filterCharacter, filterRealm, name, realm)
    return (not filterCharacter or name == filterCharacter) and (not filterRealm or realm == filterRealm)
end

---@param store AzerothLedgerStore
---@param character string
---@param realm string
---@param filterCharacter? string
---@param filterRealm? string
---@return string[]
-- Produces the text shown in the Collection, including scope freshness.
function Collection.lines(store, character, realm, filterCharacter, filterRealm)
    local lines = {}
    if not filterRealm or filterCharacter then
        for _, area in ipairs({ "bags", "bank", "equipped" }) do
            local state = store:area(filterCharacter or character, filterRealm or realm, area)
            if not state or not state.complete then
                lines[#lines + 1] = area .. ": incomplete / current stock unknown"
            else
                lines[#lines + 1] = area .. ": checked " .. stamp(state.seenAt)
            end
        end
    end
    local shown = 0
    for _, record in ipairs(store:list()) do
        local matches = not filterCharacter and not filterRealm
        for _, seen in ipairs(record.characters) do
            if matchesFilter(filterCharacter, filterRealm, seen.name, seen.realm) then
                matches = true
                break
            end
        end
        if matches then
            shown = shown + 1
            local name = record.links[1]:match("%[([^%]]+)%]") or ("Item " .. record.itemID)
            lines[#lines + 1] = name
                .. " ["
                .. record.key
                .. "] — first scan "
                .. record.firstSeenUnits
                .. " Seen; Total gained "
                .. record.totalGained
            lines[#lines + 1] = "  First Seen "
                .. stamp(record.firstSeen)
                .. " • latest Seen "
                .. stamp(record.lastSeen)
                .. " • confirmed gain unknown"
            for _, seen in ipairs(record.characters) do
                if matchesFilter(filterCharacter, filterRealm, seen.name, seen.realm) then
                    lines[#lines + 1] = "  "
                        .. seen.name
                        .. "-"
                        .. seen.realm
                        .. ": first Seen "
                        .. stamp(seen.firstSeen)
                        .. " • "
                        .. seen.firstSeenUnits
                        .. " units"
                end
            end
            for _, observation in ipairs(record.observations) do
                if matchesFilter(filterCharacter, filterRealm, observation.character, observation.realm) then
                    lines[#lines + 1] = "  "
                        .. stamp(observation.seenAt)
                        .. " • "
                        .. observation.quantity
                        .. " • "
                        .. observation.character
                        .. "-"
                        .. observation.realm
                        .. " • "
                        .. observation.area
                end
            end
        end
    end
    if shown == 0 then
        lines[#lines + 1] = "No items Seen yet."
    end
    return lines
end

---@param api AzerothLedgerCollectionApi
---@param store AzerothLedgerStore
---@param character string
---@param realm string
---@param filterCharacter? string
---@param filterRealm? string
---@return table?
function Collection.open(api, store, character, realm, filterCharacter, filterRealm)
    if type(api.CreateFrame) ~= "function" then
        return nil
    end
    if not frame then
        frame = api.CreateFrame("Frame", "AzerothLedgerCollection", api.UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(650, 450)
        frame:SetPoint("CENTER")
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame.TitleText:SetText("Azeroth Ledger Collection")
        content = api.CreateFrame("ScrollingMessageFrame", nil, frame)
        content:SetPoint("TOPLEFT", 15, -35)
        content:SetPoint("BOTTOMRIGHT", -35, 15)
        content:SetFontObject(api.GameFontNormal)
        content:SetJustifyH("LEFT")
        content:SetMaxLines(10000)
        content:SetFading(false)
        content:EnableMouseWheel(true)
        content:SetScript("OnMouseWheel", function(self, delta)
            if delta > 0 then
                self:ScrollUp()
            else
                self:ScrollDown()
            end
        end)
    end
    activeFilterCharacter = filterCharacter
    activeFilterRealm = filterRealm
    Collection.refresh(store, character, realm)
    frame:Show()
    return frame
end

function Collection.refresh(store, character, realm, filterCharacter, filterRealm)
    if not frame then
        return
    end
    content:Clear()
    for _, line in
        ipairs(
            Collection.lines(
                store,
                character,
                realm,
                filterCharacter or activeFilterCharacter,
                filterRealm or activeFilterRealm
            )
        )
    do
        content:AddMessage(line)
    end
end

addon.Collection = Collection
