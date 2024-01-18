-- Marking: lua,input,line_tcp_resend,1

local input = {
    category = "input",
    name = "line_tcp_resend",
    dataVersion = "1",
    indicator = "line_tcp_resend"
}

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

local function stringStartWith(str, start)
    return string.sub(str,1,string.len(start))==start
end

local function ifnSkip(ifn)
    local if_skip = {"lo", "docker0"}
    for _, k in ipairs(if_skip) do
        if string.find(ifn, k) ~= nil then
            return true
        end
    end
    return false
end


local function getIndexOfString(str, stringsTable)
    local index = nil
    for i, w in ipairs(stringsTable) do
        if stringStartWith(w, str) then
            index = i
            break
        end
    end
    return index
end

local function splitAddress(ipString)
    --print(ipString)
    local ipTmp, ip = nil, nil
    if string.find(ipString, "]") ~= nil then
        local ipSplit = split(ipString, "]")
        if tableLen(ipSplit) >= 1 then
            local tmp = split(ipSplit[1], ":")
            ip = tmp[2]
        end
    else
        ipTmp = split(ipString, ":")
    end

    if ipTmp ~= nil then
        if tableLen(ipTmp) >= 1 then
            --print("ipTmp", ipTmp[1])
            -- split "%"
            if string.find(ipTmp[1], "%[") ~= nil then
                local ipSplitT = split(ipTmp[1], "%")
                ip = ipSplitT[1]
            else
                ip = ipTmp[1]
            end
        end
    end

    return ip
end

local function getIpLink()
    local ifnIp = {}
    local cmd = "ip -br a"
    local results = executeCmd(cmd)
    local lines = split(results, "\n")
    for _, line in pairs(lines) do
        --print(line)
        local lineSplit = split(line, " ")
        if tableLen(lineSplit) > 2 then
            if lineSplit[3] and ifnSkip(lineSplit[1]) == false then
                local ipString = split(lineSplit[3], " ")
                if tableLen(ipString) >= 1 then
                    local ipAddr = split(ipString[1], "/")
                    if tableLen(ipAddr) >= 1 then
                        local ifnString = split(lineSplit[1], "@")
                        if tableLen(ifnString) >= 1 then
                            ifnIp[ipAddr[1]] = ifnString[1]
                        end
                    end
                end
            end
        end
    end

    return ifnIp
end

local function parseOutout(data)
    local tcpSendOut = {}
    local tcpRetrans = {}
    local ipTable = {}
    for _, line in ipairs(data) do
        --print("line", line)
        --print(type(line))
        local words = split(line, " ")
        if words[1] == "ESTAB" then
            local ip = splitAddress(words[4])
            if ip ~= nil and ip ~=  "127.0.0.1"  then
                local sIndex = getIndexOfString("segs_out", words)
                if sIndex ~= nil then
                    local segsOutSplit = split(words[sIndex], ":")
                    ipTable[ip] = 1
                    if tableLen(segsOutSplit) >= 2 then
                        --print(segsOutSplit[1], segsOutSplit[2])
                        if tcpSendOut[ip] ~= nil then
                            tcpSendOut[ip] = tcpSendOut[ip] + tonumber(segsOutSplit[2])
                        else
                            tcpSendOut[ip] = tonumber(segsOutSplit[2])
                        end
                    end

                end
            end

            if string.find(line, "retrans") then
                local rIndex = getIndexOfString("retrans", words)
                if rIndex ~= nil then
                    local retransSegsTable = split(words[rIndex], ":")
                    if tableLen(retransSegsTable) >= 2 then
                       local retransSegsTable2 = split(retransSegsTable[2], "/")
                        if tableLen(retransSegsTable2) >= 2 then
                            local retransSegs = retransSegsTable2[2]
                            if tcpRetrans[ip] ~= nil then
                                tcpRetrans[ip] = tcpRetrans[ip] + tonumber(retransSegs)
                            else
                                tcpRetrans[ip] = tonumber(retransSegs)
                            end
                        end
                    end
                end
            end
        end

    end

    return ipTable, tcpSendOut, tcpRetrans
end

local function lineTcpRetrans()
    local curTime = os.time()
    local tcpRetransTable = {
        ["timestamp"] = curTime,
        ["retrans"] = {}
    }

    local machineId = machineID()
    local ifnIpTable = getIpLink()
    --for k, v in pairs(ifnIpTable) do
    --    print('ip ', k, v)
    --end
    local tcpSendOut, tcpRetransSegs, tcpRetrans = {}, {}, {}
    local ips = {}
    local cmd = "ss -nit  |grep -v 'Address:Port' | xargs -L 1"
    local result = executeCmd(cmd)
    local lines = split(result, "\n")
    local index = 1
    if lines ~= nil then
        ips, tcpSendOut, tcpRetransSegs = parseOutout(lines)
        for ip, _ in pairs(ips) do
            if ifnIpTable[ip] ~= nil and tcpRetransSegs[ip] ~= nil then
                local retrans = tcpRetransSegs[ip] / tcpSendOut[ip] * 100
                index = index + 1
                --tcpRetrans[ifnIpTable[ip]] = retrans

                local tags = {
                    ["machine_id"] = machineId,
                    ["name"] = ifnIpTable[ip],
                }

                local tmp_data = {
                    ["tags"] = tags,
                    ["fields"] = {
                        ["ratio"] = retrans
                    }
                }
                --print(retrans)
                tcpRetransTable["retrans"][index] = tmp_data
            end
        end
    end

    for k, v in pairs(tcpRetrans) do
        print(k, v)
    end
    --tcpRetransTable["retrans"] = tcpRetrans
    return tcpRetransTable
end
--getIpLink()

--lineTcpRetrans()
--test pass

function collect(out)
    local curTime = os.time()
    local statData = lineTcpRetrans()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
