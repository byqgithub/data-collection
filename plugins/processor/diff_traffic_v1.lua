-- Marking: lua,processor,diff_traffic,1

--local processor = {
--    category = "processor",
--    name = "diff_value",
--    dataVersion = "1",
--    indicator = "diff_value"
--}
--
--local inputData = {
--    {
--    category = "input",
--    name = "hardware_card_traffic",
--    dataVersion = "1",
--    indicator = "hardware_card_traffic"
--    },
--}

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

local function tableLen(t)
    local len=0
    for _, _ in pairs(t) do
        len=len+1
    end
    return len;
end

local function getData(startTime, endTime, dataBox, dataFeature)
    local preData = ""
    local nowData = ""

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
        --log:Debugf("processor: dataArray: %v", dataArray)
        local length = tableLen(dataArray)
        if length >= 2 then
            --preData = jsonUnMarshal(dataArray[1])
            --nowData = jsonUnMarshal(dataArray[length])
            preData = dataArray[1]
            nowData = dataArray[length]
        end
    else
        log:Errorf("Failed to get fields %v %v %v %v from dataBox",
                dataFeature.category, dataFeature.name,
                dataFeature.dataVersion, dataFeature.indicator)
    end

    log:Debugf("Get preData: %v", preData)
    log:Debugf("Get nowData: %v", nowData)
    return preData, nowData
end

local function averageCalc(pre, now, keyword, delta)
    if delta <= 0 then
        log:Error("Average calculation, delta must non-zero")
        return 0
    end

    local preValue = pre[keyword]
    local nowValue = now[keyword]
    if preValue == nil or nowValue == nil then
        log:Errorf("Can not find %s in data", keyword)
        return 0
    elseif type(preValue) == "number" and type(nowValue) == "number" then
        log:Debugf("%s pre: %v, now: %v, delta %v",
                keyword, preValue, nowValue, delta)
        if nowValue < preValue then
            return 0
        else
            return math.floor((nowValue - preValue) / delta)
        end
    else
        log:Errorf("Pre %s data type error: %v", keyword, pre)
        log:Errorf("Now %s data type error: %v", keyword, now)
        return 0
    end
end

local function averageCalcBit(pre, now, keyword, deltaTime)
    if deltaTime <= 0 then
        log:Error("Average calculation, deltaTime must non-zero")
        return 0
    end

    local preValue = pre[keyword]
    local nowValue = now[keyword]
    if preValue == nil or nowValue == nil then
        log:Errorf("Can not find %s in data", keyword)
        return 0
    elseif type(preValue) == "number" and type(nowValue) == "number" then
        log:Debugf("%s pre: %v, now: %v, delta time %v",
                keyword, preValue, nowValue, deltaTime)
        if nowValue < preValue then
            return 0
        else
            return math.floor((nowValue - preValue) * 8 / deltaTime)
        end
    else
        log:Errorf("Pre %s data type error: %v", keyword, pre)
        log:Errorf("Now %s data type error: %v", keyword, now)
        return 0
    end
end

local function ratioCalc(pre, now, dividend, divisor)
    local preDividend = pre[dividend]
    local nowDividend = now[dividend]
    local preDivisor = pre[divisor]
    local nowDivisor = now[divisor]
    if preDividend == nil or nowDividend == nil
            or preDivisor == nil or nowDivisor == nil then
        log:Errorf("Can not find %s in data", keyword)
        return 0
    elseif type(preDividend) == "number" and type(nowDividend) == "number"
            and type(preDivisor) == "number" and type(nowDivisor) == "number" then
        log:Debugf("dividend %s pre: %v, now: %v", dividend, preDividend, nowDividend)
        log:Debugf("divisor %s pre: %v, now: %v", divisor, preDivisor, nowDivisor)
        if nowDivisor <= preDivisor then
            return 0
        elseif nowDividend < preDividend then
            return 0
        else
            return (nowDividend - preDividend) / (nowDivisor - preDivisor) * 100
        end
    else
        log:Errorf("RatioCalc Pre %s data type error", pre)
        log:Errorf("RatioCalc Now %s data type error", now)
        return 0
    end
