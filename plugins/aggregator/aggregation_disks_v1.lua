-- Marking: lua,aggregator,aggregation_disks,1

local aggregator = {
    category = "aggregator",
    name = "aggregation_disks_v5",
    dataVersion = "1",
    indicator = "aggregation_disks_v5"
}

local template = {
    category = "disk",
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

local function disksField(dataTable)
    local field = {}
    local nameArray = {"disk"}
    print("disk table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = nil
        end
        field[name] = tmp
    end
    print("disk table:")
    printTable(field)
    return field["disk"]
end

local function diskSystemField(dataTable)
    local field = {}
    local disk_system = {}
    --local nameArray = {"disk_system_size", "disk_system_usage"}
    local nameArray = {"disk_system"}
    print("disk system size table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = {}
        end
        disk_system[name] = tmp
    end
    print("disk system size table:")
    printTable(disk_system)
    --field[1] = disk_system
    --return field
    return disk_system["disk_system"]
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
    template.category = "disk"
    template.timestamp = os.time()
    template.values = {}
end


local dataSource = {
    disk = {
        category = "processor",
        name = "disk",
        dataVersion = "1",
        indicator = "disk",
        handler = disksField
    },
    disk_system = {
        category = "input",
        name = "disk_system_size",
        dataVersion = "1",
        indicator = "disk_system_size",
        handler = diskSystemField
    }
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
