local _, addon = ...

-- Items that come back to your characters through mail or the guild bank:
-- an alt's mail or deposit is a transfer, never a new gain.
local StoreTransfer = {}

-- Takes up to `quantity` units from your characters' earlier guild bank
-- deposits of this item on this realm, oldest first.
---@return integer own Units that were your deposits
---@return table? deposit The first deposit used, naming who made it
function StoreTransfer.guildDeposits(state, action, quantity)
    local own, first = 0, nil
    for _, deposit in ipairs(state.actions) do
        if own >= quantity then
            break
        end
        if
            deposit.status == "settled"
            and deposit.direction == "out"
            and deposit.channel == "guild"
            and deposit.key == action.key
            and deposit.realm == action.realm
            and deposit.at <= action.at
        then
            local take = math.min(deposit.quantity - (deposit.transferred or 0), quantity - own)
            if take > 0 then
                deposit.transferred = (deposit.transferred or 0) + take
                own = own + take
                first = first or deposit
            end
        end
    end
    return own, first
end

-- Journals units another of your characters sent, and moves them from the
-- recipient's first sighting: the delivering check may have counted them there.
function StoreTransfer.record(state, records, action, sender, quantity)
    state.journal[#state.journal + 1] = {
        id = action.id,
        key = action.key,
        channel = action.channel,
        quantity = quantity,
        at = action.at,
        sender = sender.character,
        senderRealm = sender.realm,
        recipient = action.character,
        recipientRealm = action.realm,
        level = action.level,
        place = action.place,
        placeKind = action.placeKind,
    }
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
end

-- The settled mail or trade one of your characters sent this recipient: whether
-- the sender is one of your characters, the matching outgoing action, and how
-- many outgoing actions match.
function StoreTransfer.altSender(state, action, quantity, characters)
    local senderKnown, ownSender, candidates = false, nil, 0
    for _, character in ipairs(characters) do
        if character.character == action.peerName and (not action.peerRealm or character.realm == action.peerRealm) then
            senderKnown = true
        end
    end
    if not senderKnown then
        return false, nil, 0
    end
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
            ownSender, candidates = outgoing, candidates + 1
        end
    end
    return senderKnown, ownSender, candidates
end

-- The mail this character sent that a returned mail brings back, and how many match.
function StoreTransfer.returnedMail(state, action, quantity)
    local returned, candidates = nil, 0
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
                or (action.peerName == action.character and (not action.peerRealm or action.peerRealm == action.realm))
            )
        then
            returned, candidates = outgoing, candidates + 1
        end
    end
    return returned, candidates
end

addon.StoreTransfer = StoreTransfer
