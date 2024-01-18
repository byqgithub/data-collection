-- Marking: lua,processor,traffic,1

historyData = {
    category = "input",
    name = "traffic",
    version = "1",
    indicator = "traffic"
}

processorData = {
    category = "processor",
    name = "traffic",
    version = "1",
    indicator = "traffic_diff"
}

preData = {}
nowData = {}
maxTotalBw = 1024 * 5 * 1024 * 1024

function description()
    u:Set("lua", "processor", "traffic", "1")
    print("lua, processor, traffic, 1")
end

function getData(startTime, endTime, dataBox)
     print("range: ", startTime, endTime)
    output = {}

    fieldList, err = dataBox:GetFields(
            historyData.category,
            historyData.name,
            historyData.version,
            historyData.indicator,
            startTime,
            endTime)
     print("-- fieldList --")
     print("fieldList:", type(fieldList), fieldList)
     print("fieldList len: ", fieldList:Len())
    fieldListLen = fieldList:Len()
     if (fieldListLen < 2) then
         print("lack of data ")
         return nil, nil
     end

    for i=1, fieldListLen do
        field = fieldList:GetField(i-1)
         print("field:", type(field), field)
         print("Loop fieldList: index,", i)
         print("field", field:Len())
        fieldLen = field:Len()
        for j=1, fieldLen do
            unit = field:GetUnit(j-1)
            unitKey = unit:GetKey()
            unitValue = unit:GetValue()
             print("Unit Key", unitKey)
             print("Unit Value", unitValue)
            output[unitKey] = unitValue
        end
    end
    -- print(fieldList:GetValue())
    -- print("------------------")
    return output
end

function dispose(startTime, endTime, dataBox)
    now = os.time()
    preData = getData(startTime, now, dataBox)
    if (preData == nil) then
        print("processor: lack of preData")
        return
    end
    nowData = getData(now, endTime, dataBox)
    if (nowData == nil) then
        print("processor: lack of nowData")
        return
    end

    for key, data in pairs(preData)
    do
        print("processor: preData: ", key, data)
    end

    for key, data in pairs(nowData)
    do
        print("processor: nowData: ", key, data)
    end

    disposeData = {}
    for nowkey, nowValue in pairs(nowData)
    do
        for preKey, preValue in pairs(preData)
        do
            if (preKey == nowkey) then
                disposeKey = nowkey .. "_diff"
                disposeData[disposeKey] = nowValue - preValue
            end
        end
    end
    for k, d in pairs(disposeData)
    do
        print("processor: disposeData: ", k, d)
    end

    if (disposeData ~= nil or len(disposeData) > 0) then
        dataBox:AddField(processorData.category, processorData.name, processorData.version,
                processorData.indicator, "", processorData.indicator, disposeData, now)
    end
end
