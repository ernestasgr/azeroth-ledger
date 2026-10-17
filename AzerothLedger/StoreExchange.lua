local _, addon = ...

-- Mail and trade: intents, confirmations, alt transfers and outside gains.

local V = addon.SchemaValidate
local isInteger, validCheckID, isName, areaKey = V.isInteger, V.validCheckID, V.isName, V.areaKey
local copyArray, validPlaceKind, validMailKind = V.copyArray, V.validPlaceKind, V.validMailKind

local StoreExchange = {}

local function pruneExchange(state, at)
    for index = #state.actions, 1, -1 do
        local action = state.actions[index]
        local age = at - action.at
        if
            age > 31 * 86400
            or (
                age >= 60
                and (
                    action.status == "canceled"
                    or (
                        action.status == "settled"
                        and (action.direction == "in" or action.transferred == action.quantity)
                    )
                )
            )
        then
            table.remove(state.actions, index)
        end
    end
end

-- Returns the state accessor and settlement a possessions scan uses.
function StoreExchange.install(store, kernel)
    local valid, readable, saveFields, editGainRoot = kernel.valid, kernel.readable, kernel.save, kernel.editGainRoot
    local bagQuantity, characterGained = kernel.bagQuantity, kernel.characterGained
    local exchangeHealthy = kernel.exchangeHealthy

    local function exchangeState()
        if kernel.raw().exchange == nil then
            return { nextID = 1, actions = {}, journal = {} }
        end
        return exchangeHealthy and kernel.raw().exchange or nil
    end

    function store.exchangeIntent(_self, intent, at, actor)
        if
            not readable
            or type(intent) ~= "table"
            or (intent.channel ~= "mail" and intent.channel ~= "trade")
            or (intent.direction ~= "in" and intent.direction ~= "out")
            or not isInteger(intent.itemID)
            or intent.itemID < 1
            or addon.Item.key(intent.link, intent.itemID) ~= intent.key
            or not isInteger(intent.quantity)
            or intent.quantity < 1
            or (intent.peerName ~= nil and not isName(intent.peerName))
            or (intent.peerRealm ~= nil and not isName(intent.peerRealm))
            or not validMailKind(intent)
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
            or not isInteger(actor.level)
            or type(actor.place) ~= "string"
            or not validPlaceKind(actor.placeKind)
        then
            return false
        end
        local scope = kernel.raw().areas[areaKey(actor.character, actor.realm, "bags")]
        local state = exchangeState()
        if not state or type(scope) ~= "table" or not scope.complete or not validCheckID(scope.checkID) then
            return false
        end
        pruneExchange(state, at)
        local record = valid[intent.key]
        state.actions[#state.actions + 1] = {
            id = state.nextID,
            channel = intent.channel,
            direction = intent.direction,
            key = intent.key,
            itemID = intent.itemID,
            link = intent.link,
            quantity = intent.quantity,
            peerName = intent.peerName,
            peerRealm = intent.peerRealm,
            mailKind = intent.mailKind,
            at = at,
            character = actor.character,
            realm = actor.realm,
            level = actor.level,
            place = actor.place,
            placeKind = actor.placeKind,
            baseline = bagQuantity(record, actor.character, actor.realm),
            baselineGained = characterGained(record, actor.character, actor.realm),
            baselineCheckID = scope.checkID,
            discovery = record == nil,
            confirmed = false,
            status = "pending",
        }
        local id = state.nextID
        state.nextID = id + 1
        saveFields({ exchange = state })
        return id
    end

    function store.exchangeConfirm(_self, channel, direction, at, actor, ids)
        if
            not readable
            or (channel ~= "mail" and channel ~= "trade")
            or (direction ~= "in" and direction ~= "out")
            or not isInteger(at)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        if not store:expireEvidence(at) then
            return false
        end
        local state = exchangeState()
        if not state then
            return false
        end
        local changed = false
        for _, action in ipairs(state.actions) do
            if
                action.status == "pending"
                and not action.confirmed
                and action.channel == channel
                and action.direction == direction
                and action.character == actor.character
                and action.realm == actor.realm
                and at >= action.at
                and at - action.at < 60
                and (ids == nil or ids == action.id or (type(ids) == "table" and ids[action.id]))
            then
                action.confirmed = true
                changed = true
            end
        end
        if changed then
            saveFields({ exchange = state })
        end
        return changed
    end

    function store.exchangeCancel(_self, channel, actor)
        local state = exchangeState()
        if
            not readable
            or not state
            or (channel ~= "mail" and channel ~= "trade")
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        local changed = false
        for _, action in ipairs(state.actions) do
            if
                action.channel == channel
                and action.character == actor.character
                and action.realm == actor.realm
                and action.status ~= "settled"
                and action.status ~= "canceled"
            then
                action.status = "canceled"
                changed = true
            end
        end
        if changed then
            saveFields({ exchange = state })
        end
        return changed
    end

    function store.exchangeMarkUnresolved(_self, id, actor)
        local state = exchangeState()
        if
            not readable
            or not state
            or not isInteger(id)
            or type(actor) ~= "table"
            or not isName(actor.character)
            or not isName(actor.realm)
        then
            return false
        end
        for _, action in ipairs(state.actions) do
            if
                action.id == id
                and (action.status == "pending" or action.status == "unresolved")
                and action.character == actor.character
                and action.realm == actor.realm
            then
                action.status = "unresolved"
                action.confirmed = false
                saveFields({ exchange = state })
                return true
            end
        end
        return false
    end

    function store.exchangeActivity(_self)
        local state = exchangeState()
        return state and copyArray(state.journal) or {}
    end

    -- Completion signals can arrive before possessions. Adapters keep these
    -- actions separate until every selected unit has actually been measured.
    function store.mailProgress(_self, ids)
        local state = exchangeState()
        if not state or type(ids) ~= "table" or not next(ids) then
            return "ended"
        end
        local remaining, groups = {}, {}
        for id in pairs(ids) do
            remaining[id] = true
        end
        for _, action in ipairs(state.actions) do
            if remaining[action.id] and action.confirmed and action.channel == "mail" and action.direction == "in" then
                local scopeKey = areaKey(action.character, action.realm, "bags")
                local groupKey = table.concat({
                    scopeKey,
                    action.key,
                    action.baseline,
                    action.baselineGained,
                    tostring(action.baselineCheckID),
                }, "\031")
                local group = groups[groupKey]
                    or {
                        scopeKey = scopeKey,
                        key = action.key,
                        character = action.character,
                        realm = action.realm,
                        baseline = action.baseline,
                        baselineGained = action.baselineGained,
                        baselineCheckID = action.baselineCheckID,
                        quantity = 0,
                        at = action.at,
                    }
                groups[groupKey] = group
                group.quantity = group.quantity + action.quantity
                group.at = math.max(group.at, action.at)
                remaining[action.id] = nil
            end
        end
        if next(remaining) then
            return "ended"
        end
        for _, group in pairs(groups) do
            -- Earlier settled takes sharing this baseline already occupy part
            -- of the increase; a later attachment cannot reuse those units.
            for _, action in ipairs(state.actions) do
                if
                    not ids[action.id]
                    and action.status == "settled"
                    and action.direction == "in"
                    and action.key == group.key
                    and action.character == group.character
                    and action.realm == group.realm
                    and action.baseline == group.baseline
                    and action.baselineGained == group.baselineGained
                    and action.baselineCheckID == group.baselineCheckID
                then
                    group.quantity = group.quantity + action.quantity
                end
            end
            local scope = kernel.raw().areas[group.scopeKey]
            if
                not scope
                or not scope.complete
                or scope.seenAt < group.at
                or bagQuantity(valid[group.key], group.character, group.realm) < group.baseline + group.quantity
            then
                return "waiting"
            end
        end
        return "measured"
    end

    function store.exchangeUnresolved(_self)
        local state = exchangeState()
        local result = {}
        for _, action in ipairs(state and state.actions or {}) do
            if action.status == "unresolved" then
                local copy = {}
                for key, value in pairs(action) do
                    copy[key] = value
                end
                result[#result + 1] = copy
            end
        end
        return result
    end

    local function settleExchange(state, snapshot, grouped, records)
        if not state or snapshot.area ~= "bags" or not snapshot.complete then
            return
        end
        pruneExchange(state, snapshot.seenAt)
        for _, action in ipairs(state.actions) do
            if
                action.confirmed
                and (action.status == "pending" or action.status == "unresolved")
                and action.character == snapshot.character
                and action.realm == snapshot.realm
                and snapshot.seenAt >= action.at
                and snapshot.seenAt - action.at < 60
            then
                local group = grouped[action.key]
                local current = group and group.quantity or 0
                local delta = current - action.baseline
                if action.direction == "out" then
                    local reserved = 0
                    for _, prior in ipairs(state.actions) do
                        if
                            prior.id < action.id
                            and prior.status == "settled"
                            and prior.direction == "out"
                            and prior.key == action.key
                            and prior.character == action.character
                            and prior.realm == action.realm
                            and prior.baseline == action.baseline
                            and prior.baselineCheckID == action.baselineCheckID
                        then
                            reserved = reserved + prior.quantity
                        end
                    end
                    if
                        action.peerName
                        and action.peerRealm
                        and action.baseline >= action.quantity + reserved
                        and -delta >= action.quantity + reserved
                    then
                        action.status = "settled"
                    else
                        action.status = "unresolved"
                    end
                elseif delta > 0 then
                    local record = records[action.key] or valid[action.key]
                    local otherGains =
                        math.max(0, characterGained(record, action.character, action.realm) - action.baselineGained)
                    local reserved = 0
                    for _, prior in ipairs(state.actions) do
                        if
                            prior.id < action.id
                            and prior.status == "settled"
                            and (prior.isTransfer or prior.isReturn)
                            and prior.key == action.key
                            and prior.character == action.character
                            and prior.realm == action.realm
                            and prior.baseline == action.baseline
                            and prior.baselineCheckID == action.baselineCheckID
                        then
                            reserved = reserved + prior.quantity
                        end
                    end
                    local quantity = math.min(action.quantity, delta - otherGains - reserved)
                    -- A removed mail attachment is a whole stack. A partial
                    -- possessions update cannot identify its completed quantity.
                    if action.channel == "mail" and quantity < action.quantity then
                        action.status = "unresolved"
                    elseif quantity > 0 and record then
                        local playerExchange = action.mailKind == nil
                        local ownSender
                        local senderCandidates = 0
                        local senderKnown = false
                        for _, character in ipairs(playerExchange and store:characters() or {}) do
                            if
                                character.character == action.peerName
                                and (not action.peerRealm or character.realm == action.peerRealm)
                            then
                                senderKnown = true
                            end
                        end
                        if senderKnown then
                            for _, outgoing in ipairs(state.actions) do
                                if
                                    outgoing.status == "settled"
                                    and outgoing.direction == "out"
                                    and outgoing.channel == action.channel
                                    and outgoing.key == action.key
                                    and outgoing.quantity - (outgoing.transferred or 0) >= quantity
                                    and outgoing.character == action.peerName
                                    and (not action.peerRealm or outgoing.realm == action.peerRealm)
                                    and outgoing.peerName == action.character
                                    and outgoing.peerRealm == action.realm
                                then
                                    ownSender = outgoing
                                    senderCandidates = senderCandidates + 1
                                end
                            end
                        end
                        if action.mailKind == "return" then
                            local returned, returnCandidates = nil, 0
                            for _, outgoing in ipairs(state.actions) do
                                if
                                    outgoing.status == "settled"
                                    and outgoing.direction == "out"
                                    and outgoing.channel == "mail"
                                    and outgoing.key == action.key
                                    and outgoing.character == action.character
                                    and outgoing.realm == action.realm
                                    and outgoing.at <= action.at
                                    and outgoing.quantity - (outgoing.transferred or 0) >= quantity
                                    and (
                                        (
                                            action.peerName == outgoing.peerName
                                            and (not action.peerRealm or action.peerRealm == outgoing.peerRealm)
                                        )
                                        or (
                                            action.peerName == action.character
                                            and (not action.peerRealm or action.peerRealm == action.realm)
                                        )
                                    )
                                then
                                    returned, returnCandidates = outgoing, returnCandidates + 1
                                end
                            end
                            if returned and returnCandidates == 1 then
                                returned.transferred = (returned.transferred or 0) + quantity
                                action.isReturn = true
                                action.quantity = quantity
                                action.status = "settled"
                            else
                                action.status = "unresolved"
                            end
                        elseif action.mailKind == "unresolved" then
                            action.status = "unresolved"
                        elseif playerExchange and not action.peerName then
                            action.status = "unresolved"
                        elseif ownSender and senderCandidates == 1 then
                            ownSender.transferred = (ownSender.transferred or 0) + quantity
                            action.peerRealm = ownSender.realm
                            action.isTransfer = true
                            state.journal[#state.journal + 1] = {
                                id = action.id,
                                key = action.key,
                                channel = action.channel,
                                quantity = quantity,
                                at = action.at,
                                sender = ownSender.character,
                                senderRealm = ownSender.realm,
                                recipient = action.character,
                                recipientRealm = action.realm,
                                level = action.level,
                                place = action.place,
                                placeKind = action.placeKind,
                            }
                            action.quantity = quantity
                            action.status = "settled"
                        elseif senderKnown then
                            action.status = "unresolved"
                        else
                            local gainID = "exchange:" .. action.id .. ":" .. action.key
                            record = editGainRoot(record, gainID)
                            local gain = {
                                id = gainID,
                                at = action.at,
                                quantity = quantity,
                                character = action.character,
                                realm = action.realm,
                                level = action.level,
                                place = action.place,
                                placeKind = action.placeKind,
                                method = "Obtained",
                                mailKind = action.mailKind,
                                channel = action.channel,
                                source = playerExchange and action.peerName and action.peerRealm and {
                                    kind = "player",
                                    name = action.peerName,
                                    realm = action.peerRealm,
                                } or nil,
                            }
                            record.gains[#record.gains + 1] = gain
                            record.totalGained = record.totalGained + quantity
                            record.firstGained = record.firstGained and math.min(record.firstGained, action.at)
                                or action.at
                            record.lastGained = record.lastGained and math.max(record.lastGained, action.at)
                                or action.at
                            if action.discovery then
                                record.evidencedDiscovery = true
                                record.firstSeenUnits = math.max(0, record.firstSeenUnits - quantity)
                                for _, seen in ipairs(record.characters) do
                                    if seen.name == action.character and seen.realm == action.realm then
                                        seen.firstSeenUnits = math.max(0, seen.firstSeenUnits - quantity)
                                        break
                                    end
                                end
                            end
                            records[action.key] = record
                            action.quantity = quantity
                            action.status = "settled"
                        end
                    else
                        action.status = "unresolved"
                    end
                else
                    action.status = "unresolved"
                end
            end
        end
    end

    return { state = exchangeState, settle = settleExchange }
end

addon.StoreExchange = StoreExchange
