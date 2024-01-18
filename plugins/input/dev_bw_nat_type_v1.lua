-- Marking: lua,input,bw_nat_type,1

local input = {
    category = "input",
    name = "bw_nat_type",
    dataVersion = "1",
    indicator = "bw_nat_type"
}

local function executeCmd(cmd, timeout)
    if timeout == nil then
        timeout = 60
    end

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

local function bwNatType()
    local curTime = os.time()
    --local machineId = machineID()
    local bwNat = {
        ["timestamp"] = curTime,
        ["bw_nat_type"] = nil
    }

    local cmd = "python3 /opt/quality/nattype.py"

    --local bw_nat_type = {
    --    ["fields"] = {
    --        ["bw_nat_type"] = tonumber(executeCmd(cmd))
    --    },
    --    ["tags"] = {
    --        ["machine_id"] = machineId
    --    }
    --}

    bwNat["bw_nat_type"] = tonumber(executeCmd(cmd))
    --for k, v in pairs(bwNat) do
    --    print(k, v)
    --end
    return bwNat
end

--bwNatType()
--test pass

function collect(out)
    local curTime = os.time()
    local statData = bwNatType()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end

