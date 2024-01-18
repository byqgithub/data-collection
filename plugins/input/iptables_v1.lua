-- Marking: lua,input,iptables,1

local input = {
    category = "input",
    name = "iptables",
    dataVersion = "1",
    indicator = "iptables"
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

local function paiIptables()
    local curTime = os.time()
    local iptablesTable = {
        ["timestamp"] = curTime,
        ["iptables_count"] = {}

    }
    local iptable = {
        ["fields"] = {},
        ["tags"] = {
            ["machine_id"] = machineID()
        }
    }
    iptable["fields"]["cnt"] = executeCmd("iptables-save | wc -l")

    --local version = ""
    --local dacachecmd = "iptables-save | grep \"HOST_INPUT\" | wc -l"
    --local ifdcache = executeCmd(dacachecmd)
    --if (tonumber(ifdcache) > 0) then
    --    version= version .. "dcache-keeper"
    --end
    --
    --ifdcache = executeCmd("iptables-save | grep \"PAI_DNAT\" | wc -l")
    --if (tonumber(ifdcache) > 0) then
    --    version = version .. "iptables-keeper"
    --end
    --
    --if version == "" then
    --    version = "none"
    --end
    --iptable["fields"]["version_iptables"] = version

    --for k, v in pairs(iptablesTable) do
    --    print(k, v)
    --end
    iptablesTable["iptables_count"][1] = iptable
    return iptablesTable
end


--paiIptables()
--test pass
function collect(out)
    local curTime = os.time()
    local statData = paiIptables()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end