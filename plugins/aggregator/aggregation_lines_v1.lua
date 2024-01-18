-- Marking: lua,aggregator,aggregation_lines,1

local aggregator = {
    category = "aggregator",
    name = "aggregation_lines_v5",
    dataVersion = "1",
    indicator = "aggregation_lines_v5"
}

local template = {
    category = "line",
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

local function lineCountField(dataTable)
    local field = {}
    local line = {}
    local nameArray = {"line_count"}
    print("line count table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = {}
        end
        line[name] = tmp
    end
    print("line dtop table:")
    printTable(line)
    --field[1] = line
    --return field
    return line["line_count"]
end

local function lineDropField(dataTable)
    local field = {}
    local line = {}
    local nameArray = {"line_drop"}
    print("line drop table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = {}
        end
        line[name] = tmp
    end
    print("line dtop table:")
    printTable(line)
    --field[1] = line
    --return field
    return line["line_drop"]
end

local function lineNatTypeField(dataTable)
    local field = {}
    local line = {}
    local nameArray = {"line_nat_type"}
    print("line nat type table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = {}
        end
        line[name] = tmp
    end
    print("line nat type table:")
    printTable(line)
    --field[1] = line
    --return field
    return line["line_nat_type"]
end

local function lineTcpResendField(dataTable)
    local field = {}
    local line = {}
    local nameArray = {"retrans"}
    print("line tcp resend table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = {}
        end
        line[name] = tmp
    end
    print("line tcp resend table:")
    printTable(line)
    --field[1] = line
    --return field
    return line["retrans"]
end

local function linesField(dataTable)
    local field = {}
    local nameArray = {"lines"}

    --printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = 0
        end
        field[name] = tmp
    end
    print("line ping table:")
    printTable(field)
    return field["lines"]
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
    template.category = "line"
    template.timestamp = os.time()
    template.values = {}
end


local dataSource = {
    line = {
        category = "input",
        name = "line_ping",
        dataVersion = "1",
        indicator = "line_ping",
        handler = linesField
    },
    tcp_resend = {
        category = "input",
        name = "line_tcp_resend",
        dataVersion = "1",
        indicator = "line_tcp_resend",
        handler = lineTcpResendField
    },
    nat_type = {
        category = "input",
        name = "line_nat_type",
        dataVersion = "1",
        indicator = "line_nat_type",
        handler = lineNatTypeField
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
