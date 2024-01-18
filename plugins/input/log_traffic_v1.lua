-- Marking: lua,input,log_traffic,1

local input = {
    category = "input",
    name = "log_traffic",
    dataVersion = "1",
    indicator = "log_traffic"
}

local function fileExists(path)
    local file, _ = io.open(path, "rb")
    if file then
        file:close()
    end
    return file ~= nil
end

local function split(str,reps)
    local resultStrList = {}
    if str == nil or type(str) ~= "string" then
        return resultStrList
    end

    string.gsub(str,'[^'..reps..']+',function (w)
        table.insert(resultStrList, w)
    end)
    return resultStrList
end

local function strip(str)
    if str == nil or type(str) ~= "string" then
        return ""
    end

    return string.gsub(str, "^%s*(.-)%s*$", "%1")
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
        timeout = 5  -- default timeout: 5s
    end

    local result = ""
    local command = string.format("%s ", cmd)
    log:Debugf("executeCmd command: %v", command)
    local file = io.popen(command)
    if nil == file then
        log:Errorf("Execute command (%s) failed", cmd)
        return result
    end
    file:flush()  -- > important to prevent receiving partial output
    local output = file:read('*all')
    file:close()
    if (output ~= nil and type(output) == "string" and string.len(output) > 0) then
        result = strip(output)
    end

    return result
end

local function getTimeArray()
    local cur = os.time()
    local timeArray = {}
    for i=0, 4, 1 do
        cur = cur - i * 60
        table.insert(timeArray, cur)
    end

    return timeArray
end

local function getLastLines(logPath, num)
    local result = {}
    if not fileExists(logPath) then
        return result
    end

    num = tonumber(num)
    local blkSizeMax = 4096
    local fh, _ = io.open(logPath, "r")
    if fh == nil then
        return result
    end

    fh.seek("end")
    fh:close()
end

local function parseDcacheLog(keyword, timeArray, logPath)
    local result = {}
    if not fileExists(logPath) then
        return result
    end

    for _, timestamp in pairs(timeArray) do
        prefix = os.date("%y-%m-%d %H:%M:", timestamp)
    end
end

local function parseLcacheLog()

end

local function dcacheLogTraffic()
    local cmd = "python3 /opt/quality/get_dcache_logflow.py --tasklogflow"
    local logTraffic = executeCmd(cmd)
    if (logTraffic ~= nil and type(logTraffic) == "string" and string.len(logTraffic) > 0) then
        local tmp = tonumber(logTraffic)
        if (tmp ~= nil and type(tmp) == "number") then
            return {dcache = tmp}
        end
    end
    return 0
end

local function bzLogTraffic()
    local cmd = "cat /data/app/portal_pin/logs/portal_pin.log|awk '{if($4==\"incoming\" && $6==\"outgoing\")print$2,$5,$7}'|tail -n10 | awk '{b+=$3}END{printf \"%.f\",b*8/10}'"
    local logTraffic = executeCmd(cmd)
    if (logTraffic ~= nil and type(logTraffic) == "string" and string.len(logTraffic) > 0) then
        local tmp = tonumber(logTraffic)
        if (tmp ~= nil and type(tmp) == "number") then
            return {bz = tmp}
        end
    end
    return 0
end

local function isPauseImage(info)
    local include = false
    log:Debugf("Container id: %s, image: %s", info["Id"], info["Image"])
    if info["Image"] == nil or string.len(info["Image"]) <= 0 then
        return include
    end

    local sections = split(info["Image"], "/")
    if tableLen(sections) <= 0 then
        return include
    end

    if string.find(sections[tableLen(sections)], "pause") then
        include = true
    end
    return include
end

local function parseContainerInfo(containerInfoTable)
    local pidMap = {}
    for cId, info in pairs(containerInfoTable) do
        repeat
            if isPauseImage(info) then
                break
            end

            if info["State"] == nil then
                break
            end

            local pid = info["State"]["Pid"]
            if pid == nil then
                break
            end

            pidMap[cId] = pid
        until true
    end

    return pidMap
end

local function findLogFile(pid, pathArray)
    local filePathArray = {}
    if pathArray == nil or tableLen(pathArray) <= 0 then
        return filePathArray
    end

    local filePath = ""
    local bashPath = string.format("/proc/%s/root", pid)
    for _, path in pairs(pathArray) do
        filePath = string.len("%s/%s", bashPath, path)
        if fileExists(filePath) then
            break
        end
    end

    if string.len(filePath) > 0 then
        local suffix = os.date("%y%m%d%H", os.time() - 3600)
        local fileName = string.format("%s/%s", filePath, "popmachine.log")
        local historyFile = string.format("%s.%s", fileName, suffix)
        if fileExists(fileName) then
            table.insert(filePathArray, fileName)
        end
        if fileExists(historyFile) then
            table.insert(filePathArray, historyFile)
        end
    end

    return filePathArray
end

