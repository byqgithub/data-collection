-- Marking: lua,aggregator,aggregation_dockers,1

local aggregator = {
    category = "aggregator",
    name = "aggregation_dockers_v5",
    dataVersion = "1",
    indicator = "aggregation_dockers_v5"
}

local template = {
    category = "docker",
    values = {},
    interval = 60,
    slice_cnt = 1,
    slice_idx = 0,
    timestamp = 0,
    version = 1
}

local function printTable(value)
    for k, v in pairs(value) do
        print(string.format("key: %s, value: %s", k, v))
    end
end

local function tableLen(t)
    local len=0
    for _, _ in pairs(t) do
        len=len+1
    end
    return len;
end

local function getData(startTime, endTime, dataBox, dataFeature, showErr)
    -- print("range: ", startTime, endTime)
    -- print("pre type: ", type(pre))
    local lastData = {}
    print(dataFeature.category, dataFeature.name, dataFeature.indicator)
    local dataStr, err = dataBox:GetFields(
            dataFeature.category,
            dataFeature.name,
            dataFeature.dataVersion,
            dataFeature.indicator,
            startTime,
            endTime)
    if err == nil then
        print("Get data string: ", dataStr)
        local dataArray = arrayUnMarshal(dataStr)
        local length = tableLen(dataArray)
        if length > 0 then
            lastData = jsonUnMarshal(dataArray[length])
        end
    else
        print("Failed to get fields from dataBox aggregator")
    end

    print("Get lastData: ")
    printTable(lastData)
    return lastData
end


local taskInfo = {
    dockers = {
        category = "input",
        name = "dockers",
        dataVersion = "1",
        indicator = "dockers",
    },
    dcache = {
        category = "input",
        name = "dcache_task",
        dataVersion = "1",
        indicator = "dcache_task",
    },
    task = {
        category = "input",
        name = "machine_task",
        dataVersion = "1",
        indicator = "machine_task",
    },
    bz = {
        category = "input",
        name = "bz_task",
        dataVersion = "1",
        indicator = "bz_task",
    }
}

local function printTable(value)
    for k, v in pairs(value) do
        print(string.format("key: %s, value: %s", k, v))
    end
end

local function dockersField(dataTable, startTime, endTime, dataBox)

    local Values = {}
    --local index = 1
    for name, item in pairs(taskInfo) do
        local tmpData = getData(startTime, endTime, dataBox, item, false)
        if tmpData ~= nil and tableLen(tmpData) > 0 then
            local tmp = tmpData[name]
            print("print docker data")
            if tmp ~= nil then
                printTable(tmp)
                --tmp = nil
                for _, t in pairs(tmp) do
                    table.insert(Values, t)
                end

                --if tableLen(tmp) == 1 then
                --    Values[index] = tmp[1]
                --else
                --    Values[index] = tmp
                --end

                --index = index + 1
            end
        end
    end

    return Values
end


local function dcacheStatusField(dataTable, startTime, endTime, dataBox)
    local field = {}
    local nameArray = {"status"}
    print("dcache status table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = nil
        end
        field[name] = tmp
    end
    print("dache status table:")
    printTable(field)
    return field["status"]
end

local function fileExists(path)
    local file, _ = io.open(path, "rb")
    if file then
        file:close()
    end
    return file ~= nil
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
        print("Can not read machine id")
        id = ""
    end
    print("Machine id: ", id)
    return id
end

local function fillTemplate()
    template.category = "docker"
    template.timestamp = os.time()
    template.values = {}
end


local dataSource = {
    docker = {
        category = "input",
        name = "dockers",
        dataVersion = "1",
        indicator = "dockers",
        handler = dockersField
    },
    dcache = {
        category = "input",
        name = "dcache_task",
        dataVersion = "1",
        indicator = "dcache_task",
        handler = dcacheStatusField
    }
}

function converge(startTime, endTime, dataBox)
    local curTime = os.time()
    local dataJson = ""
    fillTemplate()
    for name, item in pairs(dataSource) do
        local dataTable = getData(startTime, endTime, dataBox, item, false)
        if dataTable ~= nil then
            local field = item.handler(dataTable, startTime, endTime, dataBox)
            if field ~= nil then
                template.values[name] = field
            end
        end
    end

    dataJson = jsonMarshal(template)
    print("Aggregation data: ", dataJson)
    if dataJson ~= nil then
        dataBox:AddField(aggregator.category, aggregator.name, aggregator.dataVersion,
                aggregator.indicator, "", dataJson, curTime)
    end
end