end

local function tcpResendRatioCalc(preData, nowData)
    local tcpPackets = averageCalc(preData, nowData, "TcpPackets", 1)
    local tcpResendPackets = averageCalc(preData, nowData, "TcpResendPackets", 1)
    local tcpResendRatio = 0
    if tcpPackets > 0 then
        tcpResendRatio = tcpResendPackets / tcpPackets
    end
    log:Debugf("TCP Packets %v, TCP resend packets %v, tcp resend ratio %v",
    tcpPackets, tcpResendPackets, tcpResendRatio)
    return tcpPackets, tcpResendPackets, tcpResendRatio
end

local function programBandwidth(preData, nowData, deltaTime)
    local programBwUpload = 0
    local totalSendPackets = averageCalc(preData, nowData, "SendPackets", 1)
    local totalSendBytes = averageCalc(preData, nowData, "SendBytes", 1)
    local tcpPackets, tcpResendPackets, tcpResendRatio = tcpResendRatioCalc(preData, nowData)
    if totalSendPackets <= 0 or deltaTime <= 0 then
        log:Errorf("dividend must non-zero, totalSendPackets %v, detalTime %v",
                totalSendPackets, deltaTime)
        return programBwUpload
    end
    if tcpPackets >= totalSendPackets then
        log:Debug("Only include TCP packages")
        programBwUpload = (totalSendBytes - totalSendPackets * 66) * 8 / deltaTime
        if tcpResendRatio >= 0 and tcpResendRatio <= 1 then
            programBwUpload = math.floor(programBwUpload * (1 - tcpResendRatio))
        end
    else
        log:Debug("Include TCP and UDP packages")
        local tcpSendBytes = tcpPackets / totalSendPackets * totalSendBytes
        local noProgramBytes = (tcpPackets - tcpResendPackets) * 66 + (totalSendPackets - tcpPackets) * 50 + tcpSendBytes * tcpResendRatio
        programBwUpload = math.floor((totalSendBytes - noProgramBytes) * 8 / deltaTime)
    end
    if programBwUpload < 0 then
        programBwUpload = 0
    end
    return programBwUpload
end

local function machineTrafficCalc(firstData, secondData)
    local output = {}
    local preData = jsonUnMarshal(firstData)
    local nowData = jsonUnMarshal(secondData)
    local preTime = preData["timestamp"]
    local nowTime = nowData["timestamp"]
    local deltaTime = 1
    if preTime == nil or nowTime == nil then
        log:Error("Can not find timestamp")
        return nil, os.time()
    else
        deltaTime = nowTime - preTime
        if deltaTime <= 1 then
            deltaTime = 1
        end
        log:Debugf("Traffic data delta-Time %v", deltaTime)
    end

    if nowData["SendBytes"] < preData["SendBytes"] then
        log:Error("Traffic now SendBytes < pre SendBytes, return nils")
        return nil, os.time()
    end

    output["timestamp"] = nowTime
    output["bw_download"] = averageCalcBit(preData, nowData, "ReceiveBytes", deltaTime)
    output["bw_upload"] = averageCalcBit(preData, nowData, "SendBytes", deltaTime)
    output["drop_ratio"] = ratioCalc(preData, nowData, "DropPackets", "SendPackets")
    output["error_ratio"] = ratioCalc(preData, nowData, "ErrorPackets", "SendPackets")
    output["program_bw_upload"] = programBandwidth(preData, nowData, deltaTime)
    if output["program_bw_upload"] > output["bw_upload"] then
        output["program_bw_upload"] = output["bw_upload"]
    end

    log:Debugf("Traffic statistic result: %v", output)
    if output["timestamp"] ~= nil and type(output["timestamp"]) == "number" then
        return output, output["timestamp"]
    else
        return output, os.time()
    end
end

