-- Marking: lua,input,tcp_resend,1

local input = {
    category = "input",
    name = "tcp_resend",
    dataVersion = "1",
    indicator = "tcp_resend"
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

local function getTcpOutSegs()
    local cmd="cat /proc/net/snmp |grep Tcp | tail -n 1 | awk '{print $12}'"
    local result = executeCmd(cmd)
    return result
end

local function getTcpRetransSegs()
    local cmd="cat /proc/net/snmp |grep Tcp | tail -n 1 | awk '{print $13}'"
    local result = executeCmd(cmd)
    return result
end

local function tcpResend()
    local tcpTable = {}
    local curTime = os.time()
    local tcpOutSegs = getTcpOutSegs()
    local tcpRetransSegs = getTcpRetransSegs()
    tcpTable["timestamp"] = curTime
    tcpTable["tcpOutSegs"] = tcpOutSegs
    tcpTable["tcpRetransSegs"] = tcpRetransSegs

    --for k, v in pairs(tcpTable) do
    --    print(k, v)
    --end
    return tcpTable
end

function collect(out)
    local curTime = os.time()
    local devData = tcpResend()
    local dataJson = jsonMarshal(devData)
    log:Debugf("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end

