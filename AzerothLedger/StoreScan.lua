local _, addon = ...

-- Possessions snapshots: observations, identity evidence and settlement of
-- pending loot, reward, vendor and exchange actions against measured change.

local V = addon.SchemaValidate
local areas, isInteger, validCheckID, isName, areaKey = V.areas, V.isInteger, V.validCheckID, V.isName, V.areaKey
local copyValue, validLootState, copyRecord = V.copyValue, V.validLootState, V.copyRecord
local validRewardState = V.validRewardState

local StoreScan = {}

function StoreScan.install(store, kernel, domains)
    local valid, readable, saveFields, heldKeys = kernel.valid, kernel.readable, kernel.save, kernel.heldKeys
    local checkedPossessions = kernel.checkedPossessions
    local evidenceState, retain = domains.evidence.state, domains.evidence.retain
    local activeSession, award = domains.loot.activeSession, domains.loot.award
    local rewardSessions, awardReward = domains.reward.sessions, domains.reward.award
    local choiceIsProven, openAccepted = domains.reward.choiceIsProven, domains.reward.openAccepted
    local vendorState, settleVendor = domains.vendor.state, domains.vendor.settle
    local exchangeState, settleExchange = domains.exchange.state, domains.exchange.settle

    ---@param snapshot AzerothLedgerSnapshot
    function store.scan(_self, snapshot)
        if
            not readable
            or type(snapshot) ~= "table"
            or not isName(snapshot.character)
            or not isName(snapshot.realm)
            or not areas[snapshot.area]
            or not isInteger(snapshot.seenAt)
            or snapshot.seenAt < 0
            or type(snapshot.complete) ~= "boolean"
            or type(snapshot.items) ~= "table"
        then
            return false
        end
        for _, item in ipairs(snapshot.items) do
            if
                type(item) ~= "table"
                or not isInteger(item.itemID)
                or item.itemID <= 0
                or not isInteger(item.quantity)
                or item.quantity <= 0
            then
                return false
            end
        end
        local priorScope = kernel.raw().areas[areaKey(snapshot.character, snapshot.realm, snapshot.area)]
        if type(priorScope) == "table" and not validCheckID(priorScope.checkID) then
            return false
        end
        if type(priorScope) == "table" and isInteger(priorScope.seenAt) and snapshot.seenAt < priorScope.seenAt then
            return false
        end
        if not store:expireEvidence(snapshot.seenAt) then
            return false
        end
        snapshot = copyValue(snapshot)
        local grouped = {}
        local evidence = evidenceState()
        if not evidence then
            return false
        end
        local unresolvedIdentity = false
        for _, item in ipairs(snapshot.items) do
            if
                type(item) ~= "table"
                or not isInteger(item.itemID)
                or item.itemID <= 0
                or not isInteger(item.quantity)
                or item.quantity <= 0
            then
                return false
            end
            local key = addon.Item.key(item.link, item.itemID)
            if not key then
                snapshot.complete = false
                local found = false
                for _, entry in ipairs(evidence.unresolved) do
                    if
                        entry.kind == "identity"
                        and entry.character == snapshot.character
                        and entry.realm == snapshot.realm
                        and entry.detail.area == snapshot.area
                        and entry.detail.location == item.location
                        and entry.detail.itemID == item.itemID
                        and entry.detail.quantity == item.quantity
                        and entry.detail.link == item.link
                    then
                        found = true
                    end
                end
                if not found then
                    retain(evidence, "identity", "unreadable", snapshot.seenAt, snapshot, {
                        itemID = item.itemID,
                        quantity = item.quantity,
                        link = item.link,
                        location = item.location,
                        area = snapshot.area,
                    })
                end
            else
                for index = #evidence.unresolved, 1, -1 do
                    local entry = evidence.unresolved[index]
                    if
                        entry.kind == "identity"
                        and entry.character == snapshot.character
                        and entry.realm == snapshot.realm
                        and entry.detail.area == snapshot.area
                        and item.location ~= nil
                        and entry.detail.location == item.location
                        and entry.at == snapshot.seenAt
                        and entry.detail.itemID == item.itemID
                        and entry.detail.quantity == item.quantity
                    then
                        table.remove(evidence.unresolved, index)
                        unresolvedIdentity = true
                    end
                end
                local group = grouped[key] or { itemID = item.itemID, quantity = 0, links = {} }
                group.quantity = group.quantity + item.quantity
                group.links[item.link] = true
                grouped[key] = group
            end
        end
        local scopeKey = areaKey(snapshot.character, snapshot.realm, snapshot.area)
        local oldScope = kernel.raw().areas[scopeKey]
        if type(oldScope) == "table" and isInteger(oldScope.seenAt) and snapshot.seenAt < oldScope.seenAt then
            return false
        end
        local nextRecords = {}
        local pendingLoot = kernel.raw().loot and validLootState(kernel.raw().loot) and copyValue(kernel.raw().loot)
            or nil
        local pendingRewards = kernel.raw().rewards
                and validRewardState(kernel.raw().rewards)
                and copyValue(kernel.raw().rewards)
            or nil
        local activeRewards = (snapshot.area == "bags" or snapshot.area == "equipped")
                and snapshot.complete
                and rewardSessions(snapshot.seenAt, pendingRewards)
            or {}
        local session = (snapshot.area == "bags" or snapshot.area == "equipped")
                and activeSession(snapshot.seenAt, pendingLoot)
            or nil
        if session and (session.character ~= snapshot.character or session.realm ~= snapshot.realm) then
            session = nil
        end
        for key, group in pairs(grouped) do
            local characterWasKnown = false
            local existingRecord = valid[key]
            if existingRecord then
                for _, seen in ipairs(existingRecord.characters) do
                    if seen.name == snapshot.character and seen.realm == snapshot.realm then
                        characterWasKnown = true
                        break
                    end
                end
            end
            if session and session.baselinePossessions and not characterWasKnown then
                session.discoveries[key] = true
            end
            if
                session
                and not session.baselineEquipmentUncertain
                and snapshot.area == "bags"
                and snapshot.complete
                and type(oldScope) == "table"
                and oldScope.complete
                and not unresolvedIdentity
            then
                -- Bags alone prove a lower bound when they exceed all pre-loot
                -- possessions, even if every previously equipped unit moved in.
                local baselineQuantity = session.baselinePossessions and (session.baselinePossessions[key] or 0)
                    or session.baselineQuantities[key]
                    or 0
                local increase = group.quantity - baselineQuantity
                if increase > 0 then
                    local credit = isInteger(session.credits[key]) and session.credits[key] or 0
                    session.credits[key] = math.max(credit, increase)
                    if not valid[key] then
                        session.discoveries[key] = true
                    end
                end
            end
            local record = valid[key] and copyRecord(valid[key], true)
                or {
                    key = key,
                    itemID = group.itemID,
                    firstSeen = snapshot.seenAt,
                    lastSeen = snapshot.seenAt,
                    firstSeenUnits = group.quantity,
                    -- An earlier complete check of this area proves these
                    -- units arrived later, even when nothing explains how.
                    firstSeenLater = type(oldScope) == "table" and oldScope.complete or nil,
                    totalGained = 0,
                    gains = {},
                    links = {},
                    characters = {},
                    observations = {},
                }
            if snapshot.seenAt > record.lastSeen then
                record.lastSeen = snapshot.seenAt
            end
            local seenLinks = {}
            for _, link in ipairs(record.links) do
                seenLinks[link] = true
            end
            for link in pairs(group.links) do
                if not seenLinks[link] then
                    record.links[#record.links + 1] = link
                end
            end
            table.sort(record.links)
            local characterFound, characterEntry = false, nil
            for _, character in ipairs(record.characters) do
                if character.name == snapshot.character and character.realm == snapshot.realm then
                    characterFound = true
                    characterEntry = character
                    if snapshot.seenAt > character.lastSeen then
                        character.lastSeen = snapshot.seenAt
                    end
                    break
                end
            end
            if not characterFound then
                characterEntry = {
                    name = snapshot.character,
                    realm = snapshot.realm,
                    firstSeen = snapshot.seenAt,
                    lastSeen = snapshot.seenAt,
                    firstSeenUnits = group.quantity,
                }
                record.characters[#record.characters + 1] = characterEntry
            end
            if session and session.discoveries[key] and not characterWasKnown then
                local gainID = tostring(session.id) .. ":" .. key
                for _, gain in ipairs(record.gains) do
                    if gain.id == gainID then
                        local firstSeenUnits = characterEntry and characterEntry.firstSeenUnits
                        if firstSeenUnits ~= nil then
                            characterEntry.firstSeenUnits =
                                math.max(0, firstSeenUnits - gain.quantity + (gain.refunded or 0))
                        end
                        break
                    end
                end
            end
            local previous
            for _, observation in ipairs(record.observations) do
                if
                    observation.character == snapshot.character
                    and observation.realm == snapshot.realm
                    and observation.area == snapshot.area
                then
                    previous = observation
                end
            end
            if not previous or previous.quantity ~= group.quantity then
                record.observations[#record.observations + 1] = {
                    character = snapshot.character,
                    realm = snapshot.realm,
                    area = snapshot.area,
                    quantity = group.quantity,
                    seenAt = snapshot.seenAt,
                }
            else
                previous.seenAt = snapshot.seenAt
            end
            nextRecords[key] = record
            if session and snapshot.area == "bags" and snapshot.complete then
                award(session, key, nextRecords, snapshot.seenAt, true)
            end
            if snapshot.area == "bags" and snapshot.complete and type(oldScope) == "table" and oldScope.complete then
                for _, reward in ipairs(activeRewards) do
                    if
                        reward.key == key
                        and not reward.questPreparationID
                        and reward.character == snapshot.character
                        and reward.realm == snapshot.realm
                        and choiceIsProven(reward, activeRewards, grouped)
                    then
                        awardReward(reward, key, group.quantity, nextRecords)
                    end
                end
            end
        end
        if snapshot.complete then
            for key in pairs(heldKeys(snapshot.character, snapshot.realm, snapshot.area)) do
                local existing = valid[key]
                if not grouped[key] then
                    local previous
                    for _, observation in ipairs(existing.observations) do
                        if
                            observation.character == snapshot.character
                            and observation.realm == snapshot.realm
                            and observation.area == snapshot.area
                        then
                            previous = observation
                        end
                    end
                    if previous and previous.quantity > 0 then
                        local record = copyRecord(existing, true)
                        record.observations[#record.observations + 1] = {
                            character = snapshot.character,
                            realm = snapshot.realm,
                            area = snapshot.area,
                            quantity = 0,
                            seenAt = snapshot.seenAt,
                        }
                        nextRecords[key] = record
                    end
                end
            end
        end
        local bagArea = store:area(snapshot.character, snapshot.realm, "bags")
        if
            snapshot.area == "equipped"
            and snapshot.complete
            and bagArea
            and bagArea.complete
            and bagArea.seenAt == snapshot.seenAt
        then
            -- The paired check follows the bag commit. Measure the whole
            -- possession change so equipping cannot hide or invent a gain.
            if session and session.baselinePossessions then
                local keys = {}
                for key in pairs(heldKeys(snapshot.character, snapshot.realm, "bags")) do
                    keys[key] = true
                end
                for key in pairs(grouped) do
                    keys[key] = true
                end
                for key in pairs(keys) do
                    local record = nextRecords[key] or valid[key]
                    local gear = grouped[key]
                    local quantity = checkedPossessions(record, snapshot.character, snapshot.realm, gear)
                    local increase = quantity - (session.baselinePossessions[key] or 0)
                    session.credits[key] = math.max(session.credits[key] or 0, increase)
                    award(session, key, nextRecords, snapshot.seenAt, true)
                end
            end
            if pendingRewards then
                local keys = {}
                for key in pairs(heldKeys(snapshot.character, snapshot.realm, "bags")) do
                    keys[key] = true
                end
                for key in pairs(grouped) do
                    keys[key] = true
                end
                for key in pairs(nextRecords) do
                    keys[key] = true
                end
                local opened = #pendingRewards.sessions
                local character, realm = snapshot.character, snapshot.realm
                openAccepted(pendingRewards, snapshot.seenAt, character, realm, function(key)
                    return checkedPossessions(nextRecords[key] or valid[key], character, realm, grouped[key])
                end, keys)
                for index = opened + 1, #pendingRewards.sessions do
                    activeRewards[#activeRewards + 1] = pendingRewards.sessions[index]
                end
            end
            local quantities = {}
            for _, reward in ipairs(activeRewards) do
                if reward.questPreparationID then
                    local record = nextRecords[reward.key] or valid[reward.key]
                    local equipped = grouped[reward.key]
                    quantities[reward.key] = {
                        quantity = checkedPossessions(record, snapshot.character, snapshot.realm, equipped),
                    }
                end
            end
            for _, reward in ipairs(activeRewards) do
                if
                    reward.questPreparationID
                    and reward.character == snapshot.character
                    and reward.realm == snapshot.realm
                    and choiceIsProven(reward, activeRewards, quantities)
                then
                    awardReward(reward, reward.key, quantities[reward.key].quantity, nextRecords)
                end
            end
        end
        local vendor = vendorState()
        if vendor and #vendor.actions == 0 then
            vendor = nil
        elseif vendor then
            vendor = copyValue(vendor)
        end
        if
            vendor
            and (snapshot.area == "bags" or snapshot.area == "equipped")
            and snapshot.complete
            and type(oldScope) == "table"
            and oldScope.complete
        then
            settleVendor(
                vendor,
                snapshot.area,
                snapshot.seenAt,
                snapshot.character,
                snapshot.realm,
                grouped,
                nextRecords
            )
        end
        local exchange = exchangeState()
        if exchange and #exchange.actions == 0 then
            exchange = nil
        elseif exchange then
            exchange = copyValue(exchange)
        end
        if snapshot.area == "bags" and snapshot.complete and type(oldScope) == "table" and oldScope.complete then
            settleExchange(exchange, snapshot, grouped, nextRecords)
        end
        local nextAreas = {}
        for key, state in pairs(kernel.raw().areas) do
            nextAreas[key] = state
        end
        local previousArea = store:area(snapshot.character, snapshot.realm, snapshot.area)
        nextAreas[scopeKey] = {
            seenAt = snapshot.seenAt,
            checkID = (type(oldScope) == "table" and oldScope.checkID or 0) + 1,
            complete = snapshot.complete,
            lastCompleteAt = snapshot.complete and snapshot.seenAt or (previousArea and previousArea.lastCompleteAt),
            character = snapshot.character,
            realm = snapshot.realm,
        }
        saveFields({
            records = nextRecords,
            areas = nextAreas,
            loot = pendingLoot,
            rewards = pendingRewards,
            vendor = vendor,
            exchange = exchange,
            evidence = evidence,
        })
        for key, record in pairs(nextRecords) do
            if valid[key] or grouped[key] then
                valid[key] = copyRecord(record, true)
            end
        end
        return true
    end
end

addon.StoreScan = StoreScan
