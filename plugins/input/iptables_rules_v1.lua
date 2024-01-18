-- Marking: lua,input,iptables_rules,1

--local input = {
--    category = "input",
--    name = "iptables_rules",
--    dataVersion = "1",
--    indicator = "iptables_rules"
--}

-- iptables operational order
local order = {
    -- IPv4
    ipv4 = {
        checkoutRules ="iptables-save -t %s",
        checkoutRulesByteCounters = "iptables-save -c -t %s",
        storeRules = "iptables-restore -w 30 --noflush --table=%s < %s"
    },
    -- IPv6
    ipv6 = {
        checkoutRules = "ip6tables-save -t %s",
        checkoutRulesByteCounters = "ip6tables-save -c -t %s",
        storeRules = "ip6tables-restore -w 30 --noflush --table=%s < %s"
    }
}

-- iptables rule template
local createNewChain = ":%s - [0:0]"
local referenceRule = "-A %s -j %s"
local customChainNameDict = {
    raw_output = "PCDN_OUTPUT_CGROUP",
    filter_output = "PAI_OUTPUT_CGROUP"
}
local addRuleTemplateDict = {
    raw_output = "-A %s ! -o lo -m cgroup --cgroup %s -j RETURN",
    filter_output = "-A %s -m addrtype ! --dst-type LOCAL -m cgroup --cgroup %s -j RETURN"
}
local delRuleTemplate = "-D %s"
local delReferenceRuleTemplate = "-D %s -j %s"
local delCustomChain = "-X %s"

-- iptables rule regular
local chainRegular = ":%s"
local referenceRegular = "%s-A %s %s-j %s"
local ruleRegular = "%-m cgroup %-%-cgroup"
--local customChainRegular = ":%s%s*-%s*%[%d*:%d*]"
--local ruleRegular = "-A %s.*-m cgroup --cgroup %d* -j.*"
--local ruleByteCountersRegular = "%[%d*:%d*]%s*-A %s.*-m cgroup --cgroup %d* -j.*"

--local netStatisticsTx = "/sys/class/net/%s/statistics/tx_bytes"
--local netStatisticsRx = "/sys/class/net/%s/statistics/rx_bytes"
local netClsBasePath = "/sys/fs/cgroup/net_cls"
local findNetClsPath = "find %s/* -name %s"
--local netDevPath = "/proc/%s/net/dev"
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

    log:Debugf("OnlyMachineTraffic: %v", only)
    log:Debugf("Machine task: %v", taskArray)
    return only, taskArray
end

local function isPauseImage(info)
    local include = false
    local image = info["Config"]["Image"]
    log:Debugf("Container id: %s, image: %s", info["Id"], image)
    if image == nil or string.len(image) <= 0 then
        return include
    end

    local sections = split(image, "/")
    if tableLen(sections) <= 0 then
        return include
    end

    if string.find(sections[tableLen(sections)], "pause") then -- TODO
        include = true
    end
    return include
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
            log:Debugf("Can not find net_cls path, container id %s, config %s", cId, pathConfig)
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

    --log:Debugf("net cls path %s", path)
    return path
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

local function extractContainerInfo(containerInfo)
    local netClsFile = searchNetClsPath(containerInfo)
    local taskTag = getTaskFromContainerInfo(containerInfo)
    local correctFormat = "Container %s info: %v"

    local infoTable = {}
    if containerInfo["Name"] ~= nil then
        infoTable["name"] = containerInfo["Name"]
    else
        infoTable["name"] = ""
    end

    infoTable["task"] = taskTag
    infoTable["cls"] = netClsFile
    log:Debugf(correctFormat, containerInfo["Id"], infoTable)

    return infoTable
end

local function collectContainerInfo()
    local detail = {}
    local infoStr = containersInfo()
    local infoTable = jsonUnMarshal(infoStr)
    for cId, info in pairs(infoTable) do
        repeat
            if isPauseImage(info) then
                break
            end

            local tmpTable = extractContainerInfo(info)
            if tmpTable ~= nil then
                detail[cId] = tmpTable
            end
        until true
    end

    return detail
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

local function clearCgroupNode(taskName)
    local path = string.format("%s/%s", netClsBasePath, taskName)
    if fileExists(path) then
        log:Debugf("Clear %s cgroup node", taskName)
        executeCmd(string.format("rm -rf %s", path))
    else
        log:Debugf("%s cgroup node %s is not existed", taskName, path)
    end
