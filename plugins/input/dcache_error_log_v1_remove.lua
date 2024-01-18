-- Marking: lua,input,dcache_error_log,1

local input = {
    category = "input",
    name = "dcache_error_log",
    dataVersion = "1",
    indicator = "dcache_error_log"
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

local function parseLog()
    local curTime = os.time()
    local machineId = machineID()
    local result = {
        ["timestamp"] = curTime,
        ["dcache_error"] = {}
    }

    local dcache_error = {
        ["fields"] = {
            ["dcache_error"] = -2
        },
        ["tags"] = {
            ["machine_id"] = machineId
        }
    }

    local timestrings = ""
    local logFile = "/opt/soft/dcache/log/dcache.log"
    local errorCount = -2
    if not fileExists(logFile) then

        result["dcache_error"][1] = dcache_error
        return result
    end
    for i = 1,5,1 do
        local t = (os.time() - (i * 60))
        local timestr = os.date("%Y-%m-%d %H:%M:", t)
        if i == 1 then
            timestrings = timestr
        else
            timestrings = timestrings .. "|" .. timestr
        end
    end
    local cmd=string.format("grep -E '%s' %s | grep -c 'ERROR'", timestrings, logFile)
    errorCount = executeCmd(cmd, 5)

    dcache_error["fields"]["dcache_error"] = tonumber(errorCount)
    result["dcache_error"][1] = dcache_error
    return result
end

--local test = parseLog()
--for k ,v in pairs(test) do
--    print(k, v )
--end

--parseLog()
--test pass

function collect(out)
    local curTime = os.time()
    local statData = parseLog()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
