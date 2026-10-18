-- Native frame port for Book interaction specs: a client api whose item info and
-- server time a spec controls through `ui.ready` and `ui.time`, and helpers that
-- find and click visible controls by their text.
return function()
    local native = assert(loadfile("tests/support/native_ui.lua"))().create({
        rejectedTextures = { ["Interface\\Icons\\INV_Misc_Food_14"] = true },
    })
    local ui = { native = native, api = native.api, controls = native.controls, ready = true, time = 100000 }
    local api = ui.api
    api.GetServerTime = function()
        return ui.time
    end
    api.IsControlKeyDown = function()
        return true
    end
    api.C_Item = {
        GetItemInfo = function(link)
            if not ui.ready then
                return nil
            end
            local id = tonumber(link:match("item:(%d+)"))
            return "Name",
                link,
                1,
                nil,
                nil,
                nil,
                nil,
                nil,
                nil,
                "Interface\\Icons\\INV_Misc_Food_14",
                nil,
                id == 2672 and 7 or 2
        end,
    }

    function ui.find(text, kind)
        for index = #ui.controls, 1, -1 do
            local control = ui.controls[index]
            if control.text == text and control:IsVisible() and (not kind or control.kind == kind) then
                return control
            end
        end
        error("Missing visible control: " .. text)
    end

    function ui.click(text)
        ui.find(text, "Button"):Click()
    end

    return ui
end