end

local function getProcessInfo(configTable)
    local taskArray = {}
    for name, cmd in pairs(configTable) do
        repeat
            local taskName = strip(name)
            if string.len(taskName) <= 0 or string.find(taskName, "_pid") ~= nil then
                break
            end

            local pid = tonumber(executeCmd(cmd))
            local pidTreeCmd = configTable[string.format("%s_pid", taskName)]
            if pid == nil or pid <= 1 then
                clearCgroupNode(taskName)
                break
            end

            pidTreeCmd = string.format(pidTreeCmd, pid)
            local pidTreeStr = executeCmd(pidTreeCmd)
            if string.len(pidTreeStr) <= 0 then
                break
            end

            log:Debugf("Process %s, pid %v, pid tree: %v", taskName, pid, pidTreeStr)
            local cgroupPath = generateCgroupPath(taskName)
            local tmp = {}
            tmp["pid"] = pidTreeStr
            tmp["path"] = cgroupPath
            -- no index, default 0
            tmp["task"] = string.format("pai-%s-0", taskName)
            log:Debugf("Process %s, info: %v", taskName, tmp)
            taskArray[taskName] = tmp
        until true
    end

    return taskArray
end

local function clearUnusedCgroupNode(configTable)
    for name, cmd in pairs(configTable) do
        repeat
            local taskName = strip(name)
            if string.len(taskName) <= 0 or string.find(taskName, "_pid") ~= nil then
                break
            end

            local pid = tonumber(executeCmd(cmd))
            if pid ~= nil and pid >= 0 then
                log:Debugf("Process %s pid %v, try to clear cgroup node", taskName, pid)
            end
            clearCgroupNode(taskName)
        until true
    end
end

local function getTaskInfo(onlyMachine, configTable)
    local containersInfo = collectContainerInfo()
    local processInfo = {}
    if onlyMachine then
        log:Debug("Device only collect machine traffic, need to clear cgroup node")
        clearUnusedCgroupNode(configTable)
    else
        processInfo = getProcessInfo(configTable)
    end

    return containersInfo, processInfo
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
    log:Debugf("TEST class id: %.f", classId)
    return classId
end

local function movingProcessToCgroup(name, path, pidTree, netClassId)
    local tagTxt = "Add process tag: name: %s; path: %s, class_id: %s"
    local movingTxt = "Move process to cgroup: name: %s; path: %s, pid: %v"
    local classIdFile = string.format("%s/%s", path, "net_cls.classid")
    if not fileExists(classIdFile) then
        log:Debugf("File %s do not exist", classIdFile)
        return
    end
    local fh = io.open(classIdFile, "w+")
    fh:write(netClassId)
    fh:flush()
    fh:close()
    fh = io.open(classIdFile, "r")
    log:Debugf(tagTxt, name, classIdFile, fh:read('*a'))
    fh:close()

    local tasksFile = string.format("%s/%s", path, "tasks")
    if not fileExists(tasksFile) then
        log:Debugf("File %s do not exist", tasksFile)
        return
    end
    fh = io.open(tasksFile, "w+")
    fh:write(pidTree)
    fh:flush()
    fh:close()
    fh = io.open(tasksFile, "r")
    log:Debugf(movingTxt, name, tasksFile, fh:read('*a'))
    fh:close()
end

local function storeRules(ipProtocol, ruleArray, tableName)
    local tmpFile = "/tmp/tmp_iptables_rule.txt"
    local content = ""
    content = content .. string.format("*%s\n", tableName)
    for _, rule in pairs(ruleArray) do
        content = content .. string.format("%s\n", rule)
    end
    content = content .. "COMMIT\n"

    local fh = io.open(tmpFile, "w+")
    fh:write(content)
    fh:flush()
    fh:close()
    fh = io.open(tmpFile, "r")
    log:Debugf("Store iptables rules %v", fh:read('*a'))
    fh:close()

    iptablesOperator(ipProtocol, "storeRules", tableName, tmpFile)
end

