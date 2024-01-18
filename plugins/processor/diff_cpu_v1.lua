-- Marking: lua,processor,diff_cpu,1

local cpu_metric = {"user", "nice", "system", "idle", "iowait", "irrq", "softirq", "steal"}

local itemTable = {
    {
        input = {
            category = "input",
            name = "system_cpu",
            dataVersion = "1",
            indicator = "system_cpu"
        },
        output = {
            category = "processor",
            name = "system_cpu",
            dataVersion = "1",
            indicator = "system_cpu"
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

local function fileExists(file)
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
end

local function strip(str)
    return string.gsub(str, "^%s*(.-)%s*$", "%1")
end

local function readAllFile(filePath)
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
    local id = readAllFile(dbusPath)
    if string.len(id) == 0 then
        id = readAllFile(dbusPathEtc)
    end
    if string.len(id) == 0 then
        print("Can not read machine id")
        id = ""
    end
    print("Machine id: ", id)
    return id
end


local function cpuCalc(nowData, preData, total)
    --print(nowData, preData, total)
    if nowData <= preData then
        return 0
    end

    return (nowData - preData) / total * 100
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
        print("Get data string: ", dataStr, type(dataStr))
        local dataArray = arrayUnMarshal(dataStr)
        print("processor: dataArray: ", dataArray, type(dataArray))
        local length = tableLen(dataArray)
        if length >= 2 then
            preData = jsonUnMarshal(dataArray[1])
            nowData = jsonUnMarshal(dataArray[length])
        end
    else
        print("Failed to get fields from dataBox")
    end

    print("Get preData: ")
    printTable(preData)
    print("Get nowData: ")
    printTable(nowData)
    return preData, nowData
end


local function systemCpuCalc(preData, nowData)

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
        print("system cpu data delta-Time ", deltaTime)
    end
    --print(nowData["cpu"]["cpu0"])
    if nowData["cpu"]["cpu0"]["total"] < preData["cpu"]["cpu0"]["total"] then
        return nil, nil
    end

    local output = {
        ["timestamp"] = nowTime,
        ["cpu"] = {}
    }
    local machineId = machineID()
    local index = 1
    for kk, vv in pairs(nowData["cpu"]) do
        local tmp = {
            ["name"] = kk
        }

        local tags = {
            ["machine_id"] = machineId,
            ["name"] = kk,
        }

        for _, key in pairs(cpu_metric) do
            if vv[key] ~= nil then

                local total = tonumber(nowData["cpu"][kk]["total"]) - tonumber(preData["cpu"][kk]["total"])
                --print(total)
                --print(tonumber(nowData["cpu"][kk][key]), tonumber(preData["cpu"][kk][key]))

                tmp[key] = cpuCalc(tonumber(nowData["cpu"][kk][key]), tonumber(preData["cpu"][kk][key]), total)
            end
        end

        local cpu_data = {
            ["tags"] = tags,
            ["fields"] = tmp
        }
        output["cpu"][index] = cpu_data
        index = index + 1
    end

    --for k, v in pairs(output["cpu"]) do
    --    for kk, vv in pairs(v) do
    --        print("cpu: ", k, kk, vv)
    --    end
    --
    --end
    return output, output["timestamp"]
end

local function diffValue(startTime, endTime, dataBox, item)
    local preData, nowData = getData(startTime, endTime, dataBox, item.input)
    if tableLen(preData) <= 0 or tableLen(nowData) <= 0 then
        print("Can not get input data")
        return nil, nil
    end

    if item.output.indicator == "system_cpu" then
        return systemCpuCalc(preData, nowData)
    end
end

function dispose(startTime, endTime, dataBox)
    local dataJson = ""
    for _, item in pairs(itemTable) do
        local dataTable, timestamp = diffValue(startTime, endTime, dataBox, item)
        if dataTable ~= nil then
            dataJson = jsonMarshal(dataTable)
        end
        print(dataJson)
        if dataJson ~= nil and timestamp ~= nil and type(timestamp) == "number" then
            dataBox:AddField(item.output.category, item.output.name, item.output.dataVersion,
                    item.output.indicator, "", dataJson, timestamp)
        end
    end
end
