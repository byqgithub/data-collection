-- Marking: lua,input,task_traffic,1

local input = {
    category = "input",
    name = "task_traffic",
    dataVersion = "1",
    indicator = "task_traffic"
}

-- iptables operational order
local order = {
    -- IPv4
    ipv4 = {
        checkoutRules ="iptables-save -t %s",
        checkoutRulesByteCounters = "iptables-save -c -t %s",
        restoreRules = "iptables-restore -w 30 --noflush --table=%s < %s"
    },
    -- IPv6
    ipv6 = {
        checkoutRules = "ip6tables-save -t %s",
        checkoutRulesByteCounters = "ip6tables-save -c -t %s",
        restoreRules = "ip6tables-restore -w 30 --noflush --table=%s < %s"
    }
}

-- iptables rule template
--local createNewChain = ":%s - [0:0]"
--local referenceRule = "-A %s -j %s"
local customChainNameDict = {
    raw_output = "PCDN_OUTPUT_CGROUP",
    filter_output = "PAI_OUTPUT_CGROUP"
}
--local addRuleTemplateDict = {
--    raw_output = "-A %s ! -o lo -m cgroup --cgroup %s -j RETURN",
--    filter_output = "-A %s -m addrtype ! --dst-type LOCAL -m cgroup --cgroup %s -j RETURN"
--}
--local delRuleTemplate = "-D %s"
--local delReferenceRuleTemplate = "-D %s -j %s"
--local delCustomChain = "-X %s"

-- iptables rule regular
--local customChainRegular = r":%s\s*-\s*\[\d*:\d*]"
local ruleRegular = "%-m cgroup %-%-cgroup"
--local ruleByteCountersRegular = r"%[%d*:%d*]%s*-A %s.*-m cgroup --cgroup %d* -j.*"

local netStatisticsTx = "/sys/class/net/%s/statistics/tx_bytes"
local netStatisticsRx = "/sys/class/net/%s/statistics/rx_bytes"
local netClsBasePath = "/sys/fs/cgroup/net_cls"
local findNetClsPath = "find %s/* -name %s"
local netDevPath = "/proc/%s/net/dev"
--local bdfdInquireCustomId = "docker exec %s cat /PCDN/id"
--local bdwphjInquireCustomId = "docker exec %s cat /storage/bdlog/BaiduYunKernel/config.ini"
--local keywordDict = {
--    bdfd = "LIBSOCKBIND_DEVICE",
--    bdwphj = "LIBSOCKBIND_DEVICE",
--    bdx = "NET_CARD"
--}

local function fileExists(path)
    local file, _ = io.open(path, "rb")
    if file then
        file:close()
    end
    return file ~= nil
end

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
    if str == nil or type(str) ~= "string" then
        return resultStrList
    end

    string.gsub(str,'[^'..reps..']+',function (w)
        table.insert(resultStrList, w)
    end)
    return resultStrList
end

local function strip(str)
    if str == nil or type(str) ~= "string" then
        return ""
    end

    return string.gsub(str, "^%s*(.-)%s*$", "%1")
end

local function tableLen(t)
    local len=0
    for _, _ in pairs(t) do
        len=len+1
    end
    return len;
end

local function basename(path)
    local name = ""
    local sections = split(path, "/")
    if sections ~= nil and tableLen(sections) > 0 then
        name = sections[tableLen(sections)]
    end
    return name
end

local function isInTable(tb, value)
    if tb == nil then
        return false
    end

    for _, v in pairs(tb) do
        if value == v then
            return true
        end
    end
    return false
end

local function executeCmd(cmd, timeout)
    if timeout == nil then
        timeout = 5  -- default timeout: 5s
    end

    local result = ""
    local command = string.format("%s ", cmd)
    log:Debugf("executeCmd command: %v", command)
    local file = io.popen(command)
    if nil == file then
        log:Errorf("Execute command (%s) failed", cmd)
        return result
    end
    file:flush()  -- > important to prevent receiving partial output
    local output = file:read('*all')
    file:close()
    if (output ~= nil and type(output) == "string" and string.len(output) > 0) then
        result = strip(output)
    end

    return result
end

