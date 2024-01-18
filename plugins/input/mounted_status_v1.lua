-- Marking: lua,input,mounted_status,1

local input = {
    category = "input",
    name = "mounted_status",
    dataVersion = "1",
    indicator = "mounted_status"
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
    --for _, v in pairs(linesTable) do
    --    print(v)
    --end
    return linesTable
end

local function mountRepe()
    local mountFile = "/proc/mounts"
    local mounts = readFile(mountFile)
    local mountsTable = {}
    local repe = false
    if mounts ~= nil then
        for _, line in pairs(mounts) do
            local lineSplit = split(line, " ")
            if string.find(lineSplit[1], "dev") ~= nil then
                if mountsTable[lineSplit[1]] ~= nil then
                    repe = true
                    break
                else
                    mountsTable[lineSplit[1]] = 1
                end
            end
        end
    end

    return repe
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

local function readMounts()
    local defalutFsType = {
        ["xfs"] = 1,
        ["ext2"] = 2,
        ["ext3"] = 3,
        ["ext4"] = 4,
    }
    local mountFile = "/proc/mounts"
    local mounts = readFile(mountFile)
    local mountsTable = {}
    if mounts ~= nil then
        for _, line in pairs(mounts) do
            local lineSplit = split(line, " ")
            if defalutFsType[lineSplit[3]] ~= nil then
                if lineSplit[2] ~= "/" and lineSplit[2] ~= "swap" and lineSplit[2] ~= "/boot" then
                    if mountsTable[lineSplit[2]] == nil then
                        mountsTable[lineSplit[2]] = 1
                    end

                end
            end
        end
    end
    --print("mountsTable")
    --for k,v in pairs(mountsTable) do
    --    print(k, v)
    --end
    --print("end")
    return mountsTable
end

local function mountedRoot()
    local fsTab = readFstab()
    local mounts = readMounts()
    local mountRootStatus = false
    for _,v in pairs(fsTab) do
        if mounts[v] == nil then
            mountRootStatus = true
            break
        end
    end
    return mountRootStatus
end

local function mountStatus()
    local curTime = os.time()
    local mountTable = {
       ["timestamp"]  = curTime,
       ["mounted"] = {}
    }
    local mount = {}
    mount["multi_status"] = mountRepe()
    mount["root"] = mountedRoot()

    local machineId = machineID()
    for k,v in pairs(mountTable) do
        print(k, v)
    end
    local tags = {
        ["machine_id"] = machineId
    }
    local tmp_data = {
        ["tags"] = tags,
        ["fields"] = mount
    }

    mountTable["mounted"][1] = tmp_data
    return mountTable
end

--mountStatus()
-- test pass

function collect(out)
    local curTime = os.time()
    local statData = mountStatus()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end