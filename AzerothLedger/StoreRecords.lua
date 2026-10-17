local _, addon = ...

-- Read-only record and area queries, plus the marker and environment.

local V = addon.SchemaValidate
local CURRENT_SCHEMA, areas, isInteger, isName = V.CURRENT_SCHEMA, V.areas, V.isInteger, V.isName
local areaKey, copyRecord, validEnvironment = V.areaKey, V.copyRecord, V.validEnvironment

local StoreRecords = {}

function StoreRecords.install(store, kernel)
    local valid, readable, supported, saveFields = kernel.valid, kernel.readable, kernel.supported, kernel.save

    function store.breakdown(_self, key, scope, pause)
        local record = valid[key]
        if not record then
            return nil
        end
        scope = scope or {}
        local scoped = scope.character ~= nil or scope.realm ~= nil
        local function matches(character, realm)
            return (not scope.character or scope.character == character) and (not scope.realm or scope.realm == realm)
        end
        local initial = not scoped and record.firstSeenUnits or nil
        -- Units that arrived after an earlier complete check, with no
        -- confirmed way, are not stock the character already had.
        local later = record.firstSeenLater
        local result = {
            initial = initial,
            gained = scoped and 0 or record.totalGained,
            methods = initial and { [later and "Appeared" or "Seen"] = initial } or {},
            sources = initial and { [later and "Appeared later" or "Initial stock"] = initial } or {},
        }
        -- A scoped view explains its characters' own first units. Only a single
        -- character's view lists units moved in from your other characters: wider
        -- views hold both ends and count those units where they started.
        if scoped then
            local transferred = 0
            for _, seen in ipairs(record.characters) do
                if matches(seen.name, seen.realm) then
                    transferred = transferred + (seen.transferredUnits or 0)
                    if seen.firstSeenUnits > 0 then
                        -- Entries saved before the per-character flag share the item's
                        -- flag only when they were its first sighting.
                        local appeared = seen.firstSeenLater
                        if appeared == nil and seen.firstSeen == record.firstSeen then
                            appeared = later
                        end
                        local method = appeared and "Appeared" or "Seen"
                        local source = appeared and "Appeared later" or "Initial stock"
                        result.methods[method] = (result.methods[method] or 0) + seen.firstSeenUnits
                        result.sources[source] = (result.sources[source] or 0) + seen.firstSeenUnits
                    end
                end
            end
            if transferred > 0 and scope.character then
                result.methods.Transfer = transferred
                result.sources["Your characters"] = transferred
            end
        end
        local groups = {}
        for _, gain in ipairs(record.gains) do
            if matches(gain.character, gain.realm) then
                local quantity = gain.quantity - (gain.refunded or 0)
                if scoped then
                    result.gained = result.gained + quantity
                end
                result.methods[gain.method] = (result.methods[gain.method] or 0) + quantity
                V.addSource(groups, gain, quantity)
            end
            if pause then
                pause()
            end
        end
        for _, group in ipairs(V.sourceGroups(groups, pause)) do
            result.sources[group.label] = group.quantity
        end
        if initial then
            result.recorded = initial + result.gained
        end
        return result
    end

    function store.diagnostic(_self)
        if not supported then
            return {
                kind = "unsupported",
                damagedCount = 0,
                schema = type(kernel.raw()) == "table" and kernel.raw().schema or nil,
            }
        end
        local markerDamaged = kernel.raw().marker ~= nil
            and (not isName(kernel.raw().marker) or #kernel.raw().marker > 64)
        return {
            kind = (kernel.damagedCount > 0 or markerDamaged) and "damaged" or "healthy",
            damagedCount = kernel.damagedCount + (markerDamaged and 1 or 0),
            schema = CURRENT_SCHEMA,
        }
    end

    function store.marker(_self)
        return supported and isName(kernel.raw().marker) and #kernel.raw().marker <= 64 and kernel.raw().marker or nil
    end

    function store.environment(_self)
        if not supported or not validEnvironment(kernel.raw().environment) then
            return nil
        end
        local result = {}
        for key, value in pairs(kernel.raw().environment) do
            result[key] = value
        end
        return result
    end

    function store.list(_self)
        local result = {}
        for _, record in pairs(valid) do
            result[#result + 1] = copyRecord(record)
        end
        table.sort(result, function(left, right)
            return left.itemID < right.itemID or (left.itemID == right.itemID and left.key < right.key)
        end)
        return result
    end

    function store.count(_self)
        return kernel.count()
    end
    function store.revision(_self)
        return kernel.revision()
    end
    -- A stable-length cursor copies one record at a time. Consumers restart when
    -- the revision changes; no query can edit permanent records through it.
    function store.cursor(_self, pause)
        local index, count = 0, kernel.count()
        return function()
            index = index + 1
            if index <= count then
                return copyRecord(valid[kernel.keyAt(index)], false, pause)
            end
        end
    end

    function store.find(_self, key, pause)
        local record = valid[key]
        return record and copyRecord(record, false, pause) or nil
    end

    -- Activity rows need identity and current storage facts, not lifetime gains.
    function store.describe(_self, key)
        local record = valid[key]
        if not record then
            return nil
        end
        local result = copyRecord(record, true)
        result.gains, result.baseGains, result.gainEdits = nil, nil, nil
        return result
    end

    function store.tooltipFacts(_self, key)
        local facts = kernel.tooltip(key)
        if not facts then
            return nil
        end
        local methods = {}
        for method, count in pairs(facts.methods) do
            methods[method] = count > 0 or nil
        end
        local source = "Unknown"
        if not facts.sources.unknown then
            if facts.sourceCount > 1 then
                source = "Multiple"
            elseif facts.sourceCount == 1 then
                local group = facts.sources[facts.onlySource]
                local names, count = {}, 0
                for name in pairs(group.names) do
                    names[name], count = true, count + 1
                    if count == 2 then
                        break
                    end
                end
                source = V.sourceGroups({
                    [facts.onlySource] = {
                        key = facts.onlySource,
                        neutral = group.neutral,
                        quantity = group.quantity,
                        names = names,
                    },
                })[1].label
            end
        end
        return { methods = methods, hasGains = facts.count > 0, source = source }
    end

    function store.area(_self, character, realm, area)
        if not readable or not isName(character) or not isName(realm) or not areas[area] then
            return nil
        end
        local state = kernel.raw().areas[areaKey(character, realm, area)]
        if type(state) ~= "table" or not isInteger(state.seenAt) or type(state.complete) ~= "boolean" then
            return nil
        end
        return {
            seenAt = state.seenAt,
            complete = state.complete,
            lastCompleteAt = state.complete and state.seenAt
                or (isInteger(state.lastCompleteAt) and state.lastCompleteAt <= state.seenAt and state.lastCompleteAt)
                or nil,
        }
    end

    function store.characters(_self)
        local result = {}
        local seen = {}
        local function add(character, realm)
            local key = areaKey(character, realm, "")
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = { character = character, realm = realm }
            end
        end
        if readable then
            for _, state in pairs(kernel.raw().areas) do
                if type(state) == "table" and isName(state.character) and isName(state.realm) then
                    add(state.character, state.realm)
                end
            end
            for _, actor in pairs(kernel.actors()) do
                add(actor.character, actor.realm)
            end
        end
        table.sort(result, function(left, right)
            return left.realm < right.realm or (left.realm == right.realm and left.character < right.character)
        end)
        return result
    end

    function store.setMarker(_self, marker)
        if not readable or not isName(marker) or #marker > 64 then
            return false
        end
        saveFields({ marker = marker })
        return true
    end

    function store.setEnvironment(_self, environment)
        if not readable or not validEnvironment(environment) then
            return false
        end
        saveFields({ environment = environment })
        return true
    end
end

addon.StoreRecords = StoreRecords