local function isSupportIPv6()
    local ifInet6 = "/proc/net/if_inet6"
    local result = false
    if not fileExists(ifInet6) then
        return result
    end

    local fh, _ = io.open(ifInet6, "r")
    if fh == nil then
        return result
    end

    for line in fh:lines() do
        repeat
            if line == nil or type(line) ~= "string" or string.len(line) == 0 then
                break
            end

            local content = split(strip(line), '\n')
            if content ~= nil and tableLen(content) >= 4 then
                local scopeid = tonumber(content[4], 10)
                if scopeid ~= nil and scopeid == 0 then
                    log:Debug("Current device support IPv6")
                    result = true
                    break
                end
            end
        until true

        if result == true then
            break
        end
    end
    fh:close()

    return result
end

local function iptablesOperator(protocol, action, ...)
    local cmd = ""
    local result = ""
    if protocol == "ipv4" then
        cmd = order["ipv4"][action]
    elseif protocol == "ipv6" then
        cmd = order["ipv6"][action]
    else
        log:Debug("Nonsupport protocol type")
    end

    if cmd ~= nil then
        result = executeCmd(string.format(cmd, ...))
    end

    if string.len(result) <= 0 then
        result = "EXCEPTION"
    end

    return result
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
        if isInTable(specialTasks, task) then
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

local function isPauseImage(info)
    local include = false
    local image = info["Config"]["Image"]
    log:Debugf("Container id: %v, image: %v", info["Id"], image)
    if image == nil or string.len(image) <= 0 then
        return include
    end

    local sections = split(image, "/")
    if tableLen(sections) <= 0 then
        return include
    end

    if string.find(sections[tableLen(sections)], "pause") then
        include = true
    end
    return include
end

local function getTaskFromContainerInfo(containerInfo)
    local taskTag = "pai-default-0"
    if containerInfo == nil then
        return taskTag
    end

    if containerInfo["Name"] ~= nil then
        log:Debugf("containerInfo name: %v", containerInfo["Name"])
        if containerInfo["Name"] == "/ipes-lcache" then
            return "pai-dcache-0" -- no index, default 0
        end
    end

    if containerInfo["Config"] == nil then
        return taskTag
    end

    local envArray = containerInfo["Config"]["Env"]
    if envArray == nil then
        return taskTag
    end

    for _, value in pairs(envArray) do
        local tmpTable = split(value, "=")
        if tableLen(tmpTable) >= 2 then
            if tmpTable[1] == "PAI_TASK_NAME" then
                taskTag = string.lower(strip(tmpTable[2]))
                break
            elseif tmpTable[1] == "TASK_NAME" then
                taskTag = string.lower(strip(tmpTable[2]))
                taskTag = string.format("pai-%s-0", taskTag)
                break
            end
        end
    end

    return taskTag
end

local function searchNetClsPath(containerInfo)
    local path = ""
    local cId = ""
    if containerInfo["Id"] == nil then
        return path
    else
        cId = containerInfo["Id"]
    end

    if containerInfo["HostConfig"] == nil then
        return path
    end
    local pathConfig = containerInfo["HostConfig"]["CgroupParent"]
    if pathConfig ~= nil then
        local pathBasename = basename(pathConfig)
        local basePath = executeCmd(string.format(findNetClsPath, netClsBasePath, pathBasename))
        if string.len(basePath) > 0 and tableLen(split(basePath, "/")) > 1 then
            path = string.format("%s/%s/net_cls.classid", basePath, cId)
        elseif string.len(basePath) > 0 then
            path = string.format("%s/docker-%s.scope/net_cls.classid", basePath, cId)
        else
            log:Debugf("Can not find net_cls path, docker id %s, config %s", cId, pathConfig)
        end
    end

    if string.len(path) <= 0 then
        local tmp = string.format("docker-%s.scope",  cId)
        local basePath = executeCmd(string.format(findNetClsPath, netClsBasePath, tmp))
        if string.len(basePath) > 0 then
            path = string.format("%s/net_cls.classid", basePath)
        else
            path = string.format("%s/docker/%s/net_cls.classid", netClsBasePath, cId)
        end
    end

    return path
end

local function readCgroupNetClassId(filePath)
    local classId = 0

    local fh, _ = io.open(filePath, "r")
    if fh == nil then
        return classId
    end

    local output = fh:read('*all')
    fh:close()
    if output ~= nil and type(output) == "string" then
        output = strip(output)
        local num = tonumber(output, 10)
        if num ~= nil and num > 0 then
            classId = num
        end
    end

    return classId
end

