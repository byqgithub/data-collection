-- Marking: lua,aggregator,aggregation_machine_info,1

local aggregator = {
    category = "aggregator",
    name = "aggregation_machine_v5",
    dataVersion = "1",
    indicator = "aggregation_machine_v5"
}

local template = {
    category = "machine",
    values = {},
    interval = 60,
    slice_cnt = 1,
    slice_idx = 0,
    timestamp = 0,
    version = 1
}


local machine_id = ""

local function printTable(value)
    for k, v in pairs(value) do
        print(string.format("key: %s, value: %s", k, v))
    end
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

local function getData(startTime, endTime, dataBox, dataFeature, showErr)
    -- print("range: ", startTime, endTime)
    -- print("pre type: ", type(pre))
    local lastData = {}

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
        print("Failed to get fields from dataBox")
    end

    print("Get lastData: ")
    printTable(lastData)
    return lastData
end

local function getIptablesRuleCount(startTime, endTime, dataBox)
    local infoValue = {}
    local iptables = {
        count = {
            category = "input",
            name = "client_version",
            dataVersion = "1",
            indicator = "client_version"
        }
    }
    for name, item in pairs(iptables) do
        local tmpData = getData(startTime, endTime, dataBox, item, false)
        if tmpData ~= nil and tableLen(tmpData) > 0 then
            infoValue[name] = tmpData[name]
        end
    end
    log:Debugf("get iptables data: %v", infoValue)
    return infoValue
end

local function hostInfoField(dataTable, startTime, endTime, dataBox)
    local field = {}
    local host = {}
    local nameArray = {"hostinfo"}

    --local Data = getIptablesRuleCount(startTime, endTime, dataBox)

    --printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = nil
        end

        host[name] = tmp
    end
    --for k, v in pairs(Data) do
    --    host[k] = v
    --end
    print("host info table:")
    printTable(host)

    --local tag = {machine_id = machine_id}
    --local value = {tags = tag, fields = host}
    --log:Debugf("quality data: %v", value)
    --table.insert(field, value)
    --return field

    --field[1] = host
    --return field
    return host["hostinfo"]
end


local function fillTemplate()
    template.category = "machine"
    template.timestamp = os.time()
    template.values = {}

    machine_id = machineID()
end

local dataSource = {
    host = {
        category = "input",
        name = "host_info",
        dataVersion = "1",
        indicator = "host_info",
        handler = hostInfoField
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
    if dataJson ~= nil then
        dataBox:AddField(aggregator.category, aggregator.name, aggregator.dataVersion,
                aggregator.indicator, "", dataJson, curTime)
    end
end
