-- Marking: lua,input,pppoe,1

local input = {
    category = "input",
    name = "pppoe",
    dataVersion = "1",
    indicator = "pppoe"
}

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

local function printTable(value)
    for k, v in pairs(value) do
        print(string.format("key: %s, value: %s", k, v))
    end
end

local function tableLen(t)
    local len=0
    for _, _ in pairs(t) do
        len=len+1
    end
    return len;
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

local function pppoeDial()
    local curTime = os.time()

    local machineId = machineID()

    local reportTable = {
        ["timestamp"] = curTime,
        ["pppoe"] = nil
    }
    local pppoeTable = {}
    local pppoeTmp = {}
    local pppoeFile ="/var/log/pai_pppoe.log"
    local timestrings = ""
    for i = 1,5,1 do
        local t = (os.time() - (i * 60))
        local timestr = os.date("%Y-%m-%d %H:%M:", t)
        if i == 1 then
            timestrings = timestr
        else
            timestrings = timestrings .. "|" .. timestr
        end
    end
    local cmd = string.format("grep -E '%s' %s | grep '启动拨号线路' | ", timestrings, pppoeFile) .. "awk -F':' '{s[$5] += 1}END{for(i in s){printf\"%s:%d\\n\",i,s[i]}}' | tr -d ' ' | sed ':a;N;s/\\n/--/;ba;'"
    print(cmd)
    local ppLines = executeCmd(cmd)
    if ppLines == "" or ppLines == nil then
        --local tags = {
        --    ["machine_id"] = machineId,
        --}
        --
        --local tmp_data = {
        --    ["tags"] = tags,
        --    ["fields"] = {}
        --}
        --reportTable["pppoe"][1] = tmp_data
        return reportTable
    end

    local ppdial = split(ppLines, "--")
    printTable(ppdial)
    local pplen = tableLen(ppdial)
    for i = 1, pplen, 1 do
        local tmp = split(ppdial[1], ":")
        local pp = {
            --["name"] = tmp[1],
            ["count"] = tonumber(tmp[2])
        }

        local tags = {
            ["machine_id"] = machineId,
            ["name"] = tmp[1],
        }

        local tmp_ = {
            ["tags"] = tags,
            ["fields"] = pp
        }
        pppoeTable[i] = tmp_

    end
    for k,v in pairs(pppoeTable) do
        for kk, vv in pairs(v) do
            print(k, kk, vv)
        end
    end
    reportTable["pppoe"] = pppoeTable
    return reportTable
end

pppoeDial()
--local pp = pppoeDial()
--for k,v in pairs(pp) do
--    for kk, vv in pairs(v) do
--        print(k, kk, vv)
--    end
--
--end
--test pass

function collect(out)
    local curTime = os.time()
    local statData = pppoeDial()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end