local function findTaskLogFile(pidMap, pathConfig)
    local logMap = {}
    for cId, pid in pairs(pidMap) do
        local fileArray = findLogFile(pid, pathConfig)
        log:Debugf("Container id %v, pid: %v, log file: %v", cId, pid, fileArray)
        logMap[cId] = fileArray
    end
    return logMap
end

local function parseTrafficInLog(filePath, timeRange, parseFunction, ...)
    local traffic = 0
    if string.len(filePath) <= 0 then
        return traffic
    end

    local file = io.open(filePath, "r")
    if nil == file then
        log:Errorf("Failed to open %s", path)
        return customId
    end
    file:flush()
    local output = file:read('*all')
    file:close()

    if parseFunction == nil or output == nil or string.len(output) <= 0 then
        return traffic
    end

    local sections = split(output, "\n")
    if sections == nil or tableLen(sections) <= 0 then
        return traffic
    end

    return parseFunction(sections, timeRange, ...)
end

local function bdwphjParseLog(sections, timeRange, dataArray)
    for _, content in pairs(sections) do
        if string.find(content, "[") and string.find(content, "flow stat") then
            local timeStr = split(strip(split(content, "[")[1]), ".")[1]
            local _, _, y, m, d, hour, min, sec = string.find(timeStr,
                    "(%d+)-(%d+)-(%d+)%s*(%d+):(%d+):(%d+)")
            local timestamp = os.time({year=y, month = m, day = d,
                                       hour = hour, min = min, sec = sec})
            if timeRange[1] <= timestamp and timeRange[2] >= timestamp then
                if string.find(content, "upload=") and
                        string.find(content, "B|") then
                    log:Debugf("flow log: %s", content)
                    local info = split(line, "upload=")[1]
                    local one = tonumber(split(info, "B|")[1])
                    local two = tonumber(split(split(info, "B|")[2], "B")[1])
                    table.insert(dataArray, one + two)
                end
            end
        end
    end
end

local function bdwphjLogTraffic(pathConfig, containersInfo)
    local cur = os.time()
    local timeRange = {cur - 60 * 5 - 10, cur}
    local pidMap = parseContainerInfo(containersInfo)
    local logMap = findTaskLogFile(pidMap, pathConfig)
    local trafficMap = {}
    for cId, logArray in pairs(logMap) do
        local dataArray = {}
        for _, file in pairs(logArray) do
            parseTrafficInLog(file, timeRange, bdwphjParseLog, dataArray)
        end
        local traffic = 0
        for _, data in pairs(dataArray) do
            traffic = traffic + data
        end
        trafficMap[cId] = traffic * 8 / (len(dataArray) * 5 * 60)
    end
    return trafficMap
end

local function getTaskTag(configTable)
    local taskTags = {}
    local rootPath = configTable["plugin_root_path"]
    local folder = string.format("%s/../output", rootPath)
    local fileName = "runningTask.txt"
    local command = string.format(
            "flock -x -w 3 %s/file.lock -c 'cat %s/%s'",
            folder, folder, fileName)
    local result = executeCmd(command)
    if result ~= nil and type(result) == "string" and string.len(result) > 0 then
        taskTags = split(result, '\n')
    end

    log:Debugf("Get task tags: %s", taskTags)
    return taskTags
end

local function getLogTraffic(taskTags, logPathConfig)
    local output = {}
    local methodDict = {
        dcache = { func = dcacheLogTraffic, param = "" },
        bdwphj = { func = bdwphjLogTraffic, param = "" },
        bz = { func = bzLogTraffic, param = "" }
    }

    local infoStr = containersInfo()
    local infoTable = jsonUnMarshal(infoStr)

    for _, taskTag in pairs(taskTags) do
        repeat
            if not string.find(taskTag, "-") then
                break
            end

            local taskName = ""
            local sections = split(taskTags, "-")
            if tableLen(sections) < 3 then
                break
            end

            taskName = sections[2]
            local method = methodDict[taskName]
            if method == nil then
                break
            end

            output[taskName] = method["func"](logPathConfig[taskName], infoTable)
        until true
    end

    return output
end

function collect(out, configObject)
    local globalStr = configObject:ConfigRawContent("global")
    local globalConfig = jsonUnMarshal(globalStr)
    local pathConfigStr = configObject:ConfigRawContent("path_conf")
    local pathConfig = jsonUnMarshal(pathConfigStr)
    local logPathConfig = pathConfig["log"]

    local taskTags = getTaskTag(globalConfig)
    local logTraffic = getLogTraffic(taskTags, logPathConfig)

    if tableLen(logTraffic) <= 0 then
        return
    end

    local curTime = os.time()
    local dataJson = jsonMarshal(logTraffic)
    if dataJson ~= nil and string.len(dataJson) > 0 then
        out:AddField(input.category, input.name, input.dataVersion,
                input.indicator, "", dataJson, curTime)
    end
end