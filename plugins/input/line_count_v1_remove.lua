-- Marking: lua,input,line_count,1

local input = {
    category = "input",
    name = "line_count",
    dataVersion = "1",
    indicator = "line_count"
}

local function executeCmd(cmd, timeout)
    if timeout == nil then
        timeout = 5
    end

    local result = ""
    local command = string.format("timeout %d %s ", timeout, cmd)
    local file = assert(io.popen(command, 'r'))
    if file == nil then
        print(string.format("Execute command (%s) failed", cmd))
        return nil
    end

    file:flush() -- > important to prevent receiving partial output
    local output = file:read("*all")
    file:close()
    if (output ~= nil and string.len(output) > 0) then
        result = string.gsub(output, "^%s*(.-)%s*$", "%1")
    end
    --print(output)
    return result
end



--lineCount()
--test pass
local function collect(out)
    local curTime = os.time()
    local devData = lineCount()
    local dataJson = jsonMarshal(devData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
