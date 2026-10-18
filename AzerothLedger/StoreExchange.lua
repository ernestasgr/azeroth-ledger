local _, addon = ...

-- Mail, trade and the guild bank: intents, confirmations, alt transfers and outside gains.

local V = addon.SchemaValidate
local isInteger, validCheckID, areaKey = V.isInteger, V.validCheckID, V.areaKey
local copyArray, copyValue = V.copyArray, V.copyValue
local Evidence = addon.StoreEvidence
local Transfer = addon.StoreTransfer

local StoreExchange = {}

local State = addon.StoreExchangeState
local validChannel, validDirection, validExchangeState =
    State.validChannel, State.validDirection, State.validExchangeState
local pruneExchange, activeAction, validIntent = State.pruneExchange, State.activeAction, State.validIntent

---@type AzerothLedgerSlice
StoreExchange.slice = { name = "exchange", validate = validExchangeState, journal = "transfers" }

-- Returns the correlation engine a possessions check and evidence expiry use.
function StoreExchange.install(store, kernel, slice)
    local valid, readable, saveFields, recordGain = kernel.valid, kernel.readable, kernel.save, kernel.recordGain
    local bagQuantity, characterGained = kernel.bagQuantity, kernel.characterGained
    local exchangeHealthy, savedState = slice.healthy, slice.state

    local function exchangeState()
        if savedState() == nil then
            return { nextID = 1, actions = {}, journal = {} }
        end
        return exchangeHealthy and savedState() or nil
    end

    local function exchangeIntent(intent, at, actor)
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

    ---@param confirmation {channel: 'mail'|'trade', direction: 'in'|'out', ids?: ALExIds}
    ---@param at integer
    ---@param actor AzerothLedgerActor
    local function exchangeConfirm(confirmation, at, actor)
        local channel, direction, ids = confirmation.channel, confirmation.direction, confirmation.ids
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

    local function exchangeCancel(channel, _, actor)
        local state = exchangeState()
        if not state then
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

    local function exchangeMarkUnresolved(id, _, actor)
        local state = exchangeState()
        if not state then
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

    -- Units from outside your characters: a player, the auction house or the guild.
    local function outside(action, record, quantity)
        local player = action.mailKind == nil and action.peerName and action.peerRealm
        return recordGain(record, {
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
            source = player and { kind = "player", name = action.peerName, realm = action.peerRealm } or nil,
        }, { discovery = action.discovery })
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
                    -- A guild bank deposit has no recipient to name.
                    if
                        (action.channel == "guild" or (action.peerName and action.peerRealm))
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
                        local senderKnown, ownSender, senderCandidates =
                            Transfer.altSender(state, action, quantity, playerExchange and store:characters() or {})
                        if action.mailKind == "return" then
                            local returned, returnCandidates = Transfer.returnedMail(state, action, quantity)
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
                        elseif playerExchange and not action.peerName and action.channel ~= "guild" then
                            action.status = "unresolved"
                        elseif action.channel == "guild" then
                            local own, deposit = Transfer.guildDeposits(state, action, quantity)
                            if own > 0 and deposit.character ~= action.character then
                                Transfer.record(state, records, action, deposit, own)
                            end
                            if own < quantity then
                                records[action.key] = outside(action, records[action.key] or record, quantity - own)
                            elseif deposit.character == action.character then
                                action.isReturn = true
                            else
                                action.isTransfer = true
                            end
                            action.quantity = quantity
                            action.status = "settled"
                        elseif ownSender and senderCandidates == 1 then
                            ownSender.transferred = (ownSender.transferred or 0) + quantity
                            action.peerRealm = ownSender.realm
                            action.isTransfer = true
                            Transfer.record(state, records, action, ownSender, quantity)
                            action.quantity = quantity
                            action.status = "settled"
                        elseif senderKnown then
                            action.status = "unresolved"
                        else
                            records[action.key] = outside(action, record, quantity)
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

    return {
        engine = { stale = stale, expire = expire, visit = visit, check = check },
        ---@type table<string, AzerothLedgerCommand>
        commands = {
            exchangeIntent = { valid = validIntent, run = exchangeIntent, cost = 1 },
            exchangeConfirm = {
                valid = function(confirmation)
                    return type(confirmation) == "table"
                        and validChannel(confirmation.channel)
                        and validDirection(confirmation.direction)
                end,
                run = exchangeConfirm,
            },
            exchangeCancel = { valid = validChannel, run = exchangeCancel },
            exchangeMarkUnresolved = { valid = isInteger, run = exchangeMarkUnresolved },
        },
    }
end

addon.StoreExchange = StoreExchange
