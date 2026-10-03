local _, addon = ...
local Work = {}

-- Lua 5.1 cannot yield from table.sort's C comparator. Merge in small steps
-- so sorting a finished 10,000-row index also respects the frame budget.
function Work.sort(rows, less, pause)
    if not pause then
        table.sort(rows, less)
        return
    end
    local width, count = 1, #rows
    local buffer = {}
    while width < count do
        for first = 1, count, width * 2 do
            local left, middle = first, math.min(first + width, count + 1)
            local right, finish = middle, math.min(first + width * 2 - 1, count)
            for target = first, finish do
                if left < middle and (right > finish or not less(rows[right], rows[left])) then
                    buffer[target], left = rows[left], left + 1
                else
                    buffer[target], right = rows[right], right + 1
                end
                pause()
            end
        end
        for index = 1, count do
            rows[index] = buffer[index]
            pause()
        end
        width = width * 2
    end
end

Work.timings = {}

local function profileClock(api)
    if type(api.debugprofilestop) == "function" then
        return api.debugprofilestop
    end
    if type(api.GetTimePreciseSec) == "function" then
        return function()
            return api.GetTimePreciseSec() * 1000
        end
    end
    return function()
        return 0
    end
end

function Work.measure(api, label, action)
    local clock = profileClock(api)
    local started = clock()
    local result = action()
    local duration = clock() - started
    local timing = Work.timings[label] or { frames = 0, maximum = 0, total = 0 }
    timing.frames, timing.total = timing.frames + 1, timing.total + duration
    timing.maximum = math.max(timing.maximum, duration)
    Work.timings[label] = timing
    return result
end

-- The profiling clock uses milliseconds. The operation cap still yields when
-- a clock is unavailable. One indivisible item operation can exceed the budget.
function Work.start(api, label, task)
    local clock = profileClock(api)
    local operationLimit = (type(api.debugprofilestop) == "function" or type(api.GetTimePreciseSec) == "function")
            and 4096
        or 256
    local thread = coroutine.create(function()
        return task(coroutine.yield)
    end)
    local job = { frames = 0, maximum = 0, total = 0 }
    function job:step()
        if self.done then
            return self.result
        end
        local started, operations = clock(), 0
        repeat
            local ok, value = coroutine.resume(thread)
            if not ok then
                error(value)
            end
            operations = operations + 1
            if coroutine.status(thread) == "dead" then
                self.done, self.result = true, value
                break
            end
        until operations >= operationLimit or clock() - started >= 2
        local duration = clock() - started
        self.frames, self.total = self.frames + 1, self.total + duration
        self.maximum = math.max(self.maximum, duration)
        Work.timings[label] = { frames = self.frames, total = self.total, maximum = self.maximum }
        return self.result
    end
    return job
end

addon.Work = Work
