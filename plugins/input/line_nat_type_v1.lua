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

local function fileExists(file)
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
end

local function strip(str)
    return string.gsub(str, "^%s*(.-)%s*$", "%1")
end

local function readAllFile(filePath)
    local content = ""
    if fileExists(filePath) then
        local fh, _ = io.open(filePath, "r")
        if fh ~= nil then
            content = fh:read('*all')
            if (content ~= nil and string.len(content) ~= 0) then
                content = strip(content)
            end
            fh:close()
        end
    end
    return content
end

local function machineID()
    local dbusPath = "/var/lib/dbus/machine-id"
    local dbusPathEtc = "/etc/machine-id"
    local id = readAllFile(dbusPath)
    if string.len(id) == 0 then
        id = readAllFile(dbusPathEtc)
    end
    if string.len(id) == 0 then
        print("Can not read machine id")
        id = ""
    end
    print("Machine id: ", id)
    return id
end

local function lineNatType()
    local curTime = os.time()
    local natTable = {
        ["timestamp"] = curTime,
        ["line_nat_type"] = {}
    }
    local machineId = machineID()
    local natType = {}
    local cmd = "python3 /opt/quality/nattype_eth_lua.py --nat_type"
    local res = executeCmd(cmd)
    print(res)
    local resTable = split(res, "\n")
    local index = 1
    for _, v in pairs(resTable) do
        local devSplit = split(v, "#")
        if tableLen(devSplit) == 2 then
            --natType[devSplit[1]] = devSplit[2]

            local tags = {
                ["machine_id"] = machineId,
                ["name"] = devSplit[1],
            }

            local tmp_data = {
                ["tags"] = tags,
                ["fields"] = {
                    ["nat_type"] = tonumber(devSplit[2])
                }
            }
            natTable["line_nat_type"][index] = tmp_data
            index = index + 1
        end
    end
    for k ,v  in pairs(natTable) do
        print(k, v)
    end
    return natTable
end

lineNatType()
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
