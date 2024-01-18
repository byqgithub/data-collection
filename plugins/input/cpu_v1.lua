-- Marking: lua,input,system_cpu,1

local input = {
    category = "input",
    name = "system_cpu",
    dataVersion = "1",
    indicator = "system_cpu"
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

local function fileExists(file)
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
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

local function parseFile()
    local curTime = os.time()
    local cpuTable = {}
    local statTable = {}
    local statFile = "/proc/stat"
    --  cpu, user, nice, system, idle, iowait, irrq, softirq, steal, _, _ = line.split()
    local linesTable = readFile(statFile)
    local count = tableLen(linesTable)
    for _, v in pairs(linesTable) do
        --print(v)
        local words = split(v, " ")
        if string.find(words[1], "cpu") ~= nil and (#words == 11) then
            local total = tonumber(words[2]) + tonumber(words[3]) + tonumber(words[4]) + tonumber(words[5])
            total = total + tonumber(words[6]) + tonumber(words[7]) + tonumber(words[8]) +tonumber(words[9])
            local tableV = {
                ["user"] = words[2],
                ["nice"] = words[3],
                ["system"] = words[4],
                ["idle"] = words[5],
                ["iowait"] = words[6],
                ["irrq"] = words[7],
                ["softirq"] = words[8],
                ["steal"] = words[9],
                ["total"] = total
            }
            statTable[words[1]] = tableV
        end
    end
    cpuTable["timestamp"] = curTime
    cpuTable["cpu"] = statTable
    return cpuTable
end


--local function parseFile()
--    local statTable = {}
--    local statFile = "/proc/stat"
--    --  cpu, user, nice, system, idle, iowait, irrq, softirq, steal, _, _ = line.split()
--    local linesTable = readFile(statFile)
--    --local count = tableLen(linesTable)
--    for idx, v in pairs(linesTable) do
--        print(v)
--        local words = split(v, " ")
--        if words[1] ~= "cpu" and string.find(words[1], "cpu") ~= nil and (#words == 11) then
--            local total = tonumber(words[2]) + tonumber(words[3]) + tonumber(words[4]) + tonumber(words[5])
--            total = total + tonumber(words[6]) + tonumber(words[7]) + tonumber(words[8]) +tonumber(words[9])
--            local tableV = {
--                ["name"] = words[1],
--                ["user"] = words[2],
--                ["nice"] = words[3],
--                ["system"] = words[4],
--                ["idle"] = words[5],
--                ["iowait"] = words[6],
--                ["irrq"] = words[7],
--                ["softirq"] = words[8],
--                ["steal"] = words[9],
--                ["total"] = total
--            }
--            statTable[idx] = tableV
--        end
--    end
--
--    for k, v in pairs(statTable) do
--        for kk, vv in pairs(v) do
--            print(k, kk, vv)
--        end
--    end
--    return statTable
--end

--parseFile()
--test pass
function collect(out)
    local curTime = os.time()
    local statData = parseFile()
    --local newData = {}
    for key, data in pairs(statData) do
        --local jsonData = jsonMarshal(data)
        print("input plugin: ", key, data)
        --print("input plugin: ", key, jsonData)
        --newData[key] = jsonData
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
