-- Marking: lua,input,host_info,1

local input = {
    category = "input",
    name = "host_info",
    dataVersion = "1",
    indicator = "host_info"
}

local function fileExists(file)
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
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


local function hostUuid()
    local cmd = [=[
    NICS=$((echo "$(ls /sys/class/net | sort | uniq)"; echo "$(ls /sys/devices/virtual/net | sort | uniq)"; echo "$(ls /sys/devices/virtual/net | sort | uniq)";) | sort | uniq -u)
	MACS=$(for NIC in $NICS; do cat /sys/class/net/$NIC/address; done | tr '\n' ',' | sed 's/,$//')
	SYS_UUID=$(dmidecode -s system-uuid)
	PROC_ID=$(dmidecode -t processor | grep ID | head -1 | sed -r 's/ //g' | awk -F ':' '{print $2}')
	BOARD_ID=$(dmidecode -t system  | grep 'Serial Number' | sed 's/^.*Serial Number://' | sed 's/ //g')
	echo "$MACS;$SYS_UUID;$PROC_ID;$BOARD_ID" | md5sum | awk '{print $1}'
    ]=]
    local result = executeCmd(cmd)
    return result
end


local function hostInstallationId()
    local cmd = [=[
	if [ -f "/etc/installation-id" ]; then
		cat /etc/installation-id;
	else
		dbus-uuidgen | tee /etc/installation-id;
	fi
    ]=]
    local result = executeCmd(cmd)
    return result
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

local function uptime()
    local cmd = "cat /proc/uptime | awk '{split($1, a, \".\");print a[1]}'"
    local result = executeCmd(cmd)
    return tonumber(result)
end


local function hostName()
    local cmd = "hostnamectl --static"
    local result = executeCmd(cmd)
    return result
end

local function hostInfo()
    local curTime = os.time()
    local hostTable = {}
    local info = {}


    hostTable = {
        ["timestamp"] = curTime,
        ["hostinfo"] = {}
    }


    local machineId = machineID()

    info["hostname"] = hostName()
    info["uptime"] = uptime()

    local tags = {
        ["machine_id"] = machineId
    }
    local tmp_data = {
        ["tags"] = tags,
        ["fields"] = info
    }
    hostTable["hostinfo"][1] = tmp_data
    --hostTable["hostname"] = hostName()
    --hostTable["uptime"] = uptime()
    for k, v in pairs(hostTable) do
        print(k, v)
    end

    return hostTable
end

--hostInfo()
--test pass

function collect(out)
    local curTime = os.time()
    local statData = hostInfo()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
