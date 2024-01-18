-- Marking: lua,input,hardware_error,1

local input = {
    category = "input",
    name = "hardware_error",
    dataVersion = "1",
    indicator = "hardware_error"
}

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

local function checkHardwareError()
    local curTime = os.time()
    local machineId = machineID()
    local hardTable = {
        ["timestamp"] = curTime,
        ["hard_error"] = {}
    }
    local mem_cmd = "grep '[0-9]' /sys/devices/system/edac/mc/mc*/csrow*/ch*_ce_count 2>/dev/null | awk -F':' '{a=0}END{a+=$2}END{print a}'"
    local mem_err = executeCmd(mem_cmd, 5)
    local timestring=os.date("%b %d %H", os.time())
    local grepstring=string.format("cat /var/log/messages | grep -iP '^%s", timestring)
    --print(grepstring)
    local disk_cmd = grepstring .. ".+ kernel: (blk_update_request: (I/O error|critical medium error)|Buffer I/O error|ata.+: error|sd.+(Medium Error|read error)|.+(xfs_error_report|xfs_corruption_error)|XFS.+error)' | grep -v 'dev fd0' | wc -l"
    --print(disk_cmd)
    local disk_err = executeCmd(disk_cmd, 5)
    --print(mem_err, disk_err)
    local tmp = {
        ["mem_hd"] = tonumber(mem_err),
        ["disk_hd"] = tonumber(disk_err),
    }
    local hard_error = {
        ["fields"] = tmp,
        ["tags"] = {
            ["machine_id"] = machineId
        }
    }
    hardTable["hard_error"][1] = hard_error
    for k, v in pairs(hardTable) do
        print(k, v)
    end
    return hardTable
end

--checkHardwareError()
--test pass
function collect(out)
    local curTime = os.time()
    local statData = checkHardwareError()

    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