local function readContainerNetClassId(containerInfo)
    local filePath = searchNetClsPath(containerInfo)
    return readCgroupNetClassId(filePath)
end

--local function generateOffset(cId)
--    if cId == nil or type(cId) ~= "string" then
--        return 11111
--    end
--    local offset = tonumber(string.sub(cId, -10), 16)
--    --log:Debugf("Cid: %s, offset: %v", cId, offset)
--    if offset == nil then
--        return 11111
--    end
--    if offset <= 0 then
--        offset = offset * -1
--    end
--    local tmp = tostring(offset)
--    if tmp == nil then
--        return 11111
--    end
--    if string.len(tmp) < 5 then
--        return 11111
--    end
--    offset = tonumber(string.sub(tmp, 1, 5), 10)
--    if offset == nil or offset == 0 then
--        return 11111
--    end
--    return offset
--end

local function generateOffset(cId)
    if cId == nil or type(cId) ~= "string" then
        return 11111
    end
    local cmd = string.format("/usr/bin/python3 /opt/scripts/generate_offset.py %s", cId)
    local offset = executeCmd(cmd)
    if offset == nil or offset == 0 then
        return 11111
    end
    return offset
end

local function generateClassId(taskTag, cId, taskSN)
    local classId = 0
    local sections = split(taskTag, "-")
    if tableLen(sections) < 3 then
        return classId
    end

    --log:Debugf("Task tag section: %v", sections)
    local taskName = sections[2]
    local index = tonumber(sections[3], 10)
    if index == nil then
        log:Error("Generate classId error: index == nil")
        return classId
    end
    local sn = tonumber(taskSN[taskName], 10)
    if sn == nil then
        log:Error("Generate classId error: can not get task SN, set 0")
        sn = 0
    end
    local offset = tonumber(generateOffset(cId))
    if offset == 0 then
        log:Debug("Generate classId warning: offset == 0")
    end

    log:Debugf("SN: %v, index: %v, offset: %v", sn, index, offset)
    local tmp = bitOR(bitAND(offset, 0xFFFF), bitLeftShift(bitAND(sn, 0xFF), 16))
    classId = bitOR(tmp, bitLeftShift(bitAND(index, 0xFF), 24))
    --local tmp = bitOR(bitAND(offset, 0xFFFF), bitLeftShift(bitAND(sn, 0xFF), 16))
    --classId = bitOR(tmp, bitLeftShift(bitAND(index, 0xFF), 24))
    log:Debugf("TEST class id: %.f", classId)
    return classId
end

local function verifyNetClassId(classId, cId, taskTag, taskSN)
    -- Check whether gid matches containers id, task tag or process task tag
    -- Note:
    --   containers: gid must match whit containers id, task tag
    --   process:    gid only match task tag, containers id = 1
    if classId == nil or classId <= 0 then
        return false
    end
    local value = generateClassId(taskTag, cId, taskSN)
    if value == classId then
        return true
    else
        return false
    end
    return true
end

local function getNetworkMode(info, infoTable)
    local networkMode = ""
    local config = ""
    local cId = info["Id"]
    if cId == nil then
        return networkMode
    end

    if info["HostConfig"] == nil then
        config = ""
    elseif info["HostConfig"]["NetworkMode"] == nil then
        config = ""
    else
        config = info["HostConfig"]["NetworkMode"]
    end

    if string.find(config, "host") then
        networkMode = "host"
    elseif string.find(config, "container:") then
        local tmp = split(config, ":")
        if tmp ~= nil and tableLen(tmp) >= 2 then
            local fatherInfo = infoTable[tmp[2]]
            local fatherConfig = ""
            if fatherInfo["HostConfig"] == nil then
                fatherConfig = ""
            elseif fatherInfo["HostConfig"]["NetworkMode"] == nil then
                fatherConfig = ""
            else
                fatherConfig = fatherInfo["HostConfig"]["NetworkMode"]
            end
            if string.find(fatherConfig, "host") then
                networkMode = "host"
            end
        end
    else
        networkMode = "bridge"
    end

    return networkMode
end

