local _, addon = ...

-- The saved mail, trade and guild bank state: what a valid action or intent
-- looks like, and when settled or canceled actions leave the save.

local V = addon.SchemaValidate
local isInteger, validCheckID, isName = V.isInteger, V.validCheckID, V.isName
local validPlaceKind = V.validPlaceKind
local Evidence = addon.StoreEvidence

local StoreExchangeState = {}

local exchangeStatuses = { pending = true, unresolved = true, settled = true, canceled = true }
local mailKinds = { ["return"] = true, ["auction-purchase"] = true, unresolved = true }

local function validChannel(channel)
    return channel == "mail" or channel == "trade" or channel == "guild"
end

local function validDirection(direction)
    return direction == "in" or direction == "out"
end

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
            or not validChannel(action.channel)
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
            or not validChannel(activity.channel)
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

local function activeAction(action)
    return action.status == "pending" or action.status == "unresolved"
end

local function validIntent(intent, actor)
    return Evidence.validItemAction(intent, actor)
        and validChannel(intent.channel)
        and validDirection(intent.direction)
        and (intent.peerName == nil or isName(intent.peerName))
        and (intent.peerRealm == nil or isName(intent.peerRealm))
        and validMailKind(intent)
end

StoreExchangeState.validChannel = validChannel
StoreExchangeState.validDirection = validDirection
StoreExchangeState.validMailKind = validMailKind
StoreExchangeState.validExchangeState = validExchangeState
StoreExchangeState.pruneExchange = pruneExchange
StoreExchangeState.activeAction = activeAction
StoreExchangeState.validIntent = validIntent

addon.StoreExchangeState = StoreExchangeState
