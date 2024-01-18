-- Marking: lua,input,binging_device,1

local input = {
    category = "input",
    name = "binging_device",
    dataVersion = "1",
    indicator = "binging_device"
}

--local function fileExists(path)
--    local file, _ = io.open(path, "rb")
--    if file then
--        file:close()
--    end
--    return file ~= nil
--end

--local function printTable(title ,value)
--    log:Debug(title)
--    for k, v in pairs(value) do
--        log:Debugf("key: %s, value: %s", k, v)
--    end
--    log:Debug("")
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

local function fetchFromContainerEnv(containerInfoTable, keyword)
    local binding = {}
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
                        binding[cId] = string.lower(strip(tmpTable[2]))
                    end
                end
            end
        until true
    end

    return binding
end

local function getBindingDevice(taskTags)
    local output = {}
    local methodDict = {
        bdfd = { func = fetchFromContainerEnv, param = "LIBSOCKBIND_DEVICE" },
        bdwphj = { func = fetchFromContainerEnv, param = "LIBSOCKBIND_DEVICE" },
        bdx = { func = fetchFromContainerEnv, param = "NET_CARD" }
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

            output[taskName] = method["func"](infoTable, method["param"])
        until true
    end

    return output
end

function collect(out, configObject)
    local globalStr = configObject:ConfigRawContent("global")
    local globalConfig = jsonUnMarshal(globalStr)

    local taskTags = getTaskTag(globalConfig)
    local bingingDevice = getBindingDevice(taskTags)

    if tableLen(bingingDevice) <= 0 then
        return
    end

    local curTime = os.time()
    local dataJson = jsonMarshal(bingingDevice)
    if dataJson ~= nil and string.len(dataJson) > 0 then
        out:AddField(input.category, input.name, input.dataVersion,
                input.indicator, "", dataJson, curTime)
    end
end