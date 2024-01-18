-- Marking: lua,input,task_identify,1

-- template: pai-taskName-index, no index, default 0

local input = {
    category = "input",
    name = "task_identify",
    dataVersion = "1",
    indicator = "task_identify"
}

local function fileExists(path)
    local file, _ = io.open(path, "rb")
    if file then
        file:close()
    end
    return file ~= nil
end

--local function printFormat(format, ...)
--    log:Debugf(format, ...)
--end
--
--local function printTable(title ,value)
--    log:Debug(title)
--    for k, v in pairs(value) do
--        log:Debugf("key: %s, value: %s", k, v)
--    end
--    log:Debug("")
--end

local function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function (w)
        table.insert(resultStrList, w)
    end)
    return resultStrList
end

local function strip(str)
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
    local command = string.format("timeout %v %s ", timeout, cmd)
    local file = assert(io.popen(command))
    if nil == file then
        log:Errorf("Execute command (%s) failed", cmd)
        return nil
    end
    file:flush()  -- > important to prevent receiving partial output
    local output = file:read('*all')
    file:close()
    if (output ~= nil and string.len(output) > 0) then
        result = string.gsub(output, "^%s*(.-)%s*$", "%1")
    end

    return result
end

local function getTaskFromSpecialFile(filePath)
    local taskTag = ""
    if fileExists(filePath) then
        -- log:Debugf("%s exist", filePath)
        local fh, _ = io.open(filePath, "r")
        if fh ~= nil then
            for line in fh:lines() do
                -- log:Debugf("file content %v", line)
                if (line ~= nil and string.len(line) ~= 0) then
                    --local content = strip(line)
                    --taskTag = string.format("pai-%s-0", content)
                    taskTag = strip(line)
                    break
                end
            end
            fh:close()
        end
    end
    return taskTag
end

local function getTaskFromPlanTaskFile()
    return getTaskFromSpecialFile("/etc/paitask")
end

local function getTaskFromHostname()
    local taskTag = ""
    local taskArray = {}
    local isBz = false
    local isVOD = false
    local isLive = false
    local hostname = executeCmd("hostnamectl | grep \"Static hostname\"")
    log:Debugf("Local hostname: %v", hostname)
    for word in string.gmatch(hostname, "%a+") do
        if word == "mcdn" then isBz = true end
        if word == "v" then isVOD = true end
        if word == "live" or word == "plive" then isLive = true end
    end

    if isBz and isVOD then
        --taskTag = "pai-bz-0"
        taskTag = "bz"
    elseif (isBz and isLive) then
        --taskTag = "pai-bzl-0"
        taskTag = "bzl"
    else
        taskTag = ""
    end

    if string.len(taskTag) > 0 then
        table.insert(taskArray, taskTag)
    end
    --if tableLen(split(taskTag, "-")) == 3 then
    --    table.insert(taskArray, taskTag)
    --end

    return taskArray
end

local function getTaskBaseCommand(configTable)
    local taskTag = ""
    local taskArray = {}
    for name, cmd in pairs(configTable) do
        local taskName = strip(name)
        if (string.len(taskName) > 0 and string.find(taskName, "num") == nil) then
            local output = tonumber(executeCmd(cmd))
            local keyword = string.format("%s_num", taskName)
            local num = tonumber(configTable[keyword])
            log:Debugf("Cmd %v, output %v, num %v", cmd, output, num)
            if (num ~= nil and output ~= nil) then
                if output >= num then
                    --taskTag = string.format("pai-%s-0", string.lower(taskName))
                    taskTag = string.lower(taskName)
                    break
                end
            end
        end
    end

    if string.len(taskTag) > 0 then
        table.insert(taskArray, taskTag)
    end
    --if tableLen(split(taskTag, "-")) == 3 then
    --    table.insert(taskArray, taskTag)
    --end

    return taskArray
end

local function getTaskFromProcessName(configTable)
    return getTaskBaseCommand(configTable["process"])
end

local function getTaskFromContainerName(configTable)
    return getTaskBaseCommand(configTable["docker"])
end

local function getTaskFromContainerInfo()
    local taskArray = {}
    local infoStr = containersInfo()
    local infoTable = jsonUnMarshal(infoStr)
    for _, containerInfo in pairs(infoTable) do
        repeat
            if containerInfo["Name"] ~= nil then
                log:Debugf("containerInfo name: %v", containerInfo["Name"])
                if containerInfo["Name"] == "/ipes-lcache" then
                    --table.insert(taskArray, "pai-dcache-0")
                    table.insert(taskArray, "dcache")
                    break
                end
            end

            if containerInfo["Config"] == nil then
                break
            end

            local envArray = containerInfo["Config"]["Env"]
            if envArray == nil then
                break
            end

            for _, value in pairs(envArray) do
                local tmpTable = split(value, "=")
                if tableLen(tmpTable) >= 2 then
                    if tmpTable[1] == "PAI_TASK_NAME" then
                        local tag = string.lower(strip(tmpTable[2]))
                        local tagArray = split(tag, "-")
                        if tableLen(tagArray) == 3 then
                            table.insert(taskArray, tagArray[2])
                        end
                        --table.insert(taskArray, tag)
                        break
                    elseif tmpTable[1] == "TASK_NAME" then
                        local tag = string.lower(strip(tmpTable[2]))
                        --tag = string.format("pai-%s-0", tag)
                        table.insert(taskArray, tag)
                        break
                    end
                end
            end
        until true
    end

    return taskArray
