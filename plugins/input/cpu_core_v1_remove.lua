-- Marking: lua,input,cpu_core,1

local input = {
    category = "input",
    name = "cpu_core",
    dataVersion = "1",
    indicator = "cpu_core"
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

local function cpuCore()
    local curTime = os.time()
    local cpuTable = {
        ["timestamp"] = curTime,
        ["cpu_core"] = {}
    }
    local cmd = "cat /proc/cpuinfo | grep '^processor' | wc -l"
    local result = tonumber(executeCmd(cmd))
    local cpu_core = {
        ["fields"] = {
            ["cpu_core"] = result
        },
        ["tags"] = {
            ["machine_id"] = machineID()
        }
    }

    cpuTable["cpu_core"][1] = cpu_core
    cpuTable["timestamp"] = curTime
    return cpuTable
end

--cpuCore()
--test pass

function collect(out)
    local curTime = os.time()
    local devData = cpuCore()
    local dataJson = jsonMarshal(devData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