local function addContainersLabel(containersInfo, taskSN, classIdTable)
    local infoTxt = "Containers name: %s; id: %s; task: %s; net_cls file: %s, class_id: %.f;"
    local tagTxt = "Add container tag: name: %s; id: %s; net_class_id: %.f; class_id: %s"
    for cId, info in pairs(containersInfo) do
        repeat
            if tableLen(info) < 3 then
                break
            end

            local name = info["name"]
            local task = info["task"]
            local path = info["cls"]
            local netClassId = generateClassId(task, cId, taskSN)
            log:Debugf(infoTxt, name, cId, task, path, netClassId)
            if netClassId <= 0 then
                log:Errorf("Container %s net class id error", cId)
                break
            end

            classIdTable[cId] = netClassId
            local fh = io.open(path, "w+")
            fh:write(netClassId)
            fh:flush()
            fh:close()
            fh = io.open(path, "r")
            log:Debugf(tagTxt, name, cId, netClassId, fh:read('*a')) -- TODO
            fh:close()
        until true
    end
end

local function addProcessLabel(processInfo, taskSN, classIdTable)
    for _, info in pairs(processInfo) do
        repeat
            if tableLen(info) < 3 then
                break
            end

            local path = info["path"]
            local pidTree = info["pid"]
            local task = info["task"]
            local netClassId = generateClassId(task, "1", taskSN)
            if netClassId <= 0 then
                log:Errorf("Process %s net class id error", task)
                break
            end

            classIdTable[task] = netClassId
            movingProcessToCgroup(task, path, pidTree, netClassId)
        until true
    end
end

local function tasksFlowRules(tableName, defaultChain, customChain, infoTable)
    local key = string.format("%s_%s", tableName, defaultChain)
    local customChainRules = {}
    key = string.lower(key)
    local template = addRuleTemplateDict[key]
    if template == nil then
        log:Debugf("Can not find %s %s rule template", tableName, defaultChain)
        return
    end

    for name, netClassId in pairs(infoTable) do
        local rule = string.format(template, customChain, netClassId)
        log:Debugf("%s flow rule: %s", name, rule)
        customChainRules[tostring(netClassId)] = rule
    end

    return customChainRules
end

local function updateRuleInfo(detail, historyCustomChain)
    local tmp = split(detail, " ")
    if tmp == nil or tableLen(tmp) < 13 then
        log:Errorf("Iptables rule format error: %v", detail)
        return
    end

    local key = tmp[11]
    if key == nil or type(key) ~= "string" then
        log:Errorf("Can not parse iptables rule cgroup id: %v", detail)
        return
    end

    local rule = table.concat(tmp, " ", 2)
    local value = historyCustomChain[key]
    if value == nil or type(value) ~= "table" then
        local ruleArray = {}
        table.insert(ruleArray, rule)
        historyCustomChain[key] = ruleArray
    else
        table.insert(historyCustomChain[key], rule)
    end
end

local function checkoutRepetitionRule(ruleMap)
    --local popKey = {}
    local repetitionRules = {}
    local historyRules = {}
    log:Debug("Before remove duplicates history custom chain:")
    --for k, v in pairs(ruleMap["historyCustomChain"]) do
    --    log:Debugf("key: %.f, value: %v", k, v)
    --end

    for key, ruleArray in pairs(ruleMap["historyCustomChain"]) do
        log:Debugf("key: %s, rules: %v", key, ruleArray)
        if tableLen(ruleArray) > 1 then
            --table.insert(popKey, key)
            for _, rule in pairs(ruleArray) do
                table.insert(repetitionRules, rule)
            end
        elseif tableLen(ruleArray) == 1 then
            historyRules[key] = ruleArray[1]
        end
    end

    --log:Debugf("Raw repetition rule: %v", repetitionRules)
    --log:Debugf("Raw historyCustomChain rule: %v", historyRules)
    ruleMap["historyCustomChain"] = historyRules
    ruleMap["repetitionRules"] = repetitionRules
    log:Debugf("Current repetition rule: %v", ruleMap["repetitionRules"])
    --log:Debugf("After remove duplicates history custom chain: %v", ruleMap["historyCustomChain"])
    log:Debug("After remove duplicates history custom chain:")
    for k, v in pairs(ruleMap["historyCustomChain"]) do
        log:Debugf("key: %s, value: %v", k, v)
    end
end

