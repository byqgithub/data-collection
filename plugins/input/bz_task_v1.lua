-- Marking: lua,input,bz_task,1

local input = {
    category = "input",
    name = "bz_task",
    dataVersion = "1",
    indicator = "bz_task"
}

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

local function executeCmd(cmd, timeout)
    if timeout == nil then
        timeout = 60
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

local function hasValue(tab, val)
    if tab == nil then
        return false
    end

    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

local function systemDiskUsage()
    local usage = 0.0
    local size = 0
    local cmd = "df -a | grep -w '/' | awk '{printf\"%d#%d\", $2, $3}'"
    local systemDisk = executeCmd(cmd)
    local systemDiskSplit = split(systemDisk, "#")
    if tableLen(systemDiskSplit) == 2 then
        size = tonumber(systemDiskSplit[1])
        usage = tonumber(systemDiskSplit[2] / systemDiskSplit[1] * 100)
    end
    return size, usage
end

local function upTime()
    local cmd = "cat /proc/uptime | awk '{split($1, a, \".\");print a[1]}'"
    local result = executeCmd(cmd)
    return tonumber(result)
end

local function onlyMachineTraffic(taskTags, specialTasks)
    --log:Debugf("specialTasks: %v", specialTasks)
    local taskArray = {}
    local only = false
    for _, taskTag in pairs(taskTags) do
        if string.match(taskTag, "pai-%a*-%d*") then
            local tmp = split(taskTag, "-")
            if tableLen(tmp) == 3 then
                table.insert(taskArray, tmp[2])
            end
            --else
            --    table.insert(taskArray, taskTag)
        end
    end

    local num = 0
    for _, task in pairs(taskArray) do
        if hasValue(specialTasks, task) then
            num = num + 1
        end
    end

    if num == tableLen(taskArray) then
        only = true
    end

    log:Debugf("onlyMachineTraffic: %v", only)
    log:Debugf("Machine task: %v", taskArray)
    return only, taskArray
end

local function getTaskTag(configTable)
    local taskTags = {}
    local rootPath = configTable["plugin_root_path"]
    local folder = string.format("%s/../output", rootPath)
    local fileName = "runningTask.txt"
    local command = string.format(
            "flock -x -w 3 %s/file.lock -c 'cat %s/%s'",
            folder, folder, fileName)
    local result = executeCmd(command)
    if string.len(result) > 0 then
        taskTags = split(result, '\n')
    end

    log:Debugf("Get task tags: %v", taskTags)
    return taskTags
end

local function realCheckMachine(taskName, customId, bsFlowUpload, bsRunSuccess)
    local size, usage = systemDiskUsage()
    local uptime = upTime()
    local docker = {}
    local machineId = machineID()
    local task = {
        ["name"] = taskName,
        ["idx"] = 1,
        ["version"] = "0.0.0",
        ["version_program"] = "0.0.0",
        ["bw_upload"] = 0,
        ["bs_bw_upload"] = bsFlowUpload,
        ["bw_download"] = 0,
        ["bw_config"] = 0,
        ["storage_type"] = "hdd",
        ["storage_size"] = size,
        ["storage_usage"] = usage,
        ["ping_ttl"] = 0,
        ["ping_time"] = 0,
        ["ping_success"] = 0,
        ["cpu_usage"] = 0,
        ["mem_size"] = 0,
        ["mem_usage"] = 0,
        ["outgoing"] = 0,
        ["incoming"] = 0,
        ["running_status"] = bsRunSuccess,
        ["outer_ip"] = "0.0.0.0",
        ["running_count"] = 2,
        ["network_mode"] = "program",
        ["image_tag"] = "",
        ["base_image_tag"] = "",
        ["line_cnt"] = 0,
        ["bw_upload_line"] = 0,
        ["user_speed_count"] = 0,
        ["user_speed_gt_zero_count"] = 0,
        ["user_avg_speed"] = 0,
        ["provider"] = "",
        ["provider_id"] = "",
        ["uptime"] = uptime,
        ["special_line"] = 0,
        ["private_line"] = 0,
        ["support_https"] = 0,
        ["raw_storage_size"] = 0,
        ["raw_storage_devices"] = ""
    }

    local tags = {
        ["machine_id"] = machineId,
        ["docker_id"] = "",
        ["custom_id"] = customId
    }
    local tmp_docker = {
        ["tags"] = tags,
        ["fields"] = task
    }
    docker[1] = tmp_docker
    return docker
end

local function bzBsBw()
    local cmd = [=[
#!/bin/bash
if [ ! -f /data/app/portal_pin/logs/portal_pin.log ]; then
	echo "0+0+1"
	exit 0
fi
errnum=$(tail -n100 /data/app/portal_pin/logs/portal_pin.log | grep ^ERROR | wc -l)
cat /data/app/portal_pin/logs/portal_pin.log|awk '{if($4=="incoming" && $6=="outgoing")print$2,$5,$7}'|tail -n10|awk -ve=${errnum} '{a+=$2;b+=$3;c=$1}END{printf "%.f+%.f+%.f+%s\n",a*8/10,b*8/10,e,c}'
    ]=]
    local result = executeCmd(cmd)
    local words = split(result, "+")
    if tableLen(words) < 4 then
        return 0, 1
    end

    local flow_upload = tonumber(words[2])
    local error_count = tonumber(words[3])

    local tag = words[4]
    -- TODO
    return flow_upload, error_count
end

local function bzTask(taskName)
    local hostname = executeCmd("hostnamectl | grep \"Static hostname\"")
    log:Debugf("Local hostname: %v", hostname)
    local flow_upload, error_count = bzBsBw()
    return realCheckMachine(taskName, hostname, flow_upload, error_count == 0)
end

function collect(out, configObject)

    local curTime = os.time()
    local taskData = {
        ["timestamp"] = curTime,
        ["bz"] = {}
    }
    local globalStr = configObject:ConfigRawContent("global")
    local globalConfig = jsonUnMarshal(globalStr)
    local recognitionString = configObject:ConfigRawContent("recognition")
    local recognitionConfig = jsonUnMarshal(recognitionString)
    local taskSNStr = configObject:ConfigRawContent("businesses")
    local taskSNConfig = jsonUnMarshal(taskSNStr)
    local collectPidStr = configObject:ConfigRawContent("collect_pid")
    local collectPidConfig = jsonUnMarshal(collectPidStr)

    local trafficArray = {}
    local taskTags = getTaskTag(globalConfig)
    local only, trafficArray = onlyMachineTraffic(taskTags, recognitionConfig["specific"])
    if only then
        log:Info("Only collect hardware network card traffic")
        print(trafficArray)
        if hasValue(taskArray, "bz") then
            taskData["bz"] =  bzTask("bz")

        elseif hasValue(taskArray, "bzl") then
            taskData["bz"] =  bzTask("bzl")

        end
    end

    for key, data in pairs(taskData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(taskData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end

