-- Marking: lua,aggregator,aggregation_network,1

local aggregator = {
    category = "aggregator",
    name = "aggregation_network_v5",
    dataVersion = "1",
    indicator = "aggregation_network_v5"
}

local template = {
    category = "network",
    values = {},
    interval = 60,
    slice_cnt = 1,
    slice_idx = 0,
    timestamp = 0,
    version = 1
}

local machine_id = ""


local quality = {
    tcp_resend = {
        category = "processor",
        name = "tcp_resend",
        dataVersion = "1",
        indicator = "tcp_resend",
    },
    bw_nat_type = {
        category = "input",
        name = "bw_nat_type",
        dataVersion = "1",
        indicator = "bw_nat_type",
    },
    dial_type = {
        category = "input",
        name = "dial_type",
        dataVersion = "1",
        indicator = "dial_type",
    },
    dns_status = {
        category = "input",
        name = "dns_test",
        dataVersion = "1",
        indicator = "dns_test",
    },
    line_count = {
        category = "input",
        name = "line_ping",
        dataVersion = "1",
        indicator = "line_ping",
    },
    line_drop = {
        category = "input",
        name = "line_ping",
        dataVersion = "1",
        indicator = "line_ping",
    },
    drop_ratio = {
        category = "processor",
        name = "machine_traffic",
        dataVersion = "1",
        indicator = "machine_traffic",
    },
    error_ratio = {
        category = "processor",
        name = "machine_traffic",
        dataVersion = "1",
        indicator = "machine_traffic",
    }
}

local line_quality = {
    line_count = {
        category = "input",
        name = "line_ping",
        dataVersion = "1",
        indicator = "line_ping",
    },
    line_drop = {
        category = "input",
        name = "line_ping",
        dataVersion = "1",
        indicator = "line_ping",
    }
}

local function printTable(value)
    for k, v in pairs(value) do
        print(string.format("key: %s, value: %s", k, v))
    end
end

local function fileExists(path)
    local file, _ = io.open(path, "rb")
    if file then
        file:close()
    end
    return file ~= nil
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

local function tableLen(t)
    local len=0
    for _, _ in pairs(t) do
        len=len+1
    end
    return len;
end

local function readFile(filePath)
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

local function getData(startTime, endTime, dataBox, dataFeature, showErr)
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

        log:Debugf("Failed to get fields from dataBox")
        log:Debugf("category : %v, name : %v" , dataFeature.category, dataFeature.name)
    end

    log:Debugf("Get lastData: ")
    printTable(lastData)
    return lastData
end


local function fillTemplate()
    template.category = "network"
    template.timestamp = os.time()
    template.values = {}

    machine_id = machineID()
end


--local function getQualityData(startTime, endTime, dataBox)
--    local infoValue = {}
--    for name, item in pairs(quality) do
--        local tmpData = getData(startTime, endTime, dataBox, item, false)
--        if tmpData ~= nil and tableLen(tmpData) > 0 then
--            infoValue[name] = item
--        end
--    end
--
--    return infoValue
--end

local function getQualityData(startTime, endTime, dataBox)
    local infoValue = {}
    for name, item in pairs(quality) do
        local tmpData = getData(startTime, endTime, dataBox, item, false)
        if tmpData ~= nil and tableLen(tmpData) > 0 then
            infoValue[name] = tmpData[name]
        end
    end
    log:Debugf("get quality data: %v", infoValue)
    return infoValue
end

local function qualityField(dataTable, startTime, endTime, dataBox)
    local values = {}
    local qualityData = getQualityData(startTime, endTime, dataBox)

    local tag = {machine_id = machine_id}
    local value = {tags = tag, fields = qualityData}
    log:Debugf("quality data: %v", value)
    table.insert(values, value)
    return values
end