local function loadRules(tableName, defaultChain, customChain, ipProtocol)
    local ruleMap = {
        createCustomChain = "",  -- iptables 是否包含自定义链, 空字符串为不包含
        referenceChain = {},     -- iptables 默认链是否引用自定义链
        historyCustomChain = {}, -- iptables 当前自定义链规则
        repetitionRules = {}     -- iptables 重复的自定义链规则
    }
    --local createCustomChain = ""   -- iptables 是否包含自定义链, 空字符串为不包含
    --local referenceChain = {}      -- iptables 默认链是否引用自定义链
    --local historyCustomChain = {}  -- iptables 当前自定义链规则
    local result = iptablesOperator(ipProtocol, "checkoutRules", tableName)
    if result == nil or string.len(result) <= 0 then
        return
    end

    result = split(result, "\n")
    log:Debugf("Load iptables rules from system: %v", result)

    --log:Debugf("Now %v", os.time())
    local referenceTemplate = string.format(referenceRegular, "%", defaultChain, "%", customChain)
    for _, rule in pairs(result) do
        if string.find(rule, string.format(chainRegular, customChain)) then
            ruleMap["createCustomChain"] = rule
        elseif string.find(rule, referenceTemplate) then
            table.insert(ruleMap["referenceChain"], rule)
        elseif string.find(rule, ruleRegular) then
            updateRuleInfo(rule, ruleMap["historyCustomChain"])
        end
    end
    --log:Debugf("Now %v", os.time())

    if string.len(ruleMap["createCustomChain"]) <= 0 then
        log:Debug("Custom chain is not exist")
    end

    --log:Debugf("Now %v", os.time())
    checkoutRepetitionRule(ruleMap)
    --log:Debugf("Now %v", os.time())
    if tableLen(ruleMap["referenceChain"]) > 0 then
        log:Debugf("%s reference rule %v", customChain, ruleMap["referenceChain"])
    else
        log:Debugf("Do not have %s reference rule", customChain)
    end

    return ruleMap
end

local function differenceSet(mapA, mapB)
    local keys = {}
    for key, _ in pairs(mapA) do
        if mapB[key] == nil then
            table.insert(keys, key)
        end
    end

    return keys
end

-- createCustomChain
-- referenceChain
-- historyCustomChain
-- customChain
-- repetitionRules
local function generateRules(tableName,
        defaultChainName,
        customChainName,
        ruleMap,
        customChainRules)
    local ruleArray = {}

    if string.len(ruleMap["createCustomChain"]) <= 0 and tableLen(customChainRules) > 0 then
        log:Debugf("Create new chain %s in table %s", customChainName, tableName)
        table.insert(ruleArray, string.format(createNewChain, customChainName))
    end

    local txt, ruleContent = "", ""
    for _, deleteRule in pairs(ruleMap["repetitionRules"]) do
        txt = "Delete %s table %s chain rule %s"
        ruleContent = string.format(delRuleTemplate, deleteRule)
        log:Debugf(txt, tableName, customChainName, ruleContent)
        table.insert(ruleArray, ruleContent)
    end

    local deleteRuleKeys = differenceSet(ruleMap["historyCustomChain"], customChainRules)
    for _, key in pairs(deleteRuleKeys) do
        txt = "Delete %s table %s chain rule %s"
        ruleContent = string.format(delRuleTemplate, ruleMap["historyCustomChain"][key])
        log:Debugf(txt, tableName, customChainName, ruleContent)
        table.insert(ruleArray, ruleContent)
    end

    local addRuleKeys = differenceSet(customChainRules, ruleMap["historyCustomChain"])
    for _, key in pairs(addRuleKeys) do
        txt = "Add %s table %s chain, rule %s"
        local newRule = customChainRules[key]
        log:Debugf(txt, tableName, customChainName, newRule)
        table.insert(ruleArray, newRule)
    end

    if tableLen(ruleMap["referenceChain"]) <= 0 and tableLen(customChainRules) > 0 then
        txt = "Chain %s reference to %s"  -- TODO
        log:Debugf(txt, customChainName, defaultChainName)
        local rule = string.format(referenceRule, defaultChainName, customChainName)
        table.insert(ruleArray, rule)
    end

    if tableLen(ruleMap["referenceChain"]) > 1 then  -- TODO
        for index, rule in pairs(ruleMap["referenceChain"]) do
            if index > 1 then
                txt = "Delete table %s unnecessary reference: %s"
                log:Debugf(txt, tableName, rule)
                local deleteRule = string.format(delReferenceRuleTemplate, defaultChainName, customChainName)
                table.insert(ruleArray, deleteRule)
            end
        end
    end

    return ruleArray
