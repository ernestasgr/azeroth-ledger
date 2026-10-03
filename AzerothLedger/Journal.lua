local _, addon = ...
local Journal = {}

local function actor(name, realm)
    return name and (name .. (realm and ("-" .. realm) or "")) or "Unknown character"
end

local function source(gain)
    if gain.source then
        return gain.source.name and actor(gain.source.name, gain.source.realm) or "Unnamed " .. gain.source.kind
    end
    if gain.context then
        return gain.context.name or (gain.context.kind .. " " .. gain.context.id)
    end
    return "Unknown source"
end

---@param store ALStore
---@param search? string
---@return table[]
function Journal.query(store, search)
    local result = {}
    search = (search or ""):lower()
    for _, row in ipairs(store:journal()) do
        local record = store:find(row.key)
        row.link = record and record.links[#record.links] or nil
        row.name = row.link and row.link:match("%[([^%]]+)%]") or "Unknown item"
        if row.category == "gain" then
            local first = row.contributions[1]
            row.quantity, row.refunded = 0, 0
            row.actors = actor(first.character, first.realm)
            row.action = first.method == "Vendor" and "Purchase" or first.method
            local evidence, seen = {}, {}
            for _, gain in ipairs(row.contributions) do
                row.quantity = row.quantity + gain.quantity
                row.refunded = row.refunded + (gain.refunded or 0)
                local label = gain.method .. ": " .. source(gain)
                if not seen[label] then
                    evidence[#evidence + 1], seen[label] = label, true
                end
            end
            table.sort(evidence)
            row.evidence = "Matched item gain; " .. table.concat(evidence, "; ")
        elseif row.category == "transfer" then
            row.actors = actor(row.sender, row.senderRealm) .. " → " .. actor(row.recipient, row.recipientRealm)
            row.action = row.channel == "mail" and "Alt mail" or "Alt trade"
            row.evidence = "Confirmed send and matching receipt; no external gain"
        else
            row.actors = actor(row.character, row.realm)
            row.action = ({ sale = "Sale", refund = "Refund", buyback = "Buyback" })[row.kind]
            row.evidence = "Matched vendor action; " .. (row.vendorName or "Unknown vendor")
        end
        if
            (row.name .. " " .. row.actors .. " " .. row.action .. " " .. row.evidence):lower():find(search, 1, true)
        then
            result[#result + 1] = row
        end
    end
    return result
end

addon.Journal = Journal
