-- Marking: lua,processor,diff_memory,1

local itemTable = {
    {
        input = {
            category = "input",
            name = "memory",
            dataVersion = "1",
            indicator = "memory"
        },
        output = {
            category = "processor",
            name = "memory",
            dataVersion = "1",
            indicator = "memory"
        }
    },
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

local function getData(startTime, endTime, dataBox, dataFeature)
    local nowData = {}

    local dataStr, err = dataBox:GetFields(
            dataFeature.category,
            dataFeature.name,
            dataFeature.dataVersion,
            dataFeature.indicator,
            startTime,
            endTime)
    if err == nil then
        print("Get memory data string: ", dataStr, type(dataStr))
        local dataArray = arrayUnMarshal(dataStr)
        print("processor: memory dataArray: ", dataArray, type(dataArray))
        local length = tableLen(dataArray)
        if length >= 1 then
            nowData = jsonUnMarshal(dataArray[length])
        end
    else
        print("Failed to get fields from dataBox memory")
    end

    print("Get memory nowData: ")
    printTable(nowData)
    return nowData
end

local function memoryCalc(nowData)
    local output = {}
    local nowTime = nowData["timestamp"]
    if nowTime == nil then
        return nil, nil
    end

    output["timestamp"] = nowTime
    output["mem_size"] = nowData["MemTotal"]
    output["mem_usage"] = 100 * (nowData["MemTotal"] - nowData["MemAvailable"]) / (nowData["MemTotal"])
    print(" memory result:")
    printTable(output)
    return output, output["timestamp"]

end


local function diffValue(startTime, endTime, dataBox, item)
    local nowData = getData(startTime, endTime, dataBox, item.input)
    if tableLen(nowData) <= 0 then
        print("Can not get input data")
        return nil, nil
    end

    if item.output.indicator == "memory" then
        return memoryCalc(nowData)
    end
end

function dispose(startTime, endTime, dataBox)
    local dataJson = ""
    for _, item in pairs(itemTable) do
        local dataTable, timestamp = diffValue(startTime, endTime, dataBox, item)
        if dataTable ~= nil then
            dataJson = jsonMarshal(dataTable)
        end
        print("processor disposeData: ", dataJson, timestamp)
        if dataJson ~= nil and timestamp ~= nil and type(timestamp) == "number" then
            dataBox:AddField(item.output.category, item.output.name, item.output.dataVersion,
                    item.output.indicator, "", dataJson, timestamp)
        end
    end
end
