-- Marking: lua,processor,diff_tcp_resend,1

local itemTable = {
    {
        input = {
            category = "input",
            name = "tcp_resend",
            dataVersion = "1",
            indicator = "tcp_resend"
        },
        output = {
            category = "processor",
            name = "tcp_resend",
            dataVersion = "1",
            indicator = "tcp_resend"
        }
    },
}

local function printTable(value)
    for k, v in pairs(value) do
        log:Debugf(string.format("key: %s, value: %s", k, v))
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
    local preData = {}
    local nowData = {}

    local dataStr, err = dataBox:GetFields(
            dataFeature.category,
            dataFeature.name,
            dataFeature.dataVersion,
            dataFeature.indicator,
            startTime,
            endTime)
    if err == nil then
        log:Debugf("Get data string: ", dataStr, type(dataStr))
        local dataArray = arrayUnMarshal(dataStr)
        log:Debugf("processor: dataArray: ", dataArray, type(dataArray))
        local length = tableLen(dataArray)
        if length >= 2 then
            preData = jsonUnMarshal(dataArray[1])
            nowData = jsonUnMarshal(dataArray[length])
        end
    else
        log:Debugf("Failed to get fields from dataBox")
    end

    log:Debugf("Get preData: ")
    printTable(preData)
    log:Debugf("Get nowData: ")
    printTable(nowData)
    return preData, nowData
end


local function tcpResendCalc(preData, nowData)
    local output = {}
    local preTime = preData["timestamp"]
    local nowTime = nowData["timestamp"]
    local deltaTime = 1
    if preTime == nil or nowTime == nil then
        return nil, nil
    else
        deltaTime = nowTime - preTime
        if deltaTime <= 1 then
            deltaTime = 1
        end
        log:Debugf("system tcp resend data delta-Time ", deltaTime)
    end

    if nowData["tcpOutSegs"] < preData["tcpOutSegs"] and nowData["tcpRetransSegs"] < preData["tcpRetransSegs"] then
        return nil, nil
    end

    output["timestamp"] = nowTime
    output["tcp_resend"] = 100 * (nowData["tcpRetransSegs"] - preData["tcpRetransSegs"]) / (nowData["tcpOutSegs"] - preData["tcpOutSegs"])

    return output, output["timestamp"]
end

local function diffValue(startTime, endTime, dataBox, item)
    local preData, nowData = getData(startTime, endTime, dataBox, item.input)
    if tableLen(preData) <= 0 or tableLen(nowData) <= 0 then
        log:Debugf("Can not get input data")
        return nil, nil
    end

    if item.output.indicator == "tcp_resend" then
        return tcpResendCalc(preData, nowData)
    end
end

function dispose(startTime, endTime, dataBox)
    local dataJson = ""
    for _, item in pairs(itemTable) do
        local dataTable, timestamp = diffValue(startTime, endTime, dataBox, item)
        if dataTable ~= nil then
            dataJson = jsonMarshal(dataTable)
        end
        log:Debugf(dataJson)
        if dataJson ~= nil and timestamp ~= nil and type(timestamp) == "number" then
            dataBox:AddField(item.output.category, item.output.name, item.output.dataVersion,
                    item.output.indicator, "", dataJson, timestamp)
        end
    end
end
