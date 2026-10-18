local load = assert(loadfile("tests/support/addon.lua"))()
-- Every player-facing Collection term comes from one module: ownership, how you
-- got it, and Source. Expected wording follows GLOSSARY.md, not the code.
local addon = load.addon("LastSeen")
date = os.date
local Wording = addon.LastSeen

local function equal(expected, actual, rule)
    assert(expected == actual, rule .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Ownership: label, help text, and the colour class the Book tints it with.
local ownership = {
    {
        state = "present",
        label = "Present",
        colour = "green",
        help = "Present: the item was found on at least one character in the selected view.",
    },
    {
        state = "unknown",
        label = "Unknown",
        colour = "gold",
        help = "Unknown: the addon could not check all the storage it needs, "
            .. "so it cannot tell whether the item is still there.",
    },
    {
        state = "historical",
        label = "Historical only",
        colour = "gold",
        help = "Historical only: the item was found before, but not on complete checks of the selected "
            .. "characters' relevant bags, bank, and gear. "
            .. "This describes the last check dates, not where the item is now.",
    },
}
local choices = Wording.ownershipChoices()
equal("Any status", choices[1].label, "the ownership filter must offer every status")
for index, case in ipairs(ownership) do
    local wording = Wording.ownership(case.state)
    equal(case.label, wording.label, case.state .. " must use the glossary label")
    equal(case.help, wording.help, case.state .. " must explain the glossary term")
    equal(case.colour, wording.colour, case.state .. " must keep its status colour")
    equal(case.state, choices[index + 1].value, "ownership choices must follow the glossary order")
    equal(case.label, choices[index + 1].label, "the filter must name " .. case.state .. " like the status line")
end
equal(#ownership + 1, #choices, "the ownership filter must offer only glossary states")
equal("Present", Wording.ownershipText({ state = "present", checks = {} }), "a present item has no date")
equal("Unknown", Wording.ownershipText({ state = "unknown", checks = {} }), "an unknown item has no date")
equal(
    "Historical only as of " .. os.date("%Y-%m-%d %H:%M", 1000),
    Wording.ownershipText({ state = "historical", asOf = 1000, checks = {} }),
    "Historical only must name the check date it describes"
)
equal(nil, Wording.ownership("gone"), "an unrecorded state must not borrow a glossary label")

-- How you got it: breakdown label, filter choice, tooltip fact, and glossary group.
local methods = {
    { key = "Seen", label = "Already had at first check", choice = "Already had", fact = "Seen", group = "Seen" },
    {
        key = "Appeared",
        label = "Appeared after an earlier check",
        choice = "Appeared later",
        fact = "Appeared later",
        group = "Seen",
    },
    { key = "Looted", label = "Looted", choice = "Looted", fact = "Looted", group = "Looted" },
    { key = "Quest", label = "Quest", choice = "Quest reward", fact = "Obtained (Quest)", group = "Obtained" },
    { key = "Crafted", label = "Crafted", choice = "Crafted", fact = "Obtained (Crafted)", group = "Obtained" },
    { key = "Vendor", label = "Vendor", choice = "Vendor purchase", fact = "Obtained (Vendor)", group = "Obtained" },
    {
        key = "Obtained",
        label = "Obtained",
        choice = "Obtained",
        fact = "Obtained (way unknown)",
        group = "Obtained",
    },
    { key = "Transfer", label = "Transfer from another character", group = "Transfer" },
}
local methodChoices = Wording.methodChoices()
equal("Any method", methodChoices[1].label, "the method filter must offer every method")
for index, case in ipairs(methods) do
    local wording = Wording.method(case.key)
    equal(case.label, wording.label, case.key .. " must use its breakdown label")
    equal(case.label, Wording.methodLabel(case.key), case.key .. " must label the breakdown")
    equal(case.choice, wording.choice, case.key .. " must name its filter choice")
    equal(case.fact, wording.fact, case.key .. " must name its tooltip fact")
    equal(case.group, wording.group, case.key .. " must belong to its glossary term")
    if case.choice then
        equal(case.key, methodChoices[index + 1].value, "method choices must keep the breakdown order")
        equal(case.choice, methodChoices[index + 1].label, case.key .. " must be offered as a filter")
    end
end
equal(#methods, #methodChoices, "a Transfer is not a way to filter the account's gains")
equal("Appeared", Wording.firstCheckMethod(true), "units after an earlier check appeared later")
equal("Seen", Wording.firstCheckMethod(false), "units at the first check were already had")

-- The tooltip lists the first-check fact before confirmed ways, in breakdown order.
local function facts(record, methodsSeen, hasGains)
    return table.concat(Wording.tooltipFacts(record, { methods = methodsSeen, hasGains = hasGains }), ", ")
end
equal(
    "Seen, Looted, Obtained (Quest), Obtained (way unknown)",
    facts({ firstSeenUnits = 2 }, { Obtained = true, Quest = true, Looted = true }, true),
    "the tooltip must list every way you got the item"
)
equal(
    "Appeared later",
    facts({ firstSeenUnits = 1, firstSeenLater = true }, {}, false),
    "units that appeared after an earlier check were not already had"
)
equal("Seen", facts({ firstSeenUnits = 0 }, {}, false), "an item with no confirmed gains was at least Seen")
equal(
    "Looted",
    facts({ firstSeenUnits = 0, firstSeenLater = true }, { Looted = true }, true),
    "an item first found through a gain was not already had"
)

-- Journal actions name how a gain arrived, or the move it was.
local actions = {
    { gain = { method = "Looted" }, action = "Looted" },
    { gain = { method = "Quest" }, action = "Quest" },
    { gain = { method = "Crafted" }, action = "Crafted" },
    { gain = { method = "Vendor" }, action = "Purchase" },
    { gain = { method = "Obtained", mailKind = "auction-purchase" }, action = "Auction purchase" },
    { gain = { method = "Obtained", channel = "mail" }, action = "Mail" },
    { gain = { method = "Obtained", channel = "trade" }, action = "Trade" },
    { gain = { method = "Obtained" }, action = "Obtained (way unknown)" },
}
for _, case in ipairs(actions) do
    equal(case.action, Wording.gainAction(case.gain), "a Journal gain must name how it arrived")
end

-- Source: text, identity, and the group label the Book filters by.
local mobGuid = "Creature-0-1-2-3-1234-0000ABCDEF"
local sources = {
    {
        kind = "named mob",
        gain = { source = { kind = "mob", guid = mobGuid, name = "Hogger" } },
        text = "Hogger",
        key = "mob:1234",
        group = "Hogger",
    },
    {
        kind = "unnamed mob",
        gain = { source = { kind = "mob", guid = mobGuid } },
        text = "Mob #1234",
        key = "mob:1234",
        group = "Mob #1234",
    },
    {
        kind = "container",
        gain = { source = { kind = "container", guid = "GameObject-0-1-2-3-171938-0000ABCDEF" } },
        text = "Container #171938",
        key = "container:171938",
        group = "Container #171938",
    },
    {
        kind = "named container",
        gain = { source = { kind = "container", guid = "GameObject-0-1-2-3-171938-0000ABCDEF", name = "Chest" } },
        text = "Chest",
        key = "container:171938",
        group = "Chest",
    },
    {
        kind = "unparseable spawn",
        gain = { source = { kind = "mob", guid = "Creature-broken" } },
        text = "Unnamed mob",
        key = "mob:Creature-broken",
        group = "Unknown mob",
    },
    {
        kind = "vendor",
        gain = { source = { kind = "vendor", name = "Brenda" } },
        text = "Brenda",
        key = "vendor:Brenda",
        group = "Vendor: Brenda",
    },
    {
        kind = "player",
        gain = { source = { kind = "player", name = "Ben", realm = "Realm" } },
        text = "Ben-Realm",
        key = "player:Ben-Realm",
        group = "Player: Ben-Realm",
    },
    {
        kind = "named quest",
        gain = { context = { kind = "quest", id = 42, name = "Wolves" } },
        text = "Wolves",
        key = "quest:42",
        group = "Wolves",
    },
    {
        kind = "unnamed quest",
        gain = { context = { kind = "quest", id = 42 } },
        text = "quest 42",
        key = "quest:42",
        group = "Quest #42",
    },
    {
        kind = "named recipe",
        gain = { context = { kind = "recipe", id = 7, name = "Bolt of Linen Cloth" } },
        text = "Bolt of Linen Cloth",
        key = "recipe:7",
        group = "Bolt of Linen Cloth",
    },
    {
        kind = "unnamed recipe",
        gain = { context = { kind = "recipe", id = 7 } },
        text = "recipe 7",
        key = "recipe:7",
        group = "Recipe #7",
    },
    {
        kind = "auction",
        gain = { mailKind = "auction-purchase" },
        text = "Auction purchase",
        key = "auction",
        group = "Auction purchase",
    },
    { kind = "unknown", gain = {}, text = "Unknown source", key = "unknown", group = "Unknown" },
}
for _, case in ipairs(sources) do
    equal(case.text, Wording.gainSourceText(case.gain), "a " .. case.kind .. " Source must read naturally")
    equal(case.key, (Wording.sourceIdentity(case.gain)), "a " .. case.kind .. " Source must keep its identity")
    local groups = {}
    Wording.addSource(groups, case.gain, 1)
    equal(case.group, Wording.sourceGroups(groups)[1].label, "a " .. case.kind .. " Source must group by name")
end
equal("Unknown", Wording.sourceText(nil), "a gain without proof has an Unknown Source")

-- The breakdown's first-check buckets are Sources too, never confused with recorded ones.
local buckets = {
    { method = "Seen", key = "Initial stock", label = "Already had before first check" },
    { method = "Appeared", key = "Appeared later", label = "Unknown, appeared after an earlier check" },
    { method = "Transfer", key = "Your characters", label = "Your other characters" },
}
for _, case in ipairs(buckets) do
    equal(case.key, Wording.method(case.method).source, case.method .. " units must fill their own Source")
    equal(case.label, Wording.sourceLabel(case.key), case.key .. " must say where the units came from")
    local groups = {}
    Wording.addSource(groups, { source = { kind = "mob", guid = mobGuid, name = case.key } }, 1)
    equal(
        case.key .. " (mob #1234)",
        Wording.sourceGroups(groups)[1].label,
        "a recorded Source must not share a first-check label"
    )
end
equal("Hogger", Wording.sourceLabel("Hogger"), "a recorded Source keeps its group label")

-- Two Sources with one name are told apart by identity.
local groups = {}
Wording.addSource(groups, sources[1].gain, 1)
Wording.addSource(groups, { source = { kind = "mob", guid = "Creature-0-1-2-3-99-0000ABCDEF", name = "Hogger" } }, 2)
local grouped = Wording.sourceGroups(groups)
equal("Hogger (mob #1234)", grouped[1].label, "same-named Sources must stay separate")
equal("Hogger (mob #99)", grouped[2].label, "same-named Sources must stay separate")

print("collection_wording_spec: passed")
