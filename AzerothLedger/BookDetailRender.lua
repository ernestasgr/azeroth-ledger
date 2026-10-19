local _, addon = ...

-- Draws the selected item's detail panel: its header and counts, the detail
-- rows, the gear preview, and the review queue's evidence lines.
local Render = addon.BookRender
local Widgets = addon.BookWidgets
local State = addon.BookState
local Frame = addon.BookFrame
local colors = Widgets.colors
local stamp, exactQuantity, previewMessages = Render.stamp, Render.exactQuantity, Render.previewMessages

-- Lists the detail rows for an item as { kind, left, right, command } entries.
-- Commands are { "history", key }, { "sequence", sequence }; sections toggle.
function Render.detailLines(view, result, model, key)
    local lines = {}
    local function write(kind, left, right, command)
        lines[#lines + 1] = { kind = kind, left = left, right = right, command = command }
    end
    local developerMode = view.developerMode == true
    local record = model.record
    if view.filter.view == "Journal" then
        local activity
        for _, row in ipairs(result.rows) do
            if row.sequence == view.selectedSequence then
                activity = row
                break
            end
        end
        if activity then
            write("section", activity.action .. " ×" .. activity.quantity)
            write("date", "When", stamp(activity.at))
            write("note", activity.actors)
            if developerMode then
                write("note", "Recording details: " .. activity.evidence)
            end
            if activity.kind == "transfer" then
                write("note", "Moved between your characters. This does not count as a new gain.")
            end
            if activity.details then
                for _, gain in ipairs(activity.details) do
                    write("section", gain.method .. " ×" .. gain.quantity)
                    write("note", gain.actor)
                    write("date", "Time", stamp(gain.at))
                    write("note", "Place: " .. gain.place)
                    write("pair", "Character level", tostring(gain.level or "Unknown"))
                    write("note", "Source: " .. gain.source)
                end
                if activity.action == "Purchase" or activity.refunded > 0 then
                    write(
                        "note",
                        "Purchased "
                            .. activity.quantity
                            .. "; refunded "
                            .. activity.refunded
                            .. "; net gained "
                            .. activity.netQuantity
                            .. "."
                    )
                end
            else
                write("note", "Place: " .. activity.placeText)
                write("pair", "Character level", tostring(activity.level or "Unknown"))
                write("note", "Action: " .. activity.action)
                write("note", "From: " .. activity.sourceText)
            end
            local function related(sequence, label)
                local retained = sequence and result.bySequence[sequence]
                if retained then
                    write("action", label .. " • " .. stamp(retained.at), nil, { "sequence", sequence })
                else
                    write("note", label .. " is not in the recent Journal entries.")
                end
            end
            if activity.kind == "refund" then
                if activity.linkedGainID then
                    related(activity.purchaseSequence, "Linked purchase")
                else
                    write("note", "The matching purchase is not in the Journal.")
                end
            elseif activity.kind == "buyback" then
                if activity.linkedSaleID then
                    related(activity.saleSequence, "Linked sale")
                else
                    write("note", "The matching sale is not in the Journal.")
                end
            end
            for _, sequence in ipairs(activity.refundSequences or {}) do
                related(sequence, "Linked refund")
            end
        end
    else
        write("action", "View item history", nil, { "history", key })
    end
    write("note", "Older Journal entries expire; Collection totals stay.")
    local function breakdown(title, totals, emptyMessage, labelFor)
        write("section", title)
        local labels = {}
        for label, quantity in pairs(totals) do
            if quantity > 0 then
                labels[#labels + 1] = label
            end
        end
        table.sort(labels)
        if #labels == 0 then
            write("note", emptyMessage)
            return
        end
        for _, label in ipairs(labels) do
            write("pair", labelFor(label), tostring(totals[label]))
        end
    end
    breakdown("How you got it", model.breakdown.methods, "No confirmed gains in this view.", addon.LastSeen.methodLabel)
    breakdown(
        "Where it came from",
        model.breakdown.sources,
        "No source details recorded in this view.",
        addon.LastSeen.sourceLabel
    )
    write("section", "Item history")
    write("date", "First seen", stamp(model.firstSeen))
    write("date", "Last seen", stamp(model.lastSeen))
    write("date", "First confirmed gain", stamp(model.firstGained))
    write("date", "Last confirmed gain", stamp(model.lastGained))
    write("section", "Last checks")
    write("note", "Current count adds these saved checks, which can be from different times.")
    local lastCharacter
    local areas = { bags = "Bags", bank = "Bank", equipped = "Equipped" }
    for _, check in ipairs(model.checks) do
        local actor = check.character .. "-" .. check.realm
        if actor ~= lastCharacter then
            write("note", actor .. (not check.online and " • Offline; status Unknown" or ""))
            lastCharacter = actor
        end
        write(
            "pair",
            areas[check.area] .. " • Last found",
            check.observedQuantity ~= nil and tostring(check.observedQuantity) or "Unknown"
        )
        write("date", "Last seen", check.observedAt and stamp(check.observedAt) or "Not seen yet")
        write("pair", "Latest check", check.quantity ~= nil and tostring(check.quantity) or "Unknown")
        write("date", "Checked", check.at and stamp(check.at) or "Not checked yet")
    end
    if developerMode then
        write("section", "Developer details")
        write("note", "Internal item key: " .. record.key)
        write("note", "Evidence summary: " .. model.evidence)
        write("note", #model.links .. " item versions • " .. #record.links .. " saved links")
    end
    write("section", "Item versions")
    if #model.links > 1 then
        write("note", "Hover over versions to compare bonuses, enchants, and gems.")
    end
    if #record.links > #model.links then
        write(
            "note",
            #record.links
                .. " saved links represent "
                .. #model.links
                .. " distinct item "
                .. (#model.links == 1 and "version." or "versions.")
        )
    end
    for _, group in ipairs(model.links) do
        write("link", group.link)
    end
    return lines
end

function Render.evidenceLines(item)
    local lines = {
        item.name,
        item.action .. (item.quantity and (" ×" .. item.quantity) or " • quantity unknown"),
        item.character .. "-" .. item.realm,
        stamp(item.at),
        item.status,
        item.reason,
        item.nextStep,
        "Looking here will not confirm a gain or change your totals.",
    }
    if item.location then
        lines[#lines + 1] = "Where seen: " .. item.location
    end
    if item.link then
        lines[#lines + 1] = item.link
    end
    return lines
end

-- Drawing ---------------------------------------------------------------------------

function Render.preview(book)
    local view = book.view
    local record = view.selected and book.store:describe(view.selected)
    local selection =
        addon.Collection.gallerySelection(book.result, view.selected, record and record.links[view.previewIndex or 1])
    local link = selection and selection.link
    book.view = State.with(view, "previewIndex", selection and selection.index or 1)
    book.previewLink = link
    book.savedLink:SetText("Saved link " .. (book.view.previewIndex or 1) .. " of " .. (record and #record.links or 0))
    local status = addon.Client.previewStatus(book.api, link)
    Widgets.enable(book.preview, status == "ready")
    book.previewMessage:SetText(previewMessages[status])
end

function Render.previewResult(book, status)
    book.previewMessage:SetText(previewMessages[status])
end

---@param previous string|number|nil the evidence id shown before this selection
function Render.evidence(book, previous)
    local id = book.view.selectedEvidence
    local oldScroll = book.detailScroll:GetVerticalScroll()
    book.detailHeader:Hide()
    book.previewPanel:Hide()
    local index = book.result.positions[id]
    local item = index and book.result.rows[index]
    book.detailEmpty:SetShown(not item)
    book.detailScroll:SetShown(item ~= nil)
    Frame.detailArea(book, 16, 520)
    Frame.hideDetailRows(book)
    if not item then
        return
    end
    local lines = Render.evidenceLines(item)
    local y = 0
    for number, text in ipairs(lines) do
        local row = Frame.detailRow(book, number)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        y = y + row:presentLine(text, number == 1, item.link and number == #lines and item.link or nil)
    end
    Frame.finishDetails(book, y, previous == id, oldScroll)
end

local function header(book, model)
    local record = model.record
    local info = addon.Client.itemMetadata(book.api, record)
    local itemName = record.links[1]:match("%[([^%]]+)%]") or ("Item " .. record.itemID)
    book.itemTitle:SetText(itemName)
    Widgets.tint(book.itemTitle, Widgets.quality(book.api, info.quality))
    book.itemCategory:SetText(info.category .. "  •  " .. model.scopeLabel)
    Widgets.itemIcon(book.itemIcon, info.icon)
    book.itemLink = record.links[#record.links]
    local colour = colors[addon.LastSeen.ownership(model.ownershipState).colour]
    book.ownership:SetText("Status: " .. model.ownership)
    Widgets.tint(book.ownership, colour)
    Widgets.tint(book.ownershipDot, colour, true)
    book.characterOverall:SetText(exactQuantity(model.characterOverall))
    book.allCharactersOverall:SetText(exactQuantity(model.allCharactersOverall))
    book.characterCurrent:SetText(exactQuantity(model.characterCurrent))
    book.allCharactersCurrent:SetText(exactQuantity(model.allCharactersCurrent))
end

---@param previous string? the item key shown before this selection
function Render.details(book, previous, actions)
    local view = book.view
    local key = view.selected
    local oldScroll = book.detailScroll:GetVerticalScroll()
    local scope = { character = view.filter.character, realm = view.filter.realm }
    local model, pending = book.query:inspect(book.store, key, book.character, book.realm, scope)
    book.detailPending = pending
    book.detailEmpty:SetText(pending and "Loading item details…" or "Select an item to explore\nits history.")
    if pending then
        book.dirty = true
    end
    book.detailEmpty:SetShown(not model)
    book.detailHeader:SetShown(model ~= nil)
    book.detailScroll:SetShown(model ~= nil)
    local gallery = view.filter.view == "Gallery"
    book.previewPanel:SetShown(gallery and model ~= nil)
    Frame.detailArea(book, gallery and 292 or 208, gallery and 236 or Frame.DETAIL_HEIGHT)
    Frame.hideDetailRows(book)
    if not model then
        book.previewLink = nil
        return
    end
    if previous ~= key then
        Widgets.fade(book, book.detailHeader, 0.35, 0.65)
        Widgets.fade(book, book.detailScroll, 0.35, 0.65)
    end
    if gallery then
        Render.preview(book)
    end
    header(book, model)
    book.view = State.sections(book.view, State.detailIdentity(book.view, key))
    local collapsedSections = book.view.collapsedSections
    local index, y, sectionIndex, collapsed = 0, 0, 0, false
    for _, line in ipairs(Render.detailLines(book.view, book.result, model, key)) do
        index = index + 1
        local row = Frame.detailRow(book, index)
        if line.kind == "section" then
            sectionIndex = sectionIndex + 1
            collapsed = collapsedSections[sectionIndex] == true
            local sectionKey = sectionIndex
            row.onClick = function()
                actions.toggleSection(sectionKey)
            end
        elseif line.command then
            local command = line.command
            row.onClick = function()
                actions.command(command)
            end
        else
            row.onClick = nil
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        y = y + (row:present(line.kind, line.left, line.right, collapsed) or 0)
    end
    Frame.finishDetails(book, y, previous == key, oldScroll)
end
