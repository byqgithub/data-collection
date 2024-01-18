-- Marking: lua,input,memory,1

local keyword = {"MemTotal", "MemFree", "MemAvailable", "Buffers", "Cached", "timestamp"}

local input = {
    category = "input",
    name = "memory",
    dataVersion = "1",
    indicator = "memory"
}

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


function unitConvert(data, unit)
    if (string.find(unit, "k") ~= nil or string.find(unit, "K") ~= nil)
    then
        return tonumber(data) * 1024
    elseif (string.find(unit, "m") ~= nil or string.find(unit, "M") ~= nil)
    then
        return tonumber(data) * 1024 * 1024
    elseif (string.find(unit, "g") ~= nil or string.find(unit, "G") ~= nil)
    then
        return tonumber(data) * 1024 * 1024 * 1024
    else
        return tonumber(data)
    end
end

function parse()
    local store = {}
    local file = io.open("/proc/meminfo", "r")
    assert(file);
    for line in file:lines() do
        if (line ~= nil and string.len(line) ~= 0)
        then
            key, rawData, unit = string.match(line, "(%a*).*:%s*(%d*)%s*(%a*)")
            if (key ~= nil)
            then
                data = unitConvert(rawData, unit)
                store[key] = data
            end
        end
    end
    file:close()
    return store
end

function filter()
    local curTime = os.time()
    local collection = {}
    local memTable = {
        ["timestamp"] = curTime,
        ["memory"] = {}
    }
    local allData = parse()
    local data = {
        ["fields"] = {},
        ["tags"] = {
            ["machine_id"] = machineID()
        }
    }
    -- for key, data in pairs(allData)
    -- do
    --     print(key, data)
    -- end

    --for index, word in pairs(keyword)
    --do
    --    -- print("keyword: ", word)
    --    tmp = allData[word]
    --    if (tmp ~= nil)
    --    then
    --        collection[word] = tmp
    --    end
    --end
    local availableCount = allData["MemFree"] + allData["Buffers"] + allData["Cached"]
    data["fields"]["mem_size"] = allData["MemTotal"]

    data["fields"]["mem_usage"] = 100 * (allData["MemTotal"] - availableCount) / (allData["MemTotal"])
    print(" memory result:")

    memTable["memory"][1] = data
    for key, data in pairs(data)
    do
         print(key, data)
    end
    return memTable
end

--filter()
--test pass

function collect(out)
    local curTime = os.time()
    local memData = filter()
    --for key, data in pairs(memData)
    --do
    --    print("input plugin: ", key, data)
    --end
    local dataJson = jsonMarshal(memData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end

