-- Marking: lua,aggregator,aggregation_line_nat_type,1

local aggregator = {
    category = "aggregator",
    name = "aggregation_line_nat_type_v5",
    dataVersion = "1",
    indicator = "aggregation_line_nat_type_v5"
}

local template = {
    category = "line_nat_type",
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
    template.category = "line_nat_type"
    template.timestamp = os.time()
    template.values = {}
end


local dataSource = {
    line_nat_type = {
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
