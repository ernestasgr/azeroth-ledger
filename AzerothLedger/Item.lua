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
    local payload = link:match("item:([%d:%-]+)")
    if not payload then
        return nil
    end
    local fields = {}
    for field in (payload .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    if tonumber(fields[1]) ~= itemID then
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

addon.Item = Item
