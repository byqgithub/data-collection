-- Marking: lua,output,http_report_traffic,1

local dataSource = {
    {
        category = "aggregator",
        name = "aggregation_traffic",
        dataVersion = "1",
        indicator = "aggregation_traffic"
    }
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

--local function split(str,reps)
--    local resultStrList = {}
--    string.gsub(str,'[^'..reps..']+',function (w)
--        table.insert(resultStrList, w)
--    end)
--    return resultStrList
--end
--
--local function strip(str)
--    return string.gsub(str, "^%s*(.-)%s*$", "%1")
--end

local function tableLen(t)
    local len=0
    for _, _ in pairs(t) do
        len=len+1
    end
    return len;
end

local function getData(startTime, endTime, dataBox, dataFeature)
    -- log:Debugf("range: %v~%v", startTime, endTime)
    -- log:Debugf("pre type: %v", type(pre))
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
    else
        log:Errorf("Failed to get fields %v %v %v %v from dataBox",
                dataFeature.category, dataFeature.name,
                dataFeature.dataVersion, dataFeature.indicator)
    end

    log:Debugf("Get lastData: %v", lastData)
    return lastData
end

function write(startTime, endTime, dataBox)
    local dataJson = ""
    for _, item in pairs(dataSource) do
        local dataTable = getData(startTime, endTime, dataBox, item)
        if dataTable ~= nil then
            dataJson = jsonMarshal(dataTable)
            log:Infof("Report data json: %v", dataJson)
            uploadData(dataJson, true)
        end
    end
end
