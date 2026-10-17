local _, addon = ...

-- Mail and trade: intents, confirmations, alt transfers and outside gains.

local V = addon.SchemaValidate
local isInteger, validCheckID, isName, areaKey = V.isInteger, V.validCheckID, V.isName, V.areaKey
local copyArray, copyValue, validPlaceKind = V.copyArray, V.copyValue, V.validPlaceKind
local Evidence = addon.StoreEvidence

local StoreExchange = {}

local exchangeStatuses = { pending = true, unresolved = true, settled = true, canceled = true }
local mailKinds = { ["return"] = true, ["auction-purchase"] = true, unresolved = true }

local function validMailKind(intent)
    return intent.mailKind == nil
        or (intent.channel == "mail" and intent.direction == "in" and mailKinds[intent.mailKind] == true)
end

local function validTransferred(action)
    local transferred = action.transferred
    return transferred == nil or (isInteger(transferred) and transferred >= 0 and transferred <= action.quantity)
end

local function validExchangeState(exchange)
    if
        type(exchange) ~= "table"
        or not isInteger(exchange.nextID)
        or type(exchange.actions) ~= "table"
        or type(exchange.journal) ~= "table"
    then
        return false
    end
    local ids = {}
    for _, action in ipairs(exchange.actions) do
        if
            type(action) ~= "table"
            or not isInteger(action.id)
            or action.id < 1
            or action.id >= exchange.nextID
            or ids[action.id]
            or (action.channel ~= "mail" and action.channel ~= "trade")
            or (action.direction ~= "in" and action.direction ~= "out")
            or type(action.key) ~= "string"
            or not isInteger(action.itemID)
            or addon.Item.key(action.link, action.itemID) ~= action.key
            or not isInteger(action.quantity)
            or action.quantity < 1
            or not isInteger(action.at)
            or not isName(action.character)
            or not isName(action.realm)
            or not isInteger(action.level)
            or type(action.place) ~= "string"
            or not isInteger(action.baseline)
            or action.baseline < 0
            or not isInteger(action.baselineGained)
            or action.baselineGained < 0
            or type(action.discovery) ~= "boolean"
            or type(action.confirmed) ~= "boolean"
            or not exchangeStatuses[action.status]
            or (action.peerName ~= nil and not isName(action.peerName))
            or (action.peerRealm ~= nil and not isName(action.peerRealm))
            or not validTransferred(action)
            or not validCheckID(action.baselineCheckID)
            or (action.isTransfer ~= nil and type(action.isTransfer) ~= "boolean")
            or (action.isReturn ~= nil and type(action.isReturn) ~= "boolean")
            or not validMailKind(action)
        then
            return false
        end
        ids[action.id] = true
    end
    for _, activity in ipairs(exchange.journal) do
        if
            type(activity) ~= "table"
            or not isInteger(activity.id)
            or type(activity.key) ~= "string"
            or (activity.channel ~= "mail" and activity.channel ~= "trade")
            or not isInteger(activity.quantity)
            or activity.quantity < 1
            or not isInteger(activity.at)
            or not isName(activity.sender)
            or not isName(activity.senderRealm)
            or not isName(activity.recipient)
            or not isName(activity.recipientRealm)
            or (activity.level ~= nil and not isInteger(activity.level))
            or (activity.place ~= nil and type(activity.place) ~= "string")
            or not validPlaceKind(activity.placeKind)
        then
            return false
        end
    end
    return true
end

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

---@type AzerothLedgerSlice
StoreExchange.slice = { name = "exchange", validate = validExchangeState, journal = "transfers" }

local function activeAction(action)
    return action.status == "pending" or action.status == "unresolved"
end

-- Returns the correlation engine a possessions check and evidence expiry use.
function StoreExchange.install(store, kernel, slice)
    local valid, readable, saveFields, gainRecord = kernel.valid, kernel.readable, kernel.save, kernel.gain
    local bagQuantity, characterGained = kernel.bagQuantity, kernel.characterGained
    local exchangeHealthy, savedState = slice.healthy, slice.state

    local function exchangeState()
        if savedState() == nil then
            return { nextID = 1, actions = {}, journal = {} }
        end
        return exchangeHealthy and savedState() or nil
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
        local scope = kernel.area(areaKey(actor.character, actor.realm, "bags"))
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
            local scope = kernel.area(group.scopeKey)
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
                            -- The delivering check may have counted these units as the
                            -- recipient's first sighting; they came from the sender.
                            local received = records[action.key]
                            for index, seen in ipairs(received and received.characters or {}) do
                                if seen.name == action.character and seen.realm == action.realm then
                                    if seen.firstSeen >= action.at and seen.firstSeenUnits > 0 then
                                        local moved = math.min(seen.firstSeenUnits, quantity)
                                        local copy = {}
                                        for field, value in pairs(seen) do
                                            copy[field] = value
                                        end
                                        copy.firstSeenUnits = seen.firstSeenUnits - moved
                                        copy.transferredUnits = (seen.transferredUnits or 0) + moved
                                        received.characters[index] = copy
                                    end
                                    break
                                end
                            end
                            action.quantity = quantity
                            action.status = "settled"
                        elseif senderKnown then
                            action.status = "unresolved"
                        else
                            records[action.key] = gainRecord(record, {
                                id = "exchange:" .. action.id .. ":" .. action.key,
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
                            }, { discovery = action.discovery })
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

    local function healthyState()
        return savedState() and exchangeHealthy and savedState() or nil
    end

    local function stale(at)
        local state = healthyState()
        return Evidence.staleEntries(state and state.actions, at, activeAction)
    end

    local function expire(at, reason, retain)
        local original = healthyState()
        if type(original) ~= "table" then
            return nil, false
        end
        local state = copyValue(original)
        local changed = Evidence.expireEntries(state.actions, at, reason, activeAction, function(entry, openedAt)
            retain("exchange", reason, openedAt, entry, entry)
        end)
        return state, changed
    end

    local function visit(emit, pause)
        local state = healthyState()
        if not readable or not state then
            return
        end
        for _, entry in ipairs(state.actions) do
            if activeAction(entry) then
                local stopped = entry.status == "unresolved" and not entry.confirmed
                emit("exchange:" .. entry.id, "exchange", stopped and "stopped" or "active", entry.at, entry, entry)
            end
            pause()
        end
    end

    -- Settles mail and trade against a complete bag check after a complete one.
    ---@param scan AzerothLedgerCheck
    local function check(scan)
        local snapshot, oldScope = scan.snapshot, scan.oldScope
        local handler, exchange = {}, nil
        function handler.finish()
            exchange = exchangeState()
            if exchange and #exchange.actions == 0 then
                exchange = nil
            elseif exchange then
                exchange = copyValue(exchange)
            end
            if snapshot.area == "bags" and snapshot.complete and type(oldScope) == "table" and oldScope.complete then
                settleExchange(exchange, snapshot, scan.grouped, scan.records)
            end
        end
        function handler.commit(fields)
            fields.exchange = exchange
        end
        return handler
    end

    return { engine = { stale = stale, expire = expire, visit = visit, check = check } }
end

addon.StoreExchange = StoreExchange
