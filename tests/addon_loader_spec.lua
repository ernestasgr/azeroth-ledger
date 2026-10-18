local load = assert(loadfile("tests/support/addon.lua"))()

local addon = load.addon("Schema")
assert(addon.Item and addon.Schema, "a spec loading through Schema gets every module the TOC lists before it")
assert(addon.Client == nil, "a spec loading through Schema must not get the modules the TOC lists after it")

local same = {}
assert(load.addon("Client", same) == same and same.Client, "a spec can load into the addon table it already holds")

local later = load.addon("Schema")
local item = later.Item
load.addon("Scan", later, "Schema")
assert(later.Scan and later.Item == item, "a later stage loads only the modules after the earlier stage")

local untouched = {}
local ok, message = pcall(load.addon, "Missing", untouched)
assert(
    not ok and message:find("Missing", 1, true) and message:find("AzerothLedger.toc", 1, true),
    "a module name the TOC does not list must fail naming the module and the TOC"
)
assert(next(untouched) == nil, "a module name the TOC does not list must fail before anything loads")
ok, message = pcall(load.addon, "Schema", {}, "Missing")
assert(not ok and message:find("Missing", 1, true), "a stage after an unlisted module must fail clearly")

print("addon_loader_spec: passed")