local function taskTrafficCalc(preTaskTable, nowTaskTable)
    local tmpResult = {}
    tmpResult["docker_id"] = nowTaskTable["docker_id"]
    tmpResult["name"] = nowTaskTable["name"]
    tmpResult["idx"] = nowTaskTable["idx"]
    tmpResult["custom_id"] = nowTaskTable["custom_id"]
    tmpResult["binding_interface"] = nowTaskTable["binding_interface"]
    tmpResult["bs_bw_upload"] = nowTaskTable["bs_bw_upload"]
    tmpResult["bw_upload"] = 0
    tmpResult["bw_upload_ipv4"] = 0
    tmpResult["bw_upload_ipv6"] = 0
    tmpResult["bw_download"] = 0
    tmpResult["bw_download_ipv4"] = 0
    tmpResult["bw_download_ipv6"] = 0

    if tableLen(preTaskTable) <= 0 then
        log:Errorf("No match task traffic info: %s, %s",
                nowTaskTable["name"], nowTaskTable["idx"])
        return tmpResult
    end

    local preTime = preTaskTable["timestamp"]
    local nowTime = nowTaskTable["timestamp"]
    local deltaTime = 1
    if preTime == nil or nowTime == nil then
        log:Errorf("No have timestamp in preTaskTable: %v", preTaskTable)
        log:Errorf("No have timestamp in preTaskTable: %v", nowTaskTable)
        return tmpResult
    else
        deltaTime = nowTime - preTime
        if deltaTime <= 1 then
            deltaTime = 1
        end
        log:Debugf("Traffic data delta-Time %v", deltaTime)
    end

    if nowTaskTable["bw_upload"] < preTaskTable["bw_upload"] then
        log:Errorf("Task %s %s traffic now upload < pre upload",
                nowTaskTable["name"], nowTaskTable["idx"])
        return tmpResult
    end

    tmpResult["bw_upload"] = averageCalcBit(preTaskTable, nowTaskTable, "bw_upload", deltaTime)
    tmpResult["bw_upload_ipv4"] = averageCalcBit(preTaskTable, nowTaskTable, "bw_upload_ipv4", deltaTime)
    tmpResult["bw_upload_ipv6"] = averageCalcBit(preTaskTable, nowTaskTable, "bw_upload_ipv6", deltaTime)
    tmpResult["bw_download"] = averageCalcBit(preTaskTable, nowTaskTable, "bw_download", deltaTime)
    tmpResult["bw_download_ipv4"] = averageCalcBit(preTaskTable, nowTaskTable, "bw_download_ipv4", deltaTime)
    tmpResult["bw_download_ipv6"] = averageCalcBit(preTaskTable, nowTaskTable, "bw_download_ipv6", deltaTime)

    return tmpResult
end

local function taskTrafficDispose(firstData, secondData)
    local output = {}
    local preData = jsonUnMarshal(firstData)
    local nowData = jsonUnMarshal(secondData)
    for _, nowTaskTable in pairs(nowData) do
        local preTaskTable = {}
        for _, preTaskData in pairs(preData) do
            if nowTaskTable["name"] == preTaskData["name"] and
                    nowTaskTable["idx"] == preTaskData["idx"] then
                preTaskTable = preTaskData
                break
            end
        end

        local tmpResult = taskTrafficCalc(preTaskTable, nowTaskTable)
        if tableLen(tmpResult) > 0 then
            log:Debugf("Task statistic result: %v", tmpResult)
            table.insert(output, tmpResult)
        end
    end

    return output, os.time()
end

