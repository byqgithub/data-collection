-- Marking: lua,processor,diff_disk,1

local disk_metric = {"rd_ios", "rd_ticks", "wr_ios", "wr_ticks", "io_ticks"}
local disk_usage_metric = {"diskcap", "disktype", "diskusage", "mountpoint", "hderror"}
local itemTable = {
    {
        input = {
            category = "input",
            name = "disk",
            dataVersion = "1",
            indicator = "disk"
        },
        output = {
            category = "processor",
            name = "disk",
            dataVersion = "1",
            indicator = "disk"
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

local function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function (w)
        table.insert(resultStrList,w)
    end)
    return resultStrList
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

local function diskCalc(ticks, ios)
    if (ios <= 0) then
        return 0
    end
    return math.floor(ticks / ios)
end
local function executeCmd(cmd, timeout)
    if timeout == nil then
        timeout = 5
    end

    local result = ""
    local command = string.format("%s ", cmd)
    local file = assert(io.popen(command, 'r'))
    if file == nil then
        print(string.format("Execute command (%s) failed", cmd))
        return nil
    end

    file:flush() -- > important to prevent receiving partial output
    local output = file:read("*all")
    file:close()
    if (output ~= nil and string.len(output) > 0) then
        result = string.gsub(output, "^%s*(.-)%s*$", "%1")
    end
    --print(output)

    return result

end

--local function diskUsage()
--    local diskTable = {}
--    local result = executeCmd("/usr/bin/python3 /root/heibao/collect/lshw_v5.py")
--    print("disk cap", result)
--    local resultSplit = split(result, ",")
--    for _, v in pairs(resultSplit) do
--        local vsplit = split(v, "#")
--        local tmp = {
--            ["diskcap"] = vsplit[2],
--            ["disktype"] = vsplit[3],
--            ["diskusage"] = vsplit[4],
--            ["mountpoint"] = vsplit[5],
--            ["hderror"] = vsplit[6]
--        }
--        diskTable[vsplit[1]] = tmp
--    end
--    return diskTable
--end


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


local function diskStatsCalc(preData, nowData)
    local machineId = machineID()
    local output = {}
    local outtmp = {}
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
        print("disk data delta-Time ", deltaTime)
    end

    print("nowData ")
    for k, v in pairs(nowData["disk"]) do
        for kk, vv in pairs(v) do
            print(k, kk, vv)
        end
    end

    print("preData ")
    for k, v in pairs(preData["disk"]) do
        for kk, vv in pairs(v) do
            print(k, kk, vv)
        end
    end

    if nowData["disk"] == nil and preData["disk"] == nil then
        return nil, nil
    end

    output["timestamp"] = nowTime
    output["disk"] = {
    }
    outtmp["disk"] = {}

    for kk, vv in pairs(nowData["disk"]) do
        local tmp = {}
        if vv["disk_data"] == 1 then
            for _, key in pairs(disk_metric) do
                print("calc", kk, vv, key)
                print(vv[key])
                if vv[key] ~= nil then
                    local diff = 0
                    print("nowData[" .. kk .. "][" .. key .. "]")
                    print(nowData["disk"][kk])
                    print(nowData["disk"][kk][key])
                    print("preData[" .. kk .. "][" .. key .. "]", preData["disk"][kk][key])
                    if nowData["disk"][kk][key] ~= nil and preData["disk"][kk][key] ~= nil then
                        print(tonumber(nowData["disk"][kk][key]) - tonumber(preData["disk"][kk][key]))
                        diff = tonumber(nowData["disk"][kk][key]) - tonumber(preData["disk"][kk][key])
                        print(key, diff)
                    end
                    tmp[key] = diff
                end
            end

            for _, key in pairs(disk_usage_metric) do
                if vv[key] ~= nil then
                    -- mountpoint == "-"
                    if vv[key] == "-" then
                        tmp[key] = ""
                    else
                        tmp[key] = vv[key]
                    end

                end
            end
            outtmp["disk"][kk] = tmp
        end


    end

    for k, v in pairs(outtmp) do
        for kk, vv in pairs(v) do
            print(k, kk, vv)
        end
    end

    local index = 1
    for kk, vv in pairs(outtmp["disk"]) do
        local tmp = {}
        --local tmp = {
        --    ["name"] = kk
        --}
        tmp["rddelay"] = diskCalc(tonumber(vv["rd_ticks"]), tonumber(vv["rd_ios"]))
        tmp["wrdelay"] = diskCalc(tonumber(vv["wr_ticks"]), tonumber(vv["wr_ios"]))
        tmp["ioduration"] = tonumber(vv["io_ticks"]) / (nowTime - preTime)
        tmp["iops"] = -1
        tmp["iops_time"] = -1
        tmp["capacity"] = vv["diskcap"]
        tmp["type"] = vv["disktype"]
        tmp["usage"] = vv["diskusage"]
        tmp["mountpoint"] = vv["mountpoint"]

        tmp["hderror"] = vv["hderror"]

        local tags = {
            ["machine_id"] = machineId,
            ["name"] = kk,
        }

        local tmp_data = {
            ["tags"] = tags,
            ["fields"] = tmp
        }

        output["disk"][index] = tmp_data
        index = index + 1

    end

    for k, v in pairs(output["disk"]) do
        for kk, vv in pairs(v) do
            print("diff disk: ", k, kk, vv)
        end

    end
    return output, output["timestamp"]
end

local function diffValue(startTime, endTime, dataBox, item)
    local preData, nowData = getData(startTime, endTime, dataBox, item.input)
    if tableLen(preData) <= 0 or tableLen(nowData) <= 0 then
        print("Can not get input data")
        return nil, nil
    end

    if item.output.indicator == "disk" then
        print("diskStatsCalc")
        return diskStatsCalc(preData, nowData)
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