local function extractContainerInfo(containerInfo, allContainerInfo, taskSN)
    local classId = readContainerNetClassId(containerInfo)
    local taskTag = getTaskFromContainerInfo(containerInfo)
    local correctFormat = "Correct to verify container %s classId, container info: %v"
    local errorFormat = "Failed to verify container %s classId, container info: %v"

    if not verifyNetClassId(classId, containerInfo["Id"], taskTag, taskSN) then
        log:Errorf(errorFormat, containerInfo["Name"], containerInfo)
        return nil
    end

    local infoTable = {}
    if containerInfo["Id"] ~= nil then
        infoTable["id"] = containerInfo["Id"]
    else
        infoTable["id"] = ""
    end

    if containerInfo["Name"] ~= nil then
        infoTable["name"] = containerInfo["Name"]
    else
        infoTable["name"] = ""
    end

    if containerInfo["State"] == nil then
        infoTable["pid"] = -1
    elseif containerInfo["State"]["Pid"] == nil then
        infoTable["pid"] = -1
    else
        infoTable["pid"] = containerInfo["State"]["Pid"]
    end

    infoTable["classId"] = classId
    infoTable["mode"] = getNetworkMode(containerInfo, allContainerInfo)
    local tmpArray = split(taskTag, "-")
    if tmpArray ~= nil and tableLen(tmpArray) == 3 then
        infoTable["task"] = tmpArray[2]
    else
        infoTable["task"] = ""
    end

    infoTable["custom_id"] = ""
    infoTable["binding"] = ""
    log:Debugf(correctFormat, containerInfo["Name"], infoTable)

    return infoTable
end

local function collectContainerInfo(taskSN, detail)
    local infoStr = containersInfo()
    local infoTable = jsonUnMarshal(infoStr)
    for cId, info in pairs(infoTable) do
        repeat
            if isPauseImage(info) then
                break
            end

            local tmpTable = extractContainerInfo(info, infoTable, taskSN)
            if tmpTable ~= nil then
                detail[cId] = tmpTable
            end
        until true
    end
end

local function generateCgroupPath(taskName)
    local path = string.format("%s/%s", netClsBasePath, taskName)
    local cmd = string.format("mkdir -p %s 2>&1", path)
    local result = executeCmd(cmd)
    if string.len(result) > 0 then
        log:Debugf("cmd: %s, error: %s", cmd, result)
    end
    return path
end

local function getProcessNetClassId(cgroupPath)
    local filePath = string.format("%s/%s", cgroupPath, "net_cls.classid")
    return readCgroupNetClassId(filePath)
end

local function extractProcessInfo(taskName, pidStr, taskSN)
    local taskTag = string.format("pai-%s-0", taskName)
    local cgroupPath = generateCgroupPath(taskName)
    local classId = getProcessNetClassId(cgroupPath)
    local correctFormat = "Correct process name %s info: %v"
    local errorFormat = "Error process name %s task tag(%s) and classId(%s) verify failed"

    if not verifyNetClassId(classId, 1, taskTag, taskSN) then
        log:Errorf(errorFormat, taskName, taskTag, classId)
        return nil
    end

    local infoTable = {}
    infoTable["id"] = pidStr
    infoTable["name"] = taskName
    infoTable["pid"] = pidStr
    infoTable["classId"] = classId
    infoTable["mode"] = "host"  -- must host, collect traffic from iptables output
    infoTable["task"] = taskName
    infoTable["custom_id"] = ""
    infoTable["binding"] = ""
    log:Debugf(correctFormat, taskName, infoTable)

    return infoTable
end

local function collectProcessInfo(cmdTable, taskSN, detail)
    local errorFormat = "Task: %s, cmd: %s, fetch invalid pid: %s"
    if cmdTable == nil then
        return
    end

    for name, cmd in pairs(cmdTable) do
        repeat
            if string.find(name, "_pid") then
                break
            end

            local pidStr = executeCmd(cmd)
            local pid = tonumber(pidStr, 10)
            if pid == nil or pid <= 1 then
                log:Errorf(errorFormat, name, cmd, pidStr)
                break
            end

            local tmpTable = extractProcessInfo(name, pidStr, taskSN)
            if tmpTable ~= nil then
                detail[pidStr] = tmpTable
            end
        until true
    end
end

