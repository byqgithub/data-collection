-- Marking: lua,input,machine_traffic,1

local input = {
    machine = {
        category = "input",
        name = "machine_traffic",
        dataVersion = "1",
        indicator = "machine_traffic"
    },
    lines = {
        category = "input",
        name = "lines_traffic",
        dataVersion = "1",
        indicator = "lines_traffic"
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

local function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function (w)
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

local function tableLen(t)
    local len=0
    for _, _ in pairs(t) do
        len=len+1
    end
    return len;
end

local function executeCmd(cmd, timeout)
    if timeout == nil then
        timeout = 5
    end

    local result = ""
    local command = string.format("%s ", cmd)
    log:Debugf("Execute command: %v", command)
    local file = assert(io.popen(command, 'r'))
    if file == nil then
        log:Errorf("Execute command (%s) failed", cmd)
        return nil
    end

    file:flush() -- > important to prevent receiving partial output
    local output = file:read("*all")
    file:close()
    if (output ~= nil and string.len(output) > 0) then
        result = string.gsub(output, "^%s*(.-)%s*$", "%1")
    end
    --log:Debug(output)

    return result

end

local function getHardwareCard()
    local cmd="/bin/bash -c '(ls /sys/class/net; ls /sys/devices/virtual/net) | sort | uniq -u'"
    local result = executeCmd(cmd)
    return result
end

local function getLinesCard()
    local cmd = [[
    if [ $(ip addr | grep inet | grep ppp |wc -l) -gt 0 ];then
    ip addr | grep inet | grep global | grep ppp | while read line
    do
      ip=$( echo $line | awk -F/ '{print $1}' | awk '{print $2}' )
      dev=$(echo $line | awk '{print $NF}')
      echo "$dev"
    done
  elif [ $(ip addr | grep inet | grep wan |wc -l) -gt 0 ];then
    ip addr | grep inet | grep global | grep wan | while read line
    do
      ip=$( echo $line | awk -F/ '{print $1}' | awk '{print $2}' )
      dev=$(echo $line | awk '{print $NF}')
      echo "$dev"
    done
  else
    ip addr | grep inet | grep global | grep -v ppy | grep -v docker | while read line
    do
      ip=$( echo $line | awk -F/ '{print $1}' | awk '{print $2}' )
      dev=$(echo $line | awk '{print $NF}')
      echo "$dev"
    done
  fi
  ]]
    local result = executeCmd(cmd)
    return result
end

local function getTcpOutSegs()
    local cmd="cat /proc/net/snmp |grep Tcp | tail -n 1 | awk '{print $12}'"
    local result = executeCmd(cmd)
    local converted = 0
    if result ~= nil and string.len(result) > 0 then
        local tmp = tonumber(result)
        if tmp ~= nil then
            converted = tmp
        else
            log:Error("TCP out segs convert to number error")
        end
    else
        log:Errorf("Get TCP out segs error, result: %v", result)
    end
    return converted
end

local function getTcpRetransSegs()
    local cmd="cat /proc/net/snmp |grep Tcp | tail -n 1 | awk '{print $13}'"
    local result = executeCmd(cmd)
    local converted = 0
    if result ~= nil and string.len(result) > 0 then
        local tmp = tonumber(result)
        if tmp ~= nil then
            converted = tmp
        else
            log:Error("TCP retrans segs convert to number error")
        end
    else
        log:Errorf("Get TCP retrans segs error, result: %v", result)
    end
    return converted
end

local function readNetDev()
    local lines = {}
    local file = assert(io.open('/proc/net/dev', 'r'))
    local count = 0
    for line in file:lines(file) do
        count = count + 1
        lines[count] = line
    end
    file:close()
    --for _, v in pairs(lines) do
    --    log:Debugf("%v", v)
    --end
    return lines

end

local function linesTraffic(curTime, netDevTable)
    local netCardStr = getLinesCard()
    log:Debugf("Lines net cards: %v", netCardStr)
    local linesTrafficTable = {}
    if netCardStr == nil or string.len(netCardStr) <= 0 then
        return linesTrafficTable
    end

    for i, v in pairs(netDevTable) do
        repeat
            if (i <= 2) then
                break
            end

            local dataTable = split(v, " ")
            if (tableLen(dataTable) < 17) then
                break
            end

            local devName = split(dataTable[1], ":")
            if (devName == nil or tableLen(devName) < 1) then
                break
            end

            if (not string.find(netCardStr, devName[1])) then
                break
            end

            local data = {}
            local tmp = 0
            data["name"] = devName[1]
            data["timestamp"] = curTime
            data["bw_download"] = 0
            data["bw_upload"] = 0
            data["receive_packets"] = 0
            data["send_packets"] = 0

            tmp = tonumber(dataTable[2])
            if (tmp ~= nil) then data["bw_download"] = tmp end

            tmp = tonumber(dataTable[10])
            if (tmp ~= nil) then data["bw_upload"] = tmp end

            tmp = tonumber(dataTable[3])
            if (tmp ~= nil) then data["receive_packets"] = tmp end

            tmp = tonumber(dataTable[11])
            if (tmp ~= nil) then data["send_packets"] = tmp end

            log:Debugf("Line traffic data: %v", data)
            table.insert(linesTrafficTable, data)
        until true
    end

    return linesTrafficTable
end

local function parseData()
    local netCounters = {
        ["ReceiveBytes"] = 0,
        ["ReceivePackets"] = 0,
        ["SendBytes"] = 0,
        ["SendPackets"] = 0,
        ["DropPackets"] = 0,
        ["ErrorPackets"] = 0
    }
    local netCards = getHardwareCard()
    local tcpOutSegs = getTcpOutSegs()
    local tcpRetransSegs = getTcpRetransSegs()
    local curTime = os.time()
    local linesTable = readNetDev()

    for i, v in pairs(linesTable) do
        if i > 2 and v then
            local devTable = split(v, " ")
            if tableLen(devTable) == 17 then
                --log:Debugf("dev table: %v", devTable[1])
                local faceTable = split(devTable[1], ":")
                if tableLen(faceTable) == 1 then
                    if string.find(netCards, faceTable[1]) ~= nil then
                        netCounters["ReceiveBytes"] = netCounters["ReceiveBytes"] + tonumber(devTable[2])
                        netCounters["ReceivePackets"] = netCounters["ReceivePackets"] + tonumber(devTable[3])
                        netCounters["SendBytes"] = netCounters["SendBytes"] + tonumber(devTable[10])
                        netCounters["SendPackets"] = netCounters["SendPackets"] + tonumber(devTable[11])
                        netCounters["DropPackets"] = netCounters["DropPackets"] + tonumber(devTable[5]) + tonumber(devTable[13])
                        netCounters["ErrorPackets"] = netCounters["ErrorPackets"] + tonumber(devTable[4]) + tonumber(devTable[12])
                    end
                end
            end
        end
    end

    netCounters["TcpPackets"] = tcpOutSegs
    netCounters["TcpResendPackets"] = tcpRetransSegs
    netCounters["timestamp"] = curTime

    local linesTrafficData = linesTraffic(curTime, linesTable)

    log:Debugf("machine traffic: %v", netCounters)
    return netCounters, linesTrafficData
end

function collect(out)
    local curTime = os.time()
    local devData, linesData = parseData()
    local devJson = jsonMarshal(devData)
    local linesJson = jsonMarshal(linesData)

    log:Debugf("Dev data json: %v", devJson)
    out:AddField(input.machine.category, input.machine.name, input.machine.dataVersion,
            input.machine.indicator, "", devJson, curTime)

    log:Debugf("lines Data json: %v", linesJson)
    out:AddField(input.lines.category, input.lines.name, input.lines.dataVersion,
            input.lines.indicator, "", linesJson, curTime)
end
