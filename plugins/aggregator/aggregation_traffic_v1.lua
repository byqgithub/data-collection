-- Marking: lua,aggregator,aggregation_traffic,1

local aggregator = {
    category = "aggregator",
    name = "aggregation_traffic",
    dataVersion = "1",
    indicator = "aggregation_traffic"
}

local machine_id = ""

local template = {
    category = "bill",
    values = {},
    interval = 60,
    slice_cnt = 1,
    slice_idx = 0,
    timestamp = 0,
    version = 1
}

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

local function fileExists(path)
    local file, _ = io.open(path, "rb")
    if file then
        file:close()
    end
    return file ~= nil
end

local function removekey(tab, key)
    local element = tab
    for k, _ in pairs(tab) do
        if k == key then
            element[key] = nil
        end
    end
    return element
end

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

local function readFile(filePath)
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
    local id = readFile(dbusPath)
    if string.len(id) == 0 then
        id = readFile(dbusPathEtc)
    end
    if string.len(id) == 0 then
        log:Error("Can not read machine id")
        id = ""
    end
    log:Infof("Machine id: %v", id)
    return id
end

local function getData(startTime, endTime, dataBox, dataFeature, showErr)
    -- log:Debugf("range: %v~%v", startTime, endTime)
    -- log:Debugf("pre type: %v", type(pre))
    if showErr == nil then
        showErr = true  -- default show error info
    end
    local lastData = {}

    local dataStr, err = dataBox:GetFields(
            dataFeature.category,
            dataFeature.name,
            dataFeature.dataVersion,
            dataFeature.indicator,
            startTime,
            endTime)
    if err == nil then
        --log:Debugf("Get data string: %v", dataStr)
        local dataArray = jsonUnMarshal(dataStr)
        local length = tableLen(dataArray)
        if length > 0 then
            lastData = jsonUnMarshal(dataArray[length])
        end
        log:Debugf("Get lastData: %v", lastData)
    else
        if (showErr) then
            log:Errorf("Failed to get fields %v %v %v %v from dataBox",
                    dataFeature.category, dataFeature.name,
                    dataFeature.dataVersion, dataFeature.indicator)
        end
    end

    return lastData
end

local function fillTemplate()
    template.category = "bill"
    template.timestamp = os.time()
    template.values = {}

    machine_id = machineID()
end

local function machineTrafficValues(dataTable)
    local value = {}
    local tmpField = {}
    local tag = {}
    local nameArray = {"bw_download", "bw_upload", "program_bw_upload"}
    --log:Debugf("Machine traffic table: %v", dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = 0
        end
        tmpField[name] = tmp
    end

    tag = { machine_id = machine_id}

    table.insert(value, {tags = tag, fields = tmpField})
    log:Debugf("Machine traffic table: %v", value)
    return value
end

local function linesTrafficValues(dataTable)
    local values = {}
    local nameArray = {"bw_download", "bw_upload"}

    for _, lineData in pairs(dataTable) do
        local cache = {}
        for _, item in pairs(nameArray) do
            local tmp = lineData[item]
            if tmp ~= nil then
                cache[item] = tmp
            else
                log:Debugf("Line data %v no have %v", lineData, item)
            end
        end

        if tableLen(cache) > 0 then
            local tag = {machine_id = machine_id, name = lineData["name"]}
            local value = {tags = tag, fields = cache}
            log:Debugf("Lines traffic data: %v", value)
            table.insert(values, value)
        end
    end

    return values
end

local infoKey = {
    customId = {
        category = "input",
        name = "custom_id",
        dataVersion = "1",
        indicator = "custom_id",
        alias= "custom_id"
    },
    bingingDevice = {
        category = "input",
        name = "binging_device",
        dataVersion = "1",
        indicator = "binging_device",
        alias= "binding_interface"
    },
    logTraffic = {
        category = "input",
        name = "log_traffic",
        dataVersion = "1",
        indicator = "log_traffic",
        alias= "bs_bw_upload"
    }
}

local function getTaskOtherInfo(startTime, endTime, dataBox)
    local infoValue = {}
    for name, item in pairs(infoKey) do
        local tmpData = getData(startTime, endTime, dataBox, item, false)
        if tmpData ~= nil and tableLen(tmpData) > 0 then
            infoValue[name] = item
        end
    end

    return infoValue
end

local function tasksTrafficValues(dataTable, startTime, endTime, dataBox)
    local values = {}
    local otherInfo = getTaskOtherInfo(startTime, endTime, dataBox)

    for _, dockerData in pairs(dataTable) do
        local dockerId = dockerData["docker_id"]
        if dockerId == nil or string.len(dockerId) <= 0 then
            dockerId = dockerData["name"]
        end
        if dockerId == nil or string.len(dockerId) <= 0 then
            dockerId = dockerData["idx"]
        end

        for key, item in pairs(infoKey) do
            local value = otherInfo[key]
            if value ~= nil then
                local tmp = value[dockerId]
                if tmp ~= nil then
                    dockerData[item.alias] = tmp
                else
                    log:Debugf("Tasks traffic data no have %v", item.alias)
                end
            end
        end

        local tag = {machine_id = machine_id, docker_id = dockerId, name = dockerData["name"], custom_id = dockerData["custom_id"]}
        local tmpDockerData = removekey(dockerData,"name")
        tmpDockerData = removekey(tmpDockerData,"custom_id")
        tmpDockerData = removekey(tmpDockerData,"docker_id")
        local value = {tags = tag, fields = tmpDockerData}
        log:Debugf("Tasks traffic data: %v", value)
        table.insert(values, value)
    end

    return values
end

local dataSource = {
    machine = {
        category = "processor",
        name = "machine_traffic",
        dataVersion = "1",
        indicator = "machine_traffic",
        handler = machineTrafficValues
    },
    line = {
        category = "processor",
        name = "lines_traffic",
        dataVersion = "1",
        indicator = "lines_traffic",
        handler = linesTrafficValues
    },
    docker = {
        category = "processor",
        name = "task_traffic",
        dataVersion = "1",
        indicator = "task_traffic",
        handler = tasksTrafficValues
    }
}

function converge(startTime, endTime, dataBox, configObject)
    --local globalStr = configObject:ConfigRawContent("global")
    --local globalConfig = jsonUnMarshal(globalStr)
    --local taskTags = getTaskTag(globalConfig)

    local curTime = os.time()
    local dataJson = ""
    fillTemplate()
    for name, item in pairs(dataSource) do
        local dataTable = getData(startTime, endTime, dataBox, item, true)
        if dataTable ~= nil then
            local value = item.handler(dataTable, startTime, endTime, dataBox)
            if value ~= nil then
                template.values[name] = value
            end
        end
    end

    dataJson = jsonMarshal(template)
    log:Debugf("Aggregation data json: %v", dataJson)
    if dataJson ~= nil then
        dataBox:AddField(aggregator.category, aggregator.name, aggregator.dataVersion,
                aggregator.indicator, "", dataJson, curTime)
    end
end
