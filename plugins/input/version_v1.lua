-- Marking: lua,input,client_version,1

local input = {
    category = "input",
    name = "client_version",
    dataVersion = "1",
    indicator = "client_version"
}

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

local function iptableVersion()
    local version = ""
    local dacachecmd = "iptables-save | grep \"HOST_INPUT\" | wc -l"
    local ifdcache = executeCmd(dacachecmd)
    if (tonumber(ifdcache) > 0) then
        version= version .. "dcache-keeper"
    end

    ifdcache = executeCmd("iptables-save | grep \"PAI_DNAT\" | wc -l")
    if (tonumber(ifdcache) > 0) then
        version = version .. "iptables-keeper"
    end

    if version == "" then
        version = "none"
    end
    return version
end

local function clientVersion()
    local curTime = os.time()
    local versionTable = {
        ["timestamp"] = curTime,
        ["version"] = {}
    }
    local allVersion = {

    }
    local machineId = machineID()

    local paicollectcmd = "paicollect -v 2>/dev/null | tail -n 1"
    allVersion["paicollect"] = executeCmd(paicollectcmd)

    local paitrafficcmd = "/ipaas/traffic/bin/paitraffic -v 2>/dev/null | tail -n 1"
    allVersion["paitraffic"] = executeCmd(paitrafficcmd)

    local proxycmd = "paiproxy -v 2>/dev/null || echo '0.0.0'"
    allVersion["paiproxy"] = executeCmd(proxycmd)

    local pairatcmd = "pairat -v 2>/dev/null | awk '{print $3}' || echo '0.0.0'"
    allVersion["pairat"] = executeCmd(pairatcmd)

    local pairobotcmd = "pairobot -v 2>/dev/null | awk '{print $3}'"
    local pairobotversion = executeCmd(pairobotcmd)
    if pairobotversion == "" then
        pairobotversion = "0.0.0"
    end
    allVersion["pairobot"] = pairobotversion

    local painullcmd = "painull -v 2>/dev/null"
    allVersion["painull"] = executeCmd(painullcmd)

    local paipppoecmd = "jq -r '.version' /dev/shm/pai_pppoe.status 2>/dev/null"
    local pppoeversion  = executeCmd(paipppoecmd)
    if pppoeversion == nil or pppoeversion == "" then
        paipppoecmd = "find /sys/class/net/ -name \"ppp*\" | wc -l"
        local pp = executeCmd(paipppoecmd)
        if (tonumber(pp) > 0) then
            pppoeversion = "0.0.1"
        else
            pppoeversion = "0.0.0"
        end
    end
    allVersion["pppoe"] = pppoeversion


    allVersion["iptables"] = iptableVersion()
    for k, v in pairs(allVersion) do
        print(k, v)
    end

    local tags = {
        ["machine_id"] = machineId
    }
    local tmp_data = {
        ["tags"] = tags,
        ["fields"] = allVersion
    }

    versionTable["version"][1] = tmp_data
    --versionTable["count"] = tonumber(iptableCountRule())
    return versionTable

end

--clientVersion()
--test pass

function collect(out)
    local curTime = os.time()
    local statData = clientVersion()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end


