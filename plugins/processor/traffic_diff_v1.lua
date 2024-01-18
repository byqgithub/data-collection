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
    if nowData["SendBytes"] > preData["SendBytes"] then
        for nowkey, nowValue in pairs(nowData)
        do
            for preKey, preValue in pairs(preData)
            do
                if (preKey == nowkey) then

                    if nowkey == "ReceiveBytes" then
                        disposeKey = "bw_download" .. "_diff"
                        disposeData[disposeKey] = (nowValue - preValue) * 8 / (endTime - startTime)

                    elseif nowkey == "SendBytes" then
                        local disposeKey = "bw_download" .. "_diff"
                        local disposeDropKey = "drop_ratio" .. "_diff"
                        local disposeErrorKey = "error_ratio" .. "_diff"
                        local dropRatio = 0.0
                        local errorRatio = 0.0
                        local bwUpload = (nowValue - preValue) * 8 / (endTime - startTime)
                        if bwUpload < maxTotalBw * 2 then
                            if bwUpload > 10 * 1024 * 1024 * 1024 then
                                bwUpload = 0
                            end
                        end

                        if bwUpload > 0 then
                            dropRatio = 100 * (nowData["DropPackets"] - preData["DropPackets"]) / (nowData["SendPackets"] - preData["SendPackets"])
                            errorRatio = 100 * (nowData["ErrorPackets"] - preData["ErrorPackets"]) / (nowData["SendPackets"] - preData["SendPackets"])
                        end

                        disposeData[disposeKey] = bwUpload
                        disposeData[disposeDropKey] = dropRatio
                        disposeData[disposeErrorKey] = errorRatio

                    elseif nowkey == "SendPackets" then
                        local disposeKey = "program_bw_upload" .. "_diff"
                        local totalPackets = nowValue - preValue
                        local programBwUpload = 0.0
                        if nowData["TcpPackets"] > totalPackets then
                            programBwUpload = (nowData["SendPackets"] - preData["SendPackets"] - totalPackets * 66) * 8 / (endTime - startTime)
                        else
                            programBwUpload = (nowData["SendPackets"] - preData["SendPackets"] - nowData["TcpPackets"] * 66 - (totalPackets - nowData["TcpPackets"]) * 50 - nowData["TcpResendPackets"] * 1000) * 8 / (endTime - startTime)
                        end
                        if programBwUpload < 0 then
                            programBwUpload = 0
                        end
                        disposeData[disposeKey] = programBwUpload
                    end

                end
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
