-- Marking: lua,input,block_device,1

local input = {
    category = "input",
    name = "disk",
    dataVersion = "1",
    indicator = "disk"
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

local function diskUsage()
    local diskTable = {}
    local result = executeCmd("/usr/bin/python3 /opt/quality/lshw_v5.py")
    print("disk cap", result)
    if result ~= nil then
        local resultSplit = split(result, ",")
        for _, v in pairs(resultSplit) do
            local vsplit = split(v, "#")
            local tmp = {
                ["diskcap"] = vsplit[2],
                ["disktype"] = vsplit[3],
                ["diskusage"] = vsplit[4],
                ["mountpoint"] = vsplit[5],
                ["hderror"] = vsplit[6]
            }
            diskTable[vsplit[1]] = tmp
        end
    end

    return diskTable
end

local function parseFile()
    local curTime = os.time()
    local diskTable = {
        ["timestamp"] = curTime
    }
    local diskStatsTable = {}
    local diskStatsFile = "/proc/diskstats"
    --k[4] rd_ios
    --k[7] rd_ticks
    --
    --k[8] wr_ios
    --k[11] wr_ticks
    --
    --k[13] io_ticks

    --  _, _, dev, rd_ios, _, _, rd_ticks, wr_ios, _, _,wr_ticks, _, io_ticks  = line.split()
    local linesTable = readFile(diskStatsFile)
    local diskUsageTable = diskUsage()

    if linesTable ~= nil and diskUsageTable ~= nil then
        for _, v in pairs(linesTable) do
            print(v)
            local words = split(v, " ")
            if (#words == 18) then
                local tableV = {
                    ["rd_ios"] = words[4],
                    ["rd_ticks"] = words[7],
                    ["wr_ios"] = words[8],
                    ["wr_ticks"] = words[11],
                    ["io_ticks"] = words[13],
                    ["disk_data"] = 0
                }

                if diskUsageTable[words[3]] ~= nil then
                    tableV["diskcap"] = diskUsageTable[words[3]]["diskcap"]
                    tableV["disktype"] = diskUsageTable[words[3]]["disktype"]
                    tableV["diskusage"] = diskUsageTable[words[3]]["diskusage"]
                    tableV["mountpoint"] = diskUsageTable[words[3]]["mountpoint"]
                    tableV["hderror"] = diskUsageTable[words[3]]["hderror"]
                    tableV["disk_data"] = 1

                end

                diskStatsTable[words[3]] = tableV
            end
        end
    else
        diskTable["disk"] = nil
        return diskTable
    end

    for k, v in pairs(diskStatsTable) do
        for kk, vv in pairs(v) do
            print(k, kk, vv)
        end
    end

    diskTable["disk"] = diskStatsTable
    return diskTable
end

--parseFile()
--test pass

function collect(out)
    local curTime = os.time()
    local diskData = parseFile()
    for key, data in pairs(diskData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(diskData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
