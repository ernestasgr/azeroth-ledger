-- Loads addon files the way the client does: the files a TOC lists, in its order.
-- Specs and tools name the module to stop at, so adding a file means editing only the TOC.
local Loader = {}

function Loader.modules(folder)
    local names = {}
    for line in io.lines(folder .. "/" .. folder .. ".toc") do
        local name = line:match("^%s*([^#%s]%S*)%.lua%s*$")
        if name then
            names[#names + 1] = name
        end
    end
    return names
end

local function position(folder, names, name)
    for index, listed in ipairs(names) do
        if listed == name then
            return index
        end
    end
    error(name .. " is not listed in " .. folder .. ".toc", 4)
end

-- Loads every module after `after` (or from the first) through `through` into `target`.
local function load(folder, through, target, after)
    local names = Loader.modules(folder)
    local last = position(folder, names, through)
    local first = after and position(folder, names, after) + 1 or 1
    assert(first <= last, after and (after .. " is not listed before " .. through .. " in " .. folder .. ".toc"))
    target = target or {}
    for index = first, last do
        assert(loadfile(folder .. "/" .. names[index] .. ".lua"))(folder, target)
    end
    return target
end

function Loader.addon(through, addon, after)
    return load("AzerothLedger", through, addon, after)
end

function Loader.companion(through, companion, after)
    return load("AzerothLedger_Tests", through, companion, after)
end

return Loader