end

local function clearChainRules(tableName, defaultChainName, chainName, ipProtocol)
    local ruleArray = {}
    local ruleMap = loadRules(tableName, defaultChainName, chainName, ipProtocol)

    local txt = ""
    local rule = ""
    for _, deleteRule in pairs(ruleMap["repetitionRules"]) do
        txt = "Delete %s table %s chain rule %s"
        rule = string.format(delRuleTemplate, deleteRule)
        log:Debugf(txt, tableName, chainName, rule)
        table.insert(ruleArray, rule)
    end

    for _, deleteRule in pairs(ruleMap["historyCustomChain"]) do
        txt = "Delete %s table %s chain rule %s"
        rule = string.format(delRuleTemplate, deleteRule)
        log:Debugf(txt, tableName, chainName, rule)
        table.insert(ruleArray, rule)
    end

    if tableLen(ruleMap["referenceChain"]) > 0 then
        for _, deleteRule in pairs(ruleMap["referenceChain"]) do
            txt = "Delete %s reference to %s, rule: %s"
            log:Debugf(txt, chainName, defaultChainName, deleteRule)
            rule = string.format(delReferenceRuleTemplate, defaultChainName, chainName)
            table.insert(ruleArray, rule)
        end
    end

    if string.len(ruleMap["createCustomChain"]) > 0 then
        txt = "Delete custom chain %s in table %s"
        log:Debugf(txt, chainName, tableName)
        table.insert(ruleArray, string.format(delCustomChain, chainName))
    end

    if tableLen(ruleArray) > 0 then
        storeRules(ipProtocol, ruleArray, tableName)
    else
        log:Debug("There is nothing to clear")
    end
end

local function flowTag(onlyMachine, tableName, chainName, ipProtocol,
                       containersInfo, processInfo, taskSN, clear)
    local key = string.format("%s_%s", tableName, chainName)
    key = string.lower(key)
    local customChainName = customChainNameDict[key]
    if customChainName == nil or string.len(customChainName) <= 0 then
        log:Debugf("Do not have %s %s custom chain name", tableName, chainName)
        return
    end

    if clear then -- TODO
        log:Info("Start clear iptables rules")
        clearChainRules(tableName, chainName, customChainName, ipProtocol)
        return
    end

    if onlyMachine then -- TODO
        log:Info("Only statistic machine traffic, clear custom rules")
        clearChainRules(tableName, chainName, customChainName, ipProtocol)
        return
    end

    local classIdTable = {}
    addContainersLabel(containersInfo, taskSN, classIdTable)
    addProcessLabel(processInfo, taskSN, classIdTable)
    local customChainRules = tasksFlowRules(tableName, chainName, customChainName, classIdTable)
    if tableLen(customChainRules) <= 0 then
        log:Info("Do not need anyone custom rules, clear remnant rules")
        clearChainRules(tableName, chainName, customChainName, ipProtocol)
        return
    end

    local ruleMap = loadRules(tableName, chainName, customChainName, ipProtocol)
    local ruleArray = generateRules(tableName, chainName, customChainName, ruleMap, customChainRules)
    if tableLen(ruleArray) > 0 then
        storeRules(ipProtocol, ruleArray, tableName)
    else
        log:Info("Do not need to update iptables rules")
    end
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
    local switchStr = configObject:ConfigRawContent("switch")
    local switch = jsonUnMarshal(switchStr)

    local tableName = "filter"
    local chainName = "OUTPUT"
    local taskTags = getTaskTag(globalConfig)
    local only, _ = onlyMachineTraffic(taskTags, recognitionConfig["specific"]) -- TODO
    local containersInfo, processInfo = getTaskInfo(only, collectPidConfig)
    flowTag(only, tableName, chainName, "ipv4",
            containersInfo, processInfo, taskSNConfig, false)
    if isSupportIPv6() then
        local clear = false
        if not switch["ipv6"] then
            log:Info("Clear ipv6 iptalbes rules")
            clear = true
        end
        flowTag(only, tableName, chainName, "ipv6",
                containersInfo, processInfo, taskSNConfig, clear)
    else
        log:Info("No support ipv6")
    end
end