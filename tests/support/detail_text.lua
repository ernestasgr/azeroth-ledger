-- Renders an item's Book detail rows as "left: right" lines, as a player reads them.
-- Specs load the addon through BookRender and pass an inspect model.
return function(addon, model, developerMode)
    local view = { filter = {}, developerMode = developerMode }
    local text = {}
    for _, line in ipairs(addon.BookRender.detailLines(view, { rows = {} }, model, model.record.key)) do
        text[#text + 1] = (line.left or "") .. (line.right and (": " .. line.right) or "")
    end
    return table.concat(text, "\n")
end
