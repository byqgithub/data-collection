-- Marking: lua,input,disk_system_size,1

local input = {
    category = "input",
    name = "disk_system_size",
    dataVersion = "1",
    indicator = "disk_system_size"
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

local function systemSize()
    local curTime = os.time()
    local diskSystem = {
        ["timestamp"] = curTime,
        ["disk_system"] = {}
    }
    local disk_system = {
        ["fields"] = {},
        ["tags"] = {
            ["machine_id"] = machineID()
        }
    }
    local cmd = "df -a | grep -w '/' | awk '{printf\"%d#%d\", $2, $3}'"
    local systemDisk = executeCmd(cmd)
    local systemDiskSplit = split(systemDisk, "#")
    if tableLen(systemDiskSplit) == 2 then
        local tmp = {
            ["size"] = tonumber(systemDiskSplit[1]),
            ["usage"] = tonumber(systemDiskSplit[2] / systemDiskSplit[1] * 100)
        }
        disk_system["fields"] = tmp
        diskSystem["disk_system"][1] = disk_system
    end

    for k,v in pairs(diskSystem) do
        print(k, v)
    end
    return diskSystem
end

--systemSize()
--test pass

function collect(out)
    local curTime = os.time()
    local memData = systemSize()
    --for key, data in pairs(memData)
    --do
    --    print("input plugin: ", key, data)
    --end
    local dataJson = jsonMarshal(memData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
