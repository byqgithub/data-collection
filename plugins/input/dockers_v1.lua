-- Marking: lua,input,dockers,1

local input = {
    category = "input",
    name = "dockers",
    dataVersion = "1",
    indicator = "dockers"
}

local function split(str,reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function (w)
        table.insert(resultStrList, w)
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

local function strip(str)
    return string.gsub(str, "^%s*(.-)%s*$", "%1")
end

local function fileExists(file)
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
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

local function readFile(f)
    local linesTable = {}
    if not fileExists(f) then
        return nil
    end

    local count = 0
    local file = assert(io.open(f, 'r'))
    for line in file:lines(f) do
        count = count + 1
        linesTable[count] = line
    end
    file:close()
    return linesTable
end

local function executeCmd(cmd, timeout)
    if timeout == nil then
        timeout = 5
    end

    local result = ""
    local command = string.format("%s ", cmd)
    --print("Execute command: ", command)
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

    return result

end

local function stringStartWith(str, start)
    return string.sub(str,1,string.len(start))==start
end

local function isCallable(func)
    if type(func) == 'function' then
        return true
    end
    return false
end

local function hasValue(tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

local function fetchRuntime(timeStr)
    local now = os.time()
    local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+).(%d+)"
    local xyear, xmonth, xday, xhour, xminute,
    xseconds, xoffset = timeStr:match(pattern)
    local convertedTimestamp = os.time({year = xyear, month = xmonth,
                                        day = xday, hour = xhour, min = xminute, sec = xseconds})

    return now - convertedTimestamp

end

local function getCpuUsage(cpusStats, precpuStats)
    local cpuPercent = 0.0
    local cpuDelta = tonumber(cpusStats["cpu_usage"]["total_usage"]) - tonumber(precpuStats["cpu_usage"]["total_usage"])
    local systemDelta = tonumber(cpusStats["system_cpu_usage"]) - tonumber(precpuStats["system_cpu_usage"])

    if cpuDelta > 0.0 and systemDelta > 0.0 then
        cpuPercent = cpuDelta / systemDelta * tableLen(cpusStats["cpu_usage"]["percpu_usage"]) * 100
    end
    return string.format("%.1f", cpuPercent)
end

local function getMemoryUsage(memoryStats)
    local memoryPercent = tonumber(memoryStats["usage"]) / tonumber(memoryStats["limit"]) * 100
    return string.format("%.1f", memoryPercent)
end

local function getImagesTags()
    local imageTable = {}
    local cmd = '/usr/bin/docker images --format "{{.ID}} {{.Tag}}"'
    local results = executeCmd(cmd)
    if results ~= nil then
        local resultSplit = split(results, "\n")
        for _, l in pairs(resultSplit) do
            local lSplit = split(strip(l), " ")
            if tableLen(lSplit) == 2 then
                imageTable[lSplit[1]] = lSplit[2]
            end
        end
    end
    return imageTable
end

local function getSizeByDisk(disk)
    local cmd = string.format("df | grep -w '%s'", disk) .. " 2>/dev/null | awk '{printf \"%s++%s\",$2,$3}'"
    local result = executeCmd(cmd)
    if result ~= nil then
        local rSplit = split(result, "++")
        if tableLen(rSplit) == 2 then
            return rSplit[1], rSplit[2]
        end
    end
    return 0, 0
end

local function getDiskType(diskname)
    local diskType = ""
    if string.find(diskname, "nvme") then
        diskType = "nvme"
    else
        local cmd = string.format("lsblk -d -o name,rota /dev/%s 2>/dev/null", diskname) .. " | tail -n 1 | " + "awk '{print $NF}'"
        local result = executeCmd(cmd)
        if result ~= nil then
            if strip(result) == "1" then
                diskType = "hdd"
            else
                diskType = "ssd"
            end
        end
    end
    return diskType
end

local function getDiskSize(fsTable, mounts)
    local allTotal, allUsed, diskPercent = 0, 0, 0.0
    local diskType = "hdd"
    if mounts ~= nil then
        for _, m in pairs(mounts) do
            if fsTable[m["Source"]] ~= nil then
                local block = fsTable[m["Source"]]
                diskType = getDiskType(block)
                local diskTotal, diskUsed = getSizeByDisk(block)
                allTotal = allTotal + diskTotal
                allUsed = allUsed + diskUsed
            end
        end
    end

    if allTotal > 0 then
        diskPercent = allUsed / allTotal * 100
    else
        diskType = ""
    end

    return diskType, allTotal, string.format("%.1f", diskPercent)
end

local function getSizeByRowDevice(block)
    local cmd = string.format("fdisk -l 2>/dev/null |grep -w %s", block) .. " |  awk '{print $5}'"
    local result = executeCmd(cmd)
    if result ~= nil then
        return tonumber(strip(result))
    end
    return 0
end

local function getRowDiskSize(mounts)
    local all_total, slen, dev_string  = 0, 0, ""
    if mounts ~= nil then
        for _, m in pairs(mounts) do
            if stringStartWith(m["Source"], "/dev") then
                local block = m["Source"]
                local disk_total = getSizeByRowDevice(block)
                all_total = all_total + disk_total
                dev_string = dev_string .. m["Source"] .. ","
            end
        end
    end
    if string.len(dev_string) > 1 then
        slen = string.len(dev_string) - 1
    end
    return all_total, string.sub(dev_string, 1, slen)
end

local function readFstab()
    local devTable = {}
    local fstabFile = "/etc/fstab"
    local fsTable = readFile(fstabFile)
    if fsTable ~= nil then
        for _, line in pairs(fsTable) do
            local lineSplit = split(line, " ")
            if tableLen(lineSplit) == 6 then
                if string.find(lineSplit[1], "#") == nil and string.find(lineSplit[1], "/dev/mapper") == nil then
                    if lineSplit[2] ~= "/" and lineSplit[2] ~= "swap" and lineSplit[2] ~= "/boot" then
                        if string.find(lineSplit[1], "UUID") ~= nil then
                            local uuidSplit = split(lineSplit[1], "=")
                            local cmd = "readlink /dev/disk/by-uuid/" .. uuidSplit[2]
                            local realDev = executeCmd(cmd)
                            if realDev ~= nil then
                                local realDevSplit = split(realDev, "/")
                                if tableLen(realDevSplit) == 3 then
                                    local dev = "/dev/" .. realDevSplit[3]
                                    devTable[dev] = lineSplit[2]
                                end
                            end
                        end
                    elseif string.find(lineSplit[1], "/dev/") then
                        devTable[lineSplit[1]] = lineSplit[2]
                    end
                end
            end
        end
    end
    --print("devTable")
    --for k, v in pairs(devTable) do
    --    print(k, v)
    --end
    --print("end")
    return devTable
end

local function fetchImageTag(imageTable, image)
    local imageTag = ""
    local imageStr = image
    local imageSplit = split(imageStr, ":")
    local imageShort = string.sub(imageSplit[2], 1, 12)
    if imageTable[imageShort] ~= nil then
        imageTag = imageTable[imageShort]
    end

    return imageTag
end

local function getNetFlow(pid)
    local cmd = string.format("cat /proc/{pid}/net/dev 2>/dev/null", pid)
    cmd = cmd .. "| grep eth0 | awk '{printf \"%s++%s\",$2,$10}'"
    local result = executeCmd(cmd)
    if result ~= nil then
        local flow = split(result, "++")
        if tableLen(flow) == 2 then
            return flow[1], flow[2]
        end
    end
    return 0, 0
end

local function getNetworkMode(netWorkMode, pid)
    if netWorkMode == "host" then
        return 0,0
    else
        return getNetFlow(pid)
    end
end

local function fetchBdfdOrBdxCustomId(kwargsTable)
    local customId = ""
    local specialFile = string.format("/proc/%s/root/PCDN/id", kwargsTable["pid"])
    local linesTable = readFile(specialFile)
    if linesTable ~= nil then
        for _, line in pairs(linesTable) do
            if string.find(line, "guid") then
                local lineSplit = split(line, "=")
                if tableLen(lineSplit) == 2 then
                    customId = strip(lineSplit[2])
                    break
                end
            end
        end
    else
        local cmd = string.format("docker exec %s cat /PCDN/id", kwargsTable["cid"])
        local results = executeCmd(cmd)
        if results ~= nil then
            for _, line in pairs(results) do
                if string.find(line, "guid") then
                    local lineSplit = split(line, "=")
                    if tableLen(lineSplit) == 2 then
                        customId = strip(lineSplit[2])
                        break
                    end
                end
            end
        end
    end
    return customId
end

local function fetchBdsxVersion(kwargsTable)
    local version = ""
    local specialFile = string.format("/proc/%s/root/PCDN/id", kwargsTable["pid"])
    local linesTable = readFile(specialFile)
    if linesTable ~= nil then
        for _, line in pairs(linesTable) do
            if string.find(line, "version") then
                local lineSplit = split(line, "=")
                if tableLen(lineSplit) == 2 then
                    version = strip(lineSplit[2])
                    break
                end
            end
        end
    else
        local cmd = string.format("docker exec %s cat /PCDN/id", kwargsTable["cid"])
        local results = executeCmd(cmd)
        if results ~= nil then
            for _, line in pairs(results) do
                if string.find(line, "version") then
                    local lineSplit = split(line, "=")
                    if tableLen(lineSplit) == 2 then
                        version = strip(lineSplit[2])
                        break
                    end
                end
            end
        end
    end
    return version
end

local function fetchBdwphjCustomId(kwargsTable)
    local customId = ""
    local specialFile = string.format("/proc/%s/storage/popnode_id", kwargsTable["pid"])
    local linesTable = readFile(specialFile)
    if linesTable ~= nil then
        for _, line in pairs(linesTable) do
            if line ~= nil then
                customId = strip(line)
                break
            end
        end
    else
        local cmd = string.format("docker exec %s cat /P2P/popnode_id", kwargsTable["cid"])
        local results = executeCmd(cmd)
        --print(results)
        if results ~= nil then
            customId = strip(results)
            --for _, line in pairs(results) do
            --    if line ~= nil then
            --        customId = strip(line)
            --        break
            --    end
            --end
        end
    end
    return customId
end

local function fetchBdrCustomId(Env)
    print(Env)
    local customId = ""
    if Env ~= nil then
        for _, e in pairs(Env) do
            local eSplit = split(e, "=")
            if tableLen(eSplit) == 2 then
                if eSplit[1] == "RESOURCE_NAME" then
                    customId = strip(eSplit[2])
                    break
                end
            end
        end
    end
    return customId
end

local function fetchTaskNameIdx(Env)
    local taskName = "", ""
    local idx = 0
    if Env ~= nil then
        for _, e in pairs(Env) do
            local eSplit = split(e, "=")
            if tableLen(eSplit) == 2 then
                if eSplit[1] == "TASK_NAME" then
                    taskName = strip(eSplit[2])
                    break
                elseif eSplit[1] == ("PAI_TASK_NAME") then
                    local taskWorld = split(eSplit[2], "-")
                    if tableLen(taskWorld) == 3 then
                        taskName = taskWorld[2]
                        idx = taskWorld[3]
                        break
                    end
                end
            end
        end
    end
    return taskName, idx
end

local function fetchBaseImageTag(Env)
    local imageOriginalTag = ""
    if Env ~= nil then
        for _, e in pairs(Env) do
            local eSplit = split(e, "=")
            if tableLen(eSplit) == 2 then
                if eSplit[1] == "BASE_IMAGE" then
                    imageOriginalTag = strip(eSplit[2])
                    break
                end
            end
        end
    end
    return imageOriginalTag
end

local function fetchMaxBindwidth(Env)
    local max_bind_width = 0
    if Env ~= nil then
        for _, e in pairs(Env) do
            local eSplit = split(e, "=")
            if tableLen(eSplit) == 2 then
                if eSplit[1] == "MAX_BANDWIDTH" then
                    log:Debugf("fetchMaxBindwidth eSplit[2]: %s", eSplit[2])
                    max_bind_width = tonumber(eSplit[2]) * 8 * 1024 * 1024
                    break
                end
            end
        end
    end
    return max_bind_width
end

local function fetchBdxSpecialKeys(keyTable, Env)
    local bdxTable = {}
    if Env ~= nil then
        for _, e in pairs(Env) do
            local eSplit = split(e, "=")
            if tableLen(eSplit) == 2 then
                if hasValue(keyTable, eSplit[1]) then
                    bdxTable[eSplit[1]] = eSplit[2]
                end
            end
        end
    end
    return bdxTable
end

local function processInfo(pid)
    local rss, runningTime = 0, 0
    local rsscmd = string.format("cat /proc/%s/status", pid) .. " | grep VmRSS | awk '{print $2}'"

    local rssres = executeCmd(rsscmd)
    if rssres ~= nil then
        rss = tonumber(rssres) * 1024
    end

    local runningcmd= 'echo $(( $(date +%s) - $(date -d "$(stat ' .. string.format("/proc/%s/stat", pid) .. '| grep Modify | sed \'s/Modify: //\')" +%s) ))'
    local res = executeCmd(runningcmd)
    if res ~= nil then
        runningTime = res
    end
    return rss, runningTime
end

local function test(pid)
    local runningcmd= 'echo $(( $(date +%s) - $(date -d "$(stat ' .. string.format("/proc/%s/stat", pid) .. '| grep Modify | sed \'s/Modify: //\')" +%s) ))'
    local runningres = executeCmd(runningcmd)
    print(runningres)
end

--test(10778)

local function parseConf(conf)
    local confTable = {}
    local confSplit = split(conf, "\n")
    for _, line in confSplit do
        local lineSplit = split(line, ":")
        if tableLen(lineSplit) == 2 then
            if strip(lineSplit[1]) == "ksVersion" then
                local version = split(lineSplit[2], "_")
                confTable["version"] = version[3]
            else
                confTable[strip(lineSplit[1])] = strip(lineSplit[2])
            end
        end
    end
    return confTable
end

local function fetchKs(pid, mounts)
    local confTable = {}
    local diskType, diskTotal, diskPercent = "", 0, 0
    local cmd = string.format("cat /proc/%s/root/opt/ksp2p/conf/parameter.txt", pid)
    local results = executeCmd(cmd)
    if results ~= nil then
        confTable = parseConf(results)
        local fsTable = readFstab()
        if confTable ~= nil then
            diskType, diskTotal, diskPercent = getDiskSize(fsTable, mounts)
            local rsz, rtime = processInfo(pid)
            local linecount = tableLen(split(confTable["nic_out"], ""))
            local speed = tonumber(linecount) * tonumber(confTable['multi_line_speed']) * 8 * 1024 * 1024
            local multi_line_speed = tonumber(confTable['multi_line_speed']) * 8 * 1024 * 1024
            confTable["pid"] = pid
            confTable["disk_size_total"] = diskTotal
            confTable["disk_size_used"] = tonumber(diskPercent)
            confTable["memory_size"] = 0
            confTable["rsz"] = rsz
            confTable["running_time"] = rtime
            confTable["udp_mode"] =1
            confTable["linecount"] = linecount
            confTable["speed"] = speed
            confTable["multi_line_speed"] = multi_line_speed
        end
    end
    return confTable
end

local function dockerCollect(statsTable, inspectsTable)
    local curTime = os.time()
    local dockerTable = {
        ["dockers"] = nil,
        ["timestamp"] = curTime
    }
    local dockers = {}
    if statsTable == nil or inspectsTable == nil then
        print("statsTable or inspectsTable is nil")
        return dockerTable
    end
    local machineId = machineID()
    local index = 1
    local bdxSpecialKeys = {"PRIVATE_LINE", "SPECIAL_LINE", "SUPPORT_HTTPS"}
    local bindwidthTaskArray = {"bdx", "bdf"}
    local cidTaskArray = {"bdfd", "bdx", "bdwphj"}
    local funcTable = {
        ["bdfd"] = fetchBdfdOrBdxCustomId,
        ["bdx"] = fetchBdfdOrBdxCustomId,
        ["bdwphj"] = fetchBdwphjCustomId
    }
    local images = getImagesTags()
    local fsTable = readFstab()
    for id, container in pairs(inspectsTable) do
        if container["Name"] ~= nil then
            if string.find(container["Name"], "POD") == nil then
                print(container["Name"], container["Id"])
                local taskName, idx = fetchTaskNameIdx(container["Config"]["Env"])
                print("taskName", taskName)
                local cid = ""
                local cpuPercent, memorySize, memoryPercent = 0.0, 0.0, 0.0
                local diskType, diskTotal, diskPercent = "", 0, 0
                local raw_device_size, raw_dev_string = 0, ""
                local version_program = "0.0.0"
                local bdxCollect = {
                    ["PRIVATE_LINE"] = 0,
                    ["SPECIAL_LINE"] = 0,
                    ["SUPPORT_HTTPS"] = 0
                }
                local baseImageTag = ""
                local maxBindWidth = 0
                local receive, send = 0, 0
                local runTime = 0
                local imageTag = ""
                local custom_id = ""
                local docker_id = ""
                local d = {}
                local words = split(container["Name"], "_")
                if taskName then
                    baseImageTag = fetchBaseImageTag(container["Config"]["Env"])
                    if hasValue(bindwidthTaskArray, taskName) then
                        maxBindWidth = fetchMaxBindwidth(container["Config"]["Env"])
                    end
                    print("cid", cid)
                    if taskName == "bdx" then
                        bdxCollect = fetchBdxSpecialKeys(bdxSpecialKeys, container["Config"]["Env"])
                    end

                    if hasValue(cidTaskArray, taskName) then
                        local func = funcTable[taskName]
                        local kwargsTable = {
                            ["pid"] = container["State"]["Pid"],
                            ["cid"] = container["Id"]
                        }
                        if isCallable(func) then
                            cid = func(kwargsTable)
                        end

                    elseif taskName == "bdr" then
                        print("container Env", container["Config"]["Env"])
                        cid = fetchBdrCustomId(container["Config"]["Env"])
                        print("bdr", cid)

                    elseif tableLen(words) > 4 then
                        if stringStartWith(words[3], "pai-") and string.find(words[3], "monitoring") == nil then
                            local wSplit= split(words[3], "-")
                            cid = wSplit[3]
                        end
                    end

                    if taskName == "bdsx" then
                        local kwargsTable = {
                            ["pid"] = container["State"]["Pid"],
                            ["cid"] = container["Id"]
                        }
                        raw_device_size, raw_dev_string = getRowDiskSize(container["Mounts"])
                        version_program = fetchBdsxVersion(kwargsTable)
                    end


                    runTime = fetchRuntime(container["State"]["StartedAt"])
                    if statsTable[id] ~= nil then
                        local csts = statsTable[id]
                        print(csts)
                        log:Debugf("csts %v", csts)
                        cpuPercent = getCpuUsage(csts["cpu_stats"], csts["precpu_stats"])
                        memorySize = tonumber(csts["memory_stats"]["limit"])
                        memoryPercent = tonumber(getMemoryUsage(csts["memory_stats"]))
                        receive, send = getNetworkMode(container['HostConfig']['NetworkMode'], container["State"]["Pid"])
                        diskType, diskTotal, diskPercent = getDiskSize(fsTable, container["Mounts"])
                        imageTag = fetchImageTag(images, container["Image"])
                    end

                    if taskName == "ks" then
                        log:Debugf("container %v", container)
                        local ksTable = fetchKs(container["State"]["Pid"], container["Mounts"])
                        local runningStatus = false
                        if ksTable["diskTotal"] > 1024 then
                            runningStatus = true
                        end
                        custom_id = ksTable["guid"]
                        d = {
                            --["docker_id"] = "",
                            ["idx"] = 1,
                            ["version"] = ksTable["version"],
                            ["version_program"] = ksTable["version"],
                            ["bw_upload"] = 0,
                            ["bs_bw_upload"] = 0,
                            ["bw_download"] = 0,
                            ["bw_config"] = ksTable["speed"],
                            ["storage_type"] = "ssd",
                            ["storage_size"] = ksTable["disk_size_total"],
                            ["storage_usage"] = ksTable["disk_size_used"],
                            ["ping_ttl"] = 0,
                            ["ping_time"] = 0,
                            ["ping_success"] = 0,
                            ["cpu_usage"] = 0,
                            ["mem_size"] = 0,
                            ["mem_usage"] = 0,
                            ["outgoing"] = 0,
                            ["incoming"] = 0,
                            ["running_status"] = runningStatus,
                            ["outer_ip"] = "0.0.0.0",
                            ["running_count"] = 2,
                            ["network_mode"] = "program",
                            ["image_tag"] = "",
                            ["base_image_tag"] = "",
                            ["line_cnt"] = ksTable["linecount"],
                            ["bw_upload_line"] = ksTable["multi_line_speed"],
                            ["user_speed_count"] = 0,
                            ["user_speed_gt_zero_count"] = 0,
                            ["user_avg_speed"] = 0,
                            ["provider"] = ksTable["provider"],
                            ["provider_id"] = ksTable["provider_id"],
                            ["uptime"] = ksTable["running_time"],
                            ["special_line"] = 0,
                            ["private_line"] = 0,
                            ["support_https"] = 0,
                            ["raw_storage_size"] = 0,
                            ["raw_storage_devices"] = ""
                        }
                    else
                        custom_id = cid
                        docker_id = container["Id"]
                        d = {
                            --["docker_id"] = id,
                            ["idx"] = idx,
                            ["version"] = "0.0.0",
                            ["version_program"] = version_program,
                            ["bw_upload"] = 0,
                            ["bs_bw_upload"] = 0,
                            ["bw_download"] = 0,
                            ["bw_config"] = 0,
                            ["storage_type"] = diskType,
                            ["storage_size"] = tonumber(diskTotal),
                            ["storage_usage"] = tonumber(diskPercent),
                            ["ping_ttl"] = 0,
                            ["ping_time"] = 0,
                            ["ping_success"] = 0,
                            ["cpu_usage"] = tonumber(cpuPercent),
                            ["mem_size"] = memorySize,
                            ["mem_usage"] = memoryPercent,
                            ["outgoing"] = 0,
                            ["incoming"] = 0,
                            ["outer_ip"] = "0.0.0.0",
                            ["running_count"] = 0,
                            ["running_status"] = false,
                            ["network_mode"] = container['HostConfig']['NetworkMode'],
                            ["image_tag"] = imageTag,
                            ["base_image_tag"] = baseImageTag,
                            ["line_cnt"] = 0,
                            ["bw_upload_line"] = 0,
                            ["user_speed_count"] = 0,
                            ["user_speed_gt_zero_count"] = 0,
                            ["user_avg_speed"] = 0,
                            ["provider"] = "",
                            ["provider_id"] ="",
                            ["uptime"] = runTime,
                            ["special_line"] = bdxCollect["SPECIAL_LINE"],
                            ["private_line"] = bdxCollect["PRIVATE_LINE"],
                            ["support_https"] = bdxCollect["SUPPORT_HTTPS"],
                            ["raw_storage_size"] = tonumber(raw_device_size),
                            ["raw_storage_devices"] = raw_dev_string,
                        }
                    end
                    local tags = {
                        ["machine_id"] = machineId,
                        ["docker_id"] = docker_id,
                        ["custom_id"] = custom_id,
                        ["name"] = taskName,
                    }
                    local tmp_docker = {
                        ["tags"] = tags,
                        ["fields"] = d
                    }
                    dockers[index] = tmp_docker
                    index = index + 1
                end
            end
        end
    end
    for i, d in pairs(dockers) do
        for k, v in pairs(d) do
            print(i, k, v)
        end
    end
    log:Debugf("%+v", dockers)
    dockerTable["dockers"] = dockers
    return dockerTable
end

--dockerCollect()
--test pass

function collect(out)
    local curTime = os.time()
    local statsStr = containersStats()
    local statsTable = jsonUnMarshal(statsStr)

    local inspectsStr = containersInspects()
    local inspectsTable = jsonUnMarshal(inspectsStr)

    local statData = dockerCollect(statsTable, inspectsTable)
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end