end

local function getTaskTag(configTable)
    local taskArray = {}
    taskArray = getTaskFromHostname()
    log:Debugf("Get task from hostname: %v", taskArray)

    if tableLen(taskArray) <= 0 then
        taskArray = getTaskFromProcessName(configTable)
        log:Debugf("Get task from process name: %v", taskArray)
    end

    if tableLen(taskArray) <= 0 then
        taskArray = getTaskFromContainerName(configTable)
        log:Debugf("Get task from container name: %v", taskArray)
    end

    if tableLen(taskArray) <= 0 then
        taskArray = getTaskFromContainerInfo()
        log:Debugf("Get task from container info: %v", taskArray)
    end

    return taskArray
end

local function matchPlanTask(configTable)
    local taskArray = {}
    local specialTaskArray = configTable["specific"]
    local taskTag = getTaskFromPlanTaskFile()
    log:Debugf("plan task file content: %+v", taskTag)
    for _, name in pairs(specialTaskArray) do
        if taskTag == name then
            table.insert(taskArray, taskTag)
            return taskArray
        end
    end
    --local tmpTable = split(taskTag, "-")
    --if tableLen(tmpTable) == 3 then
    --    local taskName = tmpTable[2]
    --    for _, name in pairs(specialTaskArray) do
    --        if taskName == name then
    --            table.insert(taskArray, taskTag)
    --            return taskArray
    --        end
    --    end
    --end
    return taskArray
end

local function writeFile(configTable, taskArray)
    local taskString = ""
    local rootPath = configTable["plugin_root_path"]
    local folder = string.format("%s/../output", rootPath)
    local fileName = "runningTask.txt"
    for _, task in pairs(taskArray) do
        taskString = taskString .. string.format("%s\n", task)
    end

    local _ = os.execute(string.format("mkdir -p %s", folder))
    local command = string.format(
            "flock -x -w 3 %s/file.lock -c 'echo \"%s\" > %s/%s'",
            folder, taskString, folder, fileName)
    local cmdResult = os.execute(command)
    log:Debugf("Write running task %s to file %s/%s", taskString, folder, fileName)
    --log:Debugf("Cmd execute result %s", cmdResult)
end

local function arrayDeDuplicate(taskArray)
    local deDuplicated = {}
    local cache = {}

    for _, task in pairs(taskArray) do
        cache[task] = string.format("pai-%s-0", task)
    end

    for _, value in pairs(cache) do
        table.insert(deDuplicated, value)
    end

    return deDuplicated
end

function collect(out, configObject)
    local globalString = configObject:ConfigRawContent("global")
    local globalConfig = jsonUnMarshal(globalString)
    local recognitionString = configObject:ConfigRawContent("recognition")
    local configTable = jsonUnMarshal(recognitionString)

    local taskArray = {}
    taskArray = matchPlanTask(configTable)
    log:Debugf("Match plan task: %v", taskArray)

    if tableLen(taskArray) <= 0 then
        taskArray = getTaskTag(configTable)
    end

    if tableLen(taskArray) <= 0 then
        log:Info("Can not identify task")
        taskArray = {}
    else
        taskArray = arrayDeDuplicate(taskArray)
        log:Debugf("DeDuplicate task tag: %v", taskArray)
    end

    writeFile(globalConfig, taskArray)


    --table.insert(taskArray, "1")
    --table.insert(taskArray, { "2", "3" })
    --log:Debugf("Array: %v, type \"%T\"", taskArray, taskArray)
    --log:Debugf("Array element 1: %v, type \"%T\"", taskArray[1], taskArray[1])
    --log:Debugf("Array element 2: %v, type \"%T\"", taskArray[2], taskArray[2])
    --
    --taskArray = {}
    --taskArray["one"] = 1
    --taskArray["two"] = { "2", "3" }
    --log:Debugf("Map: %v, type \"%T\"", taskArray, taskArray)
    --
    --taskArray = {}
    --table.insert(taskArray, { "1", 2 })
    --table.insert(taskArray, { "3", { ip = "4", v = { version = 1.1 } } })
    --table.insert(taskArray, { map5 = 2.2 })
    --log:Debugf("Map: %v, type \"%T\"", taskArray, taskArray)

    --local cmd = "ps --no-headers -fC deliSvr | wc -l"
    --local output = 0
    --local num = 0.1
    --log:Debugf("Cmd %v, type \"%T\", output %v, type \"%T\", num %v, type \"%T\"",
    --        cmd, cmd, output, output, num, num)
    --
    --log:Errorf("Cmd %v, output %v, num %v", cmd, output, num)
    --log:Debugf("Cmd %v, output %v, num %v", cmd, output, num)
    --log:Warnf("Cmd %v, output %v, num %v", cmd, output, num)
    --log:Infof("Cmd %v, output %v, num %v", cmd, output, num)
    --
    --log:Error("Cmd %v, output %v, num %v")
    --log:Debug("Cmd %v, output %v, num %v")
    --log:Warn("Cmd %v, output %v, num %v")
    --log:Info("Cmd %v, output %v, num %v")
end