--local function tcpField(dataTable)
--    local field = {}
--    local curTime = os.time()
--    local machineId = machineID()
--    local tmpField = {
--        ["timestamp"] = curTime,
--        ["tcp_resend"] = {}
--    }
--    local tcpTable = {
--        ["fields"] = {
--            ["tcp_resend"] = 0
--        },
--        ["tags"] = {
--            ["machine_id"] = machineId
--        }
--    }
--    local nameArray = {"tcp_resend"}
--    log:Debugf("tcp table:")
--    printTable(dataTable)
--    for _, name in pairs(nameArray) do
--        local tmp = dataTable[name]
--        if tmp == nil then
--            tmp = 0
--        end
--        tcpTable["fields"]["tcp_resend"] = tmp
--
--    end
--    tmpField["tcp_resend"][1] = tcpTable
--    log:Debugf("tcp table:")
--    printTable(tmpField)
--    --field[1] = tmpField
--    --return field
--    return tmpField["tcp_resend"]
--end
--
--local function bwNatTypeField(dataTable)
--    local field = {}
--    local tmpField = {}
--    local nameArray = {"bw_nat_type"}
--    log:Debugf("bw_nat_type table:")
--    printTable(dataTable)
--    for _, name in pairs(nameArray) do
--        local tmp = dataTable[name]
--        if tmp == nil then
--            tmp = 0
--        end
--        tmpField[name] = tmp
--    end
--    log:Debugf("bw_nat_type table:")
--    printTable(tmpField)
--    --field[1] = tmpField
--    --return field
--    return tmpField["bw_nat_type"]
--end
--
--local function dialTypeField(dataTable)
--    local field = {}
--    local tmpField = {}
--    local nameArray = {"dial_type"}
--    log:Debugf("dial_type table:")
--    printTable(dataTable)
--    for _, name in pairs(nameArray) do
--        local tmp = dataTable[name]
--        if tmp == nil then
--            tmp = 0
--        end
--        tmpField[name] = tmp
--    end
--    log:Debugf("dial_type table:")
--    printTable(tmpField)
--    --field[1] = tmpField
--    --return field
--    return tmpField["dial_type"]
--end
--
--local function dnsTestField(dataTable)
--    local field = {}
--    local tmpField = {}
--    local nameArray = {"dns_status"}
--    log:Debugf("dns_status table:")
--    printTable(dataTable)
--    for _, name in pairs(nameArray) do
--        local tmp = dataTable[name]
--        if tmp == nil then
--            tmp = 0
--        end
--        tmpField[name] = tmp
--    end
--    log:Debugf("dns_status table:")
--    printTable(tmpField)
--    --field[1] = tmpField
--    --return field
--    return tmpField["dns_status"]
--end

local function pppoeField(dataTable, startTime, endTime, dataBox)
    local field = {}
    local tmpField = {}
    local nameArray = {"pppoe"}
    log:Debugf("pppoe table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            return nil
        end
        tmpField[name] = tmp
    end
    log:Debugf("pppoe table:")
    printTable(tmpField)
    return tmpField["pppoe"]
end

local function iptablesField(dataTable, startTime, endTime, dataBox)
    local field = {}
    local tmpField = {}
    local nameArray = {"iptables_count"}
    log:Debugf("iptables_count table:")
    printTable(dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            return nil
        end
        tmpField[name] = tmp
    end
    log:Debugf("iptables_count table:")
    printTable(tmpField)
    return tmpField["iptables_count"]
end


local function networkErrorField(dataTable, startTime, endTime, dataBox)
    local value = {}
    local tmpField = {}
    local tag = {}
    local nameArray = {"drop_ratio", "error_ratio"}
    --log:Debugf("Machine traffic table: %v", dataTable)
    for _, name in pairs(nameArray) do
        local tmp = dataTable[name]
        if tmp == nil then
            tmp = 0
        end
        tmpField[name] = tmp
    end

    tag = { machine_id = machine_id}

    table.insert(value, {tags = tag, fields = tmpField})
    log:Debugf("network error table: %v", value)
    return value
end

local dataSource = {
    quality = {
        category = "processor",
        name = "tcp_resend",
        dataVersion = "1",
        indicator = "tcp_resend",
        handler = qualityField
    },
    pppoe = {
        category = "input",
        name = "pppoe",
        dataVersion = "1",
        indicator = "pppoe",
        handler = pppoeField
    },
    iptables_rule = {
        category = "input",
        name = "iptables",
        dataVersion = "1",
        indicator = "iptables",
        handler = iptablesField
    }
}

function converge(startTime, endTime, dataBox)
    local curTime = os.time()
    local dataJson = ""
    fillTemplate()
    for name, item in pairs(dataSource) do
        local dataTable = getData(startTime, endTime, dataBox, item, false)
        if dataTable ~= nil then
            local field = item.handler(dataTable, startTime, endTime, dataBox)
            if field ~= nil then
                template.values[name] = field
            end
        end
    end

    dataJson = jsonMarshal(template)
    if dataJson ~= nil then
        dataBox:AddField(aggregator.category, aggregator.name, aggregator.dataVersion,
                aggregator.indicator, "", dataJson, curTime)
    end
end
