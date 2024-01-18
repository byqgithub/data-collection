-- Marking: lua,input,custom_id,1

local input = {
    category = "input",
    name = "custom_id",
    dataVersion = "1",
    indicator = "custom_id"
}

local function fileExists(path)
    local file, _ = io.open(path, "rb")
    if file then
        file:close()
    end
    return file ~= nil
end

--local function printTable(title ,value)
--    log:Debugf(title)
--    for k, v in pairs(value) do
--        log:Debugf("key: %s, value: %s", k, v)
--    end
--    log:Debugf("")
--end

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
    log:Debugf("executeCmd command: %s", command)
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

local function getTaskTag(configTable)
    local taskTags = {}
    local rootPath = configTable["plugin_root_path"]
    local folder = string.format("%s/../output", rootPath)
    local fileName = "runningTask.txt"
    local command = string.format(
            "flock -x -w 3 %s/file.lock -c 'cat %s/%s'",
            folder, folder, fileName)
    local result = executeCmd(command)
    if string.len(result) > 0 then
        taskTags = split(result, '\n')
    end

    log:Debugf("Get task tags: %s", taskTags)
    return taskTags
end

local function dcacheCustomId(pathArray)
    local customIdTable = {}
    for _, path in pairs(pathArray) do
        repeat
            if not fileExists(path) then
                break
            end

            local file = io.open(path, "r")
            if nil == file then
                log:Errorf("Failed to open %s", path)
                break
            end
            file:flush()
            local output = file:read('*all')
            file:close()
            if (output ~= nil and type(output) == "string" and string.len(output) > 0) then
                customIdTable["dcache"] = strip(output)
            end
        until true

        if string.len(customIdTable) > 0 then
            break
        end
    end

    return customIdTable
end

local function isPauseImage(info)
    local include = false
    local image = info["Config"]["Image"]
    log:Debugf("Container id: %v, image: %v", info["Id"], image)
    if image == nil or string.len(image) <= 0 then
        return include
    end

    local sections = split(image, "/")
    if tableLen(sections) <= 0 then
        return include
    end

    if string.find(sections[tableLen(sections)], "pause") then
        include = true
    end
    return include
end

local function getCIDBaseTask(taskName, containerInfoTable)
    local result = ""
    for cId, info in pairs(containerInfoTable) do
        repeat
            if isPauseImage(info) then
                break
            end

            if info["Config"] == nil then
                break
            end

            local envArray = info["Config"]["Env"]
            if envArray == nil then
                break
            end

            for _, value in pairs(envArray) do
                if string.match(value, "TASK_NAME") then
                    if string.match(value, taskName) then
                        result = cId
                        break
                    end
                end
            end
        until true

        if string.len(result) > 0 then
            break
        end
    end

    if string.len(result) <= 0 then
        result = taskName
    end

    return result
end

local function ksCustomId(pathConfig, containerInfoTable)
    local cId = getCIDBaseTask("ks", containerInfoTable)
    local customIdTable = {}
    local cmd = "ps --no-headers -fC ksp2p-server | grep worker | grep -v grep | awk '{print $2}'"
    local pid = executeCmd(cmd)
    if string.len(pid) <= 0 then
        return customId
    end

    local path = string.len("%s/%s/%s", "/proc", pid, "cmdline")
    if not fileExists(path) then
        return customId
    end

    local file = io.open(path, "r")
    if nil == file then
        log:Errorf("Failed to open %s", path)
        return customId
    end
    file:flush()
    local output = file:read('*all')
    file:close()

    if not string.find(output, "guid=") then
        return customId
    end

    for _, content in pairs(split(output, " ")) do
        if string.find(content, "guid=") then
            local tmp = split(content, "=")
            if tableLen(tmp) >= 2 then
                customIdTable[cId] = strip(tmp[2])
                break
            end
        end
    end

    return customIdTable
end

local function findCustomIdFile(pid, pathArray)
    local filePath = ""
    if pathArray == nil or tableLen(pathArray) <= 0 then
        return filePath
    end

    local bashPath = string.format("/proc/%s/root", pid)
    for _, path in pairs(pathArray) do
        filePath = string.len("%s/%s", bashPath, path)
        if fileExists(filePath) then
            break
        end
    end

    return filePath
end

local function readCustomId(pid, pathConfig, keyword)
    local customId = ""
    local filePath = findCustomIdFile(pid, pathConfig)
    if string.len(filePath) <= 0 then
        return customId
    end

    local file = io.open(filePath, "r")
    if nil == file then
        log:Errorf("Failed to open %s", path)
        return customId
    end
    file:flush()
    local output = file:read('*all')
    file:close()

    if string.len(keyword) > 0 then
        local sections = split(output, "\n")
        if tableLen(sections) <= 0 then
            return customId
        end

        for _, content in pairs(sections) do
            if string.find(content, keyword) then
                local tmp = split(content, keyword)
                if tableLen(tmp) == 1 then
                    customId = strip(tmp[1])
                    break
                end
            end
        end
    else
        customId = strip(output)
    end

    return customId
end

local function fetchFromContainerFS(pathConfig, containerInfoTable, keyword)
    local customIdTable = {}
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

            local customId = readCustomId(pid, pathConfig, keyword)
            if string.len(customId) > 0 then
               customIdTable[cId] = customId
            end
        until true
    end

    return customIdTable
end

local function fetchFromContainerEnv(pathConfig, containerInfoTable, keyword)
    local customIdTable = {}
    for cId, info in pairs(containerInfoTable) do
        repeat
            if isPauseImage(info) then
                break
            end

            if info["Config"] == nil then
                break
            end

            local envArray = info["Config"]["Env"]
            if envArray == nil then
                break
            end

            for _, value in pairs(envArray) do
                local tmpTable = split(value, "=")
                if tableLen(tmpTable) >= 2 then
                    if tmpTable[1] == keyword then
                        customIdTable[cId] = string.lower(strip(tmpTable[2]))
                    end
                end
            end
        until true
    end

    return customIdTable
end

local function getCustomId(taskTags, pathConfig)
    local output = {}
    local methodDict = {
        dcache = { func = dcacheCustomId, param = "" },
        ks = { func = ksCustomId, param = "" },
        bdfd = { func = fetchFromContainerFS, param = "guid=" },
        bdx = { func = fetchFromContainerFS, param = "guid=" },
        bdwphj = { func = fetchFromContainerFS, param = "" },
        bdr = { func = fetchFromContainerEnv, param = "RESOURCE_NAME" }
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

            output[taskName] = method["func"](pathConfig[taskName], infoTable, method["param"])
        until true
    end

    return output
end

function collect(out, configObject)
    local globalStr = configObject:ConfigRawContent("global")
    local globalConfig = jsonUnMarshal(globalStr)
    local pathConfigStr = configObject:ConfigRawContent("path_conf")
    local pathConfig = jsonUnMarshal(pathConfigStr)
    local customIdPathConfig = pathConfig["custom_id"]

    local taskTags = getTaskTag(globalConfig)
    local customIdTable = getCustomId(taskTags, customIdPathConfig)

    if tableLen(customIdTable) <= 0 then
        return
    end

    local curTime = os.time()
    local dataJson = jsonMarshal(customIdTable)
    if dataJson ~= nil and string.len(dataJson) > 0 then
        out:AddField(input.category, input.name, input.dataVersion,
                input.indicator, "", dataJson, curTime)
    end
end