-- Marking: lua,input,ks_error_log,1

local input = {
    category = "input",
    name = "ks_error_log",
    dataVersion = "1",
    indicator = "ks_error_log"
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


local function dcacheErrorLog()
    local timestrings = ""
    local logFile = "/opt/soft/dcache/log/dcache.log"
    local errorCount = -2
    if not fileExists(logFile) then
        return errorCount
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
    return tonumber(errorCount)
end

local function ksErrorLog()
    local timestrings = ""
    local logFile = "ksp2p-server_*"
    local errorCount = -2
    local logcmd = "ps -ef | grep ksp2p-server::worker | grep -v grep | awk -F'log_path=' '{print $2}' | awk '{print $1}'"
    local logDir = executeCmd(logcmd)
    if logDir ~= "" then
        logFile = logDir .. '/' .. logFile
        for i = 1,5,1 do
            local t = (os.time() - (i * 60))
            local timestr = os.date("%Y-%m-%d %H:%M:", t)
            if i == 1 then
                timestrings = timestr
            else
                timestrings = timestrings .. "|" .. timestr
            end
        end
        local cmd=string.format("grep -E '%s' %s 2>/dev/null| grep -c '\[ERR\]'", timestrings, logFile)
        --print(cmd)
        errorCount = tonumber(executeCmd(cmd, 5))
    end
    return errorCount
end

local function parseLog()
    local curTime = os.time()
    local machineId = machineID()
    local result = {
        ["timestamp"] = curTime,
        ["error_log"] = {}
    }

    local error = {
        ["fields"] = {
            ["ks"] = ksErrorLog(),
            ["dcache"] = dcacheErrorLog()

        },
        ["tags"] = {
            ["machine_id"] = machineId
        }
    }
    result["error_log"][1] = error
    return result
end

--local test = parseLog()
--for k ,v in pairs(test) do
--    print(k, v )
--end

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