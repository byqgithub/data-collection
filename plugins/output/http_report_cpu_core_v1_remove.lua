-- Marking: lua,output,http_report_cpu_core,1

local dataSource = {
    {
        category = "aggregator",
        name = "aggregation_hard_cpu_v5",
        dataVersion = "1",
        indicator = "aggregation_hard_cpu_v5"
    }
}

local function printTable(value)
    for k, v in pairs(value) do
        print(string.format("key: %s, value: %s", k, v))
    end
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

local function getData(startTime, endTime, dataBox, dataFeature)
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

function write(startTime, endTime, dataBox)
    local dataJson = ""
    for _, item in pairs(dataSource) do
        local dataTable = getData(startTime, endTime, dataBox, item)
        if dataTable ~= nil then
            dataJson = jsonMarshal(dataTable)
            print("Report data json: ", dataJson)
            uploadData(dataJson, true)
        end
    end
end