local function readTrafficForBridge(pid)
    log:Debug("Docker bridge network mode")
    local uploadBytes = 0

    local devPath = string.format(netDevPath, pid)
    if not fileExists(devPath) then
        return uploadBytes
    end

    local fh, _ = io.open(devPath, "r")
    if fh == nil then
        return uploadBytes
    end

    local result = {}
    fh:flush()  -- > important to prevent receiving partial output
    local output = fh:read('*all')
    fh:close()
    if (output ~= nil and type(output) == "string" and string.len(output) > 0) then
        result = split(strip(output), "\n")
    end
    for _, line in pairs(result) do
        repeat
            if not string.find(line, "eth0:") then
                break
            end

            --log:Debugf("Docker net dev data %v", line)
            local tmp = split(strip(line), " ")
            if tableLen(tmp) < 10 then
                break
            end

            local bytes = tonumber(tmp[10])
            if bytes ~= nil then
                uploadBytes = bytes + uploadBytes
            end
        until true
    end

    return uploadBytes
end

local function parseTrafficForHost(iptablesOutput)
    local uploadBytes = 0
    log:Debug("Docker host network mode")
    if iptablesOutput == nil or tableLen(iptablesOutput) < 1 then
        return uploadBytes
    end

    local dataArray = split(iptablesOutput[1], ":")
    if tableLen(dataArray) < 2 then
        return uploadBytes
    end

    local tmpData = string.sub(dataArray[2], 1, string.len(dataArray[2]) - 1)
    if tmpData == nil then
        return uploadBytes
    end

    uploadBytes = tonumber(tmpData)
    if uploadBytes ~= nil then
        return uploadBytes
    else
        return 0
    end
end

local function trafficUpload(networkMode, pid, iptablesOutput)
    local uploadBytes = 0

    if networkMode == "bridge" then
        uploadBytes = readTrafficForBridge(pid)
    elseif networkMode == "host" then
        uploadBytes = parseTrafficForHost(iptablesOutput)
    else
        uploadBytes = 0
        log:Debugf("Pid %v can not match network mode", pid)
    end

    return tonumber(uploadBytes)
end

local function matchData(detail, output, protocol, customChainName)
    local uploadBytes = 0
    if "ipv6" == protocol and detail["mode"] == "bridge" then
        return uploadBytes
    end

    if type(output) ~= "string" or string.len(output) <= 0 then
        return uploadBytes
    end

    local lines = split(output, "\n")
    if lines == nil then
        return uploadBytes
    end

    for _, line in pairs(lines) do
        repeat
            if string.find(line, ruleRegular) == nil or
                    string.find(line, customChainName) == nil then
                --log:Debugf("Can not find statistic keyword, line %v", line)
                break
            end

            --log:Debugf("Iptables statistic: %v", line)
            local content = split(strip(line), " ")
            if content == nil then
                break
            end

            local len = tableLen(content)
            if len <= 3 then
                log:Debugf("Statistic string info absence %v", content)
                break
            end

            if content[len-2] == tostring(detail["classId"]) then
                uploadBytes = uploadBytes + trafficUpload(detail["mode"], detail["pid"], content)
            end
        until true
    end

    return uploadBytes
end

local function collectTaskTraffic(tableName, customChainName, taskInfo)
    local trafficArray = {}
    local titleFormat = "Container id %s, name %s, detail: %v"
    local supportIPv6 = isSupportIPv6()
    local outputIPv4 = iptablesOperator("ipv4",
            "checkoutRulesByteCounters", tableName)
    local outputIPv6 = ""
    if supportIPv6 then
        outputIPv6 = iptablesOperator("ipv6",
                "checkoutRulesByteCounters", tableName)
    end

    if outputIPv4 == "EXCEPTION" or outputIPv6 == "EXCEPTION" then
        log:Debug("iptables execute exception, return empty list")
        return trafficArray
    end

    local timestamp = os.time()
    for cIdStr, detail in pairs(taskInfo) do
        local tmp = {}
        tmp["timestamp"] = timestamp

        if string.len(cIdStr) < 12 then
            tmp["docker_id"] = ""  -- process docker_id = ""
        else
            tmp["docker_id"] = cIdStr
        end

        tmp["name"] = detail["task"]

        if string.len(cIdStr) < 12 then
            tmp["idx"] = 1  -- process idx = 1
        else
            tmp["idx"] = detail["classId"]
        end

        tmp["custom_id"] = detail["custom_id"]
        tmp["binding_interface"] = detail["binding"]
        tmp["bw_upload_ipv4"] = matchData(detail, outputIPv4, "ipv4", customChainName)
        tmp["bw_upload_ipv6"] = matchData(detail, outputIPv6, "ipv6", customChainName)
        tmp["bw_upload"] = tmp["bw_upload_ipv4"] + tmp["bw_upload_ipv6"]
        tmp["bw_download_ipv4"] = 0
        tmp["bw_download_ipv6"] = 0
        tmp["bw_download"] = tmp["bw_download_ipv4"] + tmp["bw_download_ipv6"]
        tmp["bs_bw_upload"] = 0

        log:Debugf(titleFormat, cIdStr, detail["name"], tmp)
        table.insert(trafficArray, tmp)
    end

    return trafficArray
