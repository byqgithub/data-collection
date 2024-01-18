-- Marking: lua,aggregator,aggregation_error,1

local aggregator = {
    category = "aggregator",
    name = "aggregation_error_v5",
    dataVersion = "1",
    indicator = "aggregation_error_v5"
}

local template = {
    category = "error",
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

local function ksLogErrorField(dataTable)
    local field = {}
    local error = {}
    local nameArray = {"ks_error"}
    print("ks error log table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = 0
        end
        error[name] = tmp
    end
    print("ks error log table:")
    printTable(error)
    return error["ks_error"]
    --field[1] = error
    --return field
end

local function ErrorLogErrorField(dataTable)
    local field = {}
    local error = {}
    local nameArray = {"error_log"}
    print("error log table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = 0
        end
        error[name] = tmp
    end
    print("error log table:")
    printTable(error)
    log:Debugf("err log table: %v", error)
    return error["error_log"]
    --field[1] = error
    --return field
end

local function hardwareErrorField(dataTable)
    local field = {}
    local hard_error = {}
    local nameArray = {"hard_error"}
    print("hardware error table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = nil
        end
        hard_error[name] = tmp
    end
    print("hardware error table:")
    printTable(hard_error)
    --field[1] = hard_error
    --return field
    return hard_error["hard_error"]
end

local function typeVmField(dataTable)
    local field = {}
    local typeVm = {}
    --local nameArray = {"type_vm"}
    local nameArray = {"vm"}
    print("type vm table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = nil
        end
        typeVm[name] = tmp
    end
    print("type vm table:")
    printTable(typeVm)
    return typeVm["vm"]
    --field[1] = typeVm
    --return field
end

local function mountedStatusField(dataTable)
    local field = {}
    local mounted = {}
    --local nameArray = {"mounted_multi_status", "mounted_root"}
    local nameArray = {"mounted"}
    print("mounted status table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = nil
        end
        mounted[name] = tmp
    end
    print("mounted status table:")
    printTable(mounted)
    --field[1] = mounted
    --return field
    return mounted["mounted"]
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

local function getData(startTime, endTime, dataBox, dataFeature)
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

local function fillTemplate()
    template.category = "error"
    template.timestamp = os.time()
    template.values = {}
end


local dataSource = {
    log = {
        category = "input",
        name = "ks_error_log",
        dataVersion = "1",
        indicator = "ks_error_log",
        handler = ErrorLogErrorField
    },
    hardware = {
        category = "input",
        name = "hardware_error",
        dataVersion = "1",
        indicator = "hardware_error",
        handler = hardwareErrorField
    },
    type_vm = {
        category = "input",
        name = "type_vm",
        dataVersion = "1",
        indicator = "type_vm",
        handler = typeVmField
    },
    mounted_status = {
        category = "input",
        name = "mounted_status",
        dataVersion = "1",
        indicator = "mounted_status",
        handler = mountedStatusField
    },
}

function converge(startTime, endTime, dataBox)
    local curTime = os.time()
    local dataJson = ""
    fillTemplate()
    for name, item in pairs(dataSource) do
        local dataTable = getData(startTime, endTime, dataBox, item)
        if dataTable ~= nil then
            local field = item.handler(dataTable)
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