local function linesTrafficCalc(preLinesTable, nowLinesTable)
    local tmpResult = {}

    local preTime = preLinesTable["timestamp"]
    local nowTime = nowLinesTable["timestamp"]
    if nowLinesTable["name"] == nil or
            nowLinesTable["bw_upload"] == nil or
            nowLinesTable["bw_download"] == nil or
            nowLinesTable["receive_packets"] == nil or
            nowLinesTable["send_packets"] == nil or
            preLinesTable["name"] == nil or
            preLinesTable["bw_upload"] == nil or
            preLinesTable["bw_download"] == nil or
            preLinesTable["receive_packets"] == nil or
            preLinesTable["send_packets"] == nil or
            preTime == nil or nowTime == nil then
        log:Errorf("Missing data in preLinesTable: %v", preLinesTable)
        log:Errorf("Missing data in nowLinesTable: %v", nowLinesTable)
        return tmpResult
    end

    tmpResult["name"] = nowLinesTable["name"]
    tmpResult["bw_download"] = 0
    tmpResult["bw_upload"] = 0
    tmpResult["receive_packets"] = 0
    tmpResult["send_packets"] = 0

    if tableLen(preLinesTable) <= 0 then
        log:Errorf("No match lines traffic info: %s", nowLinesTable["name"])
        return tmpResult
    end

    local deltaTime = 1
    deltaTime = nowTime - preTime
    if deltaTime <= 1 then
        deltaTime = 1
    end
    log:Debugf("Traffic data delta-Time %v", deltaTime)

    if nowLinesTable["bw_upload"] < preLinesTable["bw_upload"] then
        log:Debugf("Line %s traffic now upload < pre upload", nowLinesTable["name"])
        return tmpResult
    end

    tmpResult["bw_upload"] = averageCalcBit(preLinesTable, nowLinesTable, "bw_upload", deltaTime)
    tmpResult["bw_download"] = averageCalcBit(preLinesTable, nowLinesTable, "bw_download", deltaTime)
    tmpResult["receive_packets"] = averageCalc(preLinesTable, nowLinesTable, "receive_packets", 1)
    tmpResult["send_packets"] = averageCalc(preLinesTable, nowLinesTable, "send_packets", 1)

    return tmpResult
end

local function linesTrafficDispose(firstData, secondData)
    local output = {}
    local preLinesArray = jsonUnMarshal(firstData)
    local nowLinesArray = jsonUnMarshal(secondData)
    for _, nowLinesTable in pairs(nowLinesArray) do
        local preLinesTable = {}
        for _, preData in pairs(preLinesArray) do
            if nowLinesTable["name"] == preData["name"] then
                preLinesTable = preData
                break
            end
        end

        local tmpResult = linesTrafficCalc(preLinesTable, nowLinesTable)
        if tableLen(tmpResult) > 0 then
            log:Debugf("Lines statistic result: %v", tmpResult)
            table.insert(output, tmpResult)
        end
    end

    return output, os.time()
end

local function diffValue(startTime, endTime, dataBox, item)
    local preData, nowData = getData(startTime, endTime, dataBox, item.input)
    if string.len(preData) <= 0 or string.len(nowData) <= 0 then
        log:Error("Can not get input data")
        return nil, os.time()
    end

    return item.output.handler(preData, nowData)
end

local itemTable = {
    {
        input = {
            category = "input",
            name = "machine_traffic",
            dataVersion = "1",
            indicator = "machine_traffic"
        },
        output = {
            category = "processor",
            name = "machine_traffic",
            dataVersion = "1",
            indicator = "machine_traffic",
            handler = machineTrafficCalc
        }
    },
    {
        input = {
            category = "input",
            name = "task_traffic",
            dataVersion = "1",
            indicator = "task_traffic"
        },
        output = {
            category = "processor",
            name = "task_traffic",
            dataVersion = "1",
            indicator = "task_traffic",
            handler = taskTrafficDispose
        }
    },
    {
        input = {
            category = "input",
            name = "lines_traffic",
            dataVersion = "1",
            indicator = "lines_traffic"
        },
        output = {
            category = "processor",
            name = "lines_traffic",
            dataVersion = "1",
            indicator = "lines_traffic",
            handler = linesTrafficDispose
        }
    },
}

function dispose(startTime, endTime, dataBox)
    for _, item in pairs(itemTable) do
        local dataJson = ""
        local dataTable, timestamp = diffValue(startTime, endTime, dataBox, item)
        if dataTable ~= nil and tableLen(dataTable) > 0 then
            dataJson = jsonMarshal(dataTable)
            if dataJson ~= nil and string.len(dataJson) > 0 then
                dataBox:AddField(
                        item.output.category,
                        item.output.name,
                        item.output.dataVersion,
                        item.output.indicator,
                        "",
                        dataJson,
                        timestamp)
            end
        end
    end
end
