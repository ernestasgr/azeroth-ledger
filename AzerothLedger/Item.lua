local _, addon = ...

local Item = {}

---@param link string
---@param itemID integer
---@return string?
-- A collection key includes intrinsic suffix and bonus IDs, but ignores mutable instance fields.
function Item.key(link, itemID)
    if type(link) ~= "string" or type(itemID) ~= "number" then
        return nil
    end
    local payload = link:match("item:([%d:%-]+)|")
    if not payload then
        return nil
    end
    local fields = {}
    for field in (payload .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    if tonumber(fields[1]) ~= itemID or #fields < 8 then
        return nil
    end
    local suffix = tonumber(fields[7]) or 0
    local bonusCount = tonumber(fields[13]) or 0
    if bonusCount < 0 or bonusCount > 100 or bonusCount ~= math.floor(bonusCount) then
        return nil
    end
    local bonuses = {}
    for index = 1, bonusCount do
        local bonus = tonumber(fields[13 + index])
        if not bonus or bonus ~= math.floor(bonus) then
            return nil
        end
        bonuses[#bonuses + 1] = bonus
    end
    table.sort(bonuses)
    local parts = { tostring(itemID), tostring(suffix) }
    for _, bonus in ipairs(bonuses) do
        parts[#parts + 1] = tostring(bonus)
    end
    return table.concat(parts, ":")
end

---@param links string[]
---@return {link: string, count: integer}[]
-- Viewer level/spec and instance ID do not create another visible item version.
-- Preserve enchant, gems, intrinsic bonuses and all original full links in the ledger.
function Item.linkGroups(links)
    local groups, byKey = {}, {}
    for _, link in ipairs(links) do
        local payload = link:match("item:([%d:%-]+)|")
        local key = link
        if payload then
            local fields = {}
            for field in (payload .. ":"):gmatch("([^:]*):") do
                fields[#fields + 1] = tostring(tonumber(field) or 0)
            end
            fields[8], fields[9], fields[10] = "0", "0", "0"
            while fields[#fields] == "0" do
                fields[#fields] = nil
            end
            key = table.concat(fields, ":")
        end
        local group = byKey[key]
        if group then
            group.count = group.count + 1
        else
            group = { link = link, count = 1 }
            byKey[key] = group
            groups[#groups + 1] = group
        end
    end
    return groups
end

addon.Item = Item
