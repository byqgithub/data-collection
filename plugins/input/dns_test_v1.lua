-- Marking: lua,input,dns_test,1

local input = {
    category = "input",
    name = "dns_test",
    dataVersion = "1",
    indicator = "dns_test"
}

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

local function dnsTest()
    local curTime = os.time()
    local machineId = machineID()
    local dnsTable ={
        ["timestamp"] = curTime,
        ["dns_status"] = nil
    }
    local cmd = [=[
    #!/bin/bash
    host=("tracker.pcdn.yximgs.com" "tance.pcdn.yximgs.com" "punch.yximgs.com" "keepalive-report.pcdn.yximgs.com" "transfer-proxy.kcdn.yximgs.com" "router.conf.pcdn.yximgs.com" "www.baidu.com" "www.taobao.com" "www.qq.com")

    for i in ${host[@]}; do
        a=$(timeout 5 getent hosts $i)
        if [ ! $? -eq 0 ]; then
            if [[ $(timeout 5 dig $i | grep flags | grep ANSWER | awk -F'ANSWER: ' '{print $2}' | awk -F, '{print $1}' ) -le 0 ]];then
                echo 0
                exit
            fi
        fi
    done
    echo 1
    ]=]
    --local dns_status = {
    --    ["fields"] = {
    --        ["dns_status"] = tonumber(executeCmd(cmd))
    --    },
    --    ["tags"] = {
    --        ["machine_id"] = machineId
    --    }
    --}


    --dnsTable["dns_status"][1] = dns_status
    dnsTable["dns_status"] = tonumber(executeCmd(cmd))
    --for k,v in pairs(dnsTable) do
    --    print(k,v)
    --end
    return dnsTable

end

--dnsTest()
--test pass

function collect(out)
    local curTime = os.time()
    local statData = dnsTest()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end
