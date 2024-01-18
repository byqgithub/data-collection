-- Marking: lua,input,dial_type,1

local input = {
    category = "input",
    name = "dial_type",
    dataVersion = "1",
    indicator = "dial_type"
}

local OUTER_TEST_URL="47.114.74.103:60080"

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
    local command = string.format("timeout %d %s ", timeout, cmd)
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

local function findDevIp(ifce)
    local cmd="ip addr show " .. ifce .. " | grep inet | grep global | awk -F/ '{print $1}' | awk '{print $2}'"
    print(cmd)
    local ip = executeCmd(cmd)
    return ip
end

local function findDevOuterIp(dev)
    local cmd="curl --interface " .. dev .. " --connect-timeout 2 -m 3 " .. OUTER_TEST_URL .. " 2>/dev/null"
    print(cmd)
    local result=executeCmd(cmd)
    local outIp=split(result, ":")
    return outIp[1]
end

local function isPublicIp(devIp, dev)
    local outerIp = findDevOuterIp(dev)

    if devIp == outerIp then
        return 1
    else
        return 0
    end
end

local function checkNetType()
    local curTime = os.time()
    --local machineId = machineID()
    local netType = {
        ["timestamp"] = curTime,
        ["dial_type"] = nil
    }
    --local dial_type = {
    --    ["fields"] = {
    --        ["dial_type"] = 1
    --    },
    --    ["tags"] = {
    --        ["machine_id"] = machineId
    --    }
    --}

    local pppcmd = "ip addr | grep ppp | grep inet | wc -l"
    local pppCount = executeCmd(pppcmd)

    if tonumber(pppCount) > 0 then
        --netType["dial_type"][1] = dial_type
        netType["dial_type"] = 1
        return netType
    end

    local wancmd = "ip addr | grep wan | grep inet | wc -l"
    local wanCount = executeCmd(wancmd)
    if tonumber(wanCount) > 0 then
        local devIp = findDevIp("wan0")
        local ispublicIp = isPublicIp(devIp, "wan0")

        if ispublicIp == 1 then
            netType["dial_type"] = 5
            --dial_type["fields"]["dial_type"] = 5
        else
            netType["dial_type"] = 2
            --dial_type["fields"]["dial_type"] = 2
        end
        --netType["dial_type"][1] = dial_type
        return netType
    end

    local cmd = "ip addr | grep inet | grep -v inet6 | grep global | grep -v docker | grep -v ppy | grep -v \"br-\" | grep -v veth | grep -v mgt"

    local res = executeCmd(cmd)
    local result = split(res, "\n")
    print(tableLen(result))
    for _, v in pairs(result) do
        local tmpSplit = split(v, " ")
        local ipSplit = split(tmpSplit[2], "/")
        local dev = tmpSplit[#tmpSplit]
        local ispublibIp = findDevOuterIp(ipSplit[1], dev)
        if ispublibIp == 1 then
            --dial_type["fields"]["dial_type"] = 4
            --netType["dial_type"][1] = dial_type
            netType["dial_type"] = 4
            return netType
        end
    end
    netType["dial_type"] = 3
    --dial_type["fields"]["dial_type"] = 3
    --netType["dial_type"][1] = dial_type
    --for k, v in pairs(natT) do
    --    print(k, v)
    --end
    return netType

end

--checkNetType()
--test pass

function collect(out)
    local curTime = os.time()
    local statData = checkNetType()

    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end