end

local function localNetCards()
    local nameArray = {}
    local linksCmd = "ls /sys/class/net"
    local vLinksCmd = "ls /sys/devices/virtual/net"
    local uniqCmd = "(echo \"$(%s)\"; echo \"$(%s)\"; echo \"$(%s)\") | sort | uniq -u"
    uniqCmd = string.format(uniqCmd, linksCmd, vLinksCmd, vLinksCmd)
    local result = executeCmd(uniqCmd)
    if string.len(result) > 0 then
        nameArray = split(result, "\n")
    end

    log:Debugf("Local netCards: %v", nameArray)
    return nameArray
end

local function readNetStatisticBytes(formatstring, netCards)
    local bytes = 0
    for _, name in pairs(netCards) do
        repeat
            if string.len(name) <= 0 then
                break
            end

            local filePath = string.format(formatstring, strip(name))
            if not fileExists(filePath) then
                log:Debugf("No such file: %v", filePath)
                break
            end

            local fh, _ = io.open(filePath, "r")
            if fh == nil then
                log:Debugf("Can not open file %v", filePath)
                break
            end
            local output = fh:read('*all')
            fh:close()
            local num = tonumber(output)
            if num == nil then
                log:Debugf("%s can not convert to number", output)
                break
            end
            bytes = bytes + num
        until true
    end

    return bytes
end

local function statisticNetCardTraffic()
    local uploadBytes = 0
    local downloadBytes = 0
    local netCards = localNetCards()
    local timestamp = os.time()
    if netCards == nil or tableLen(netCards) <= 0 then
        log:Debug("Can not find hardware net card")
        return timestamp, uploadBytes, downloadBytes
    end

    uploadBytes = readNetStatisticBytes(netStatisticsTx, netCards)
    downloadBytes = readNetStatisticBytes(netStatisticsRx, netCards)

    return timestamp, uploadBytes, downloadBytes
end

local function collectMachineTraffic(taskArray)
    local trafficArray = {}
    for _, taskName in pairs(taskArray) do
        local timestamp, uploadBytes, downloadBytes = statisticNetCardTraffic()
        local detail = {}
        detail["timestamp"] = timestamp
        detail["docker_id"] = ""
        detail["name"] = taskName
        detail["idx"] = 1
        detail["custom_id"] = ""
        detail["binding_interface"] = ""
        detail["bw_upload"] = uploadBytes
        detail["bw_upload_ipv4"] = 0
        detail["bw_upload_ipv6"] = 0
        detail["bw_download"] = downloadBytes
        detail["bw_download_ipv4"] = 0
        detail["bw_download_ipv6"] = 0
        detail["bs_bw_upload"] = 0
        log:Debugf("%s traffic detail: %v", taskName, detail)
        table.insert(trafficArray, detail)
    end

    return trafficArray
end

function collect(out, configObject)
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
    local only, taskArray = onlyMachineTraffic(taskTags, recognitionConfig["specific"])
    if only then
        log:Info("Only collect hardware network card traffic")
        trafficArray = collectMachineTraffic(taskArray)
    else
        local tableName = "filter"
        local chainName = "OUTPUT"
        local key = string.format("%s_%s", tableName, string.lower(chainName))
        local customChainName = customChainNameDict[key]
        if customChainName ~= nil then
            local taskInfo = {}
            collectContainerInfo(taskSNConfig, taskInfo)
            collectProcessInfo(collectPidConfig, taskSNConfig, taskInfo)
            trafficArray = collectTaskTraffic(tableName, customChainName, taskInfo)
        else
            log:Debugf("Can not find %s %s custom chain name", tableName, chainName)
        end
    end

    local curTime = os.time()
    local dataJson = jsonMarshal(trafficArray)
    if dataJson ~= nil then
        out:AddField(input.category, input.name, input.dataVersion,
                input.indicator, "", dataJson, curTime)
    end
end
