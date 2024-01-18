-- Marking: lua,input,line_nat_type,1

local input = {
    category = "input",
    name = "line_nat_type",
    dataVersion = "1",
    indicator = "line_nat_type"
}

local function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function (w)
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

local function tableLen(t)
    local len=0
    for _, _ in pairs(t) do
        len=len+1
    end
    return len;
end

local function executeCmd(cmd, timeout)

    local result = ""
    local command = string.format("%s ", cmd)
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

local function lineNatType()
    local natType = {}
    local cmd = "python3 /tmp/nattype_eth_lua.py --nat_type"
    local res = executeCmd(cmd)
    local resTable = split(res, "\n")
    for _, v in pairs(resTable) do
        local devSplit = split(v, "#")
        if tableLen(devSplit) == 2 then
            natType[devSplit[1]] = devSplit[2]
        end
    end
    --for k ,v  in pairs(natType) do
    --    print(k, v)
    --end
    return natType
end

--lineNatType()
--test pass

function collect(out)
    local curTime = os.time()
    local statData = lineNatType()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
