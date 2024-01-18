-- Marking: lua,input,type_vm,1

local input = {
    category = "input",
    name = "type_vm",
    dataVersion = "1",
    indicator = "type_vm"
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

local function isVm(line)
    local lineLower = string.lower(line)
    local vmKeyTable = {
        '440fx', 'virtio', 'kvm', 'xen', 'qemu', 'q35', 'hyper-v', 'vmlite', 'hvm', 'rhev', 'virtualbox', 'virtualpc', 'vmware', 'microsoft', 'red hat', 'virtual machine', 'kubevirt'
    }
    for _, k in ipairs(vmKeyTable) do
        if string.find(lineLower, k) ~= nil then
            return true
        end
    end
    return false

end

local function machineTypeVm()
    local curTime = os.time()
    local machineId = machineID()
    local machineVm = {
        ["timestamp"] = curTime,
        ["vm"] = {}
    }
    local type_vm = {
        ["fields"] = {
            ["vm"] = false
        },
        ["tags"] = {
            ["machine_id"] = machineId
        }
    }

    local cmd = "/usr/sbin/virt-what 2>/dev/null"
    local vm = executeCmd(cmd)
    if vm ~= nil then
        if vm == "" then
            cmd = "lspci 2>/dev/null | grep -v NetXen"
            local lspciOutput = executeCmd(cmd)
            local lspciOutputSplit = split(lspciOutput, "\n")
            --print(lspciOutput)
            for _, line in pairs(lspciOutputSplit) do
                local state = isVm(line)
                if state then
                    type_vm["fields"]["vm"] = state
                    machineVm["vm"][1] = type_vm
                    print(state)
                    return machineVm
                end
            end

            local dmidecodeOutput = "dmidecode 2>/dev/null | grep -vE \"NetXen|Serial Number\""
            local dmidecodeSplit = split(dmidecodeOutput, "\n")
            for _, line in pairs(dmidecodeSplit) do
                local state = isVm(line)
                if state then
                    type_vm["fields"]["vm"] = state
                    machineVm["vm"][1] = type_vm
                    print(state)
                    return machineVm
                end
            end
        else
            type_vm["fields"]["vm"] = true
            machineVm["vm"][1] = type_vm
        end

    end
    return machineVm
end

--machineTypeVm()


function collect(out)
    local curTime = os.time()
    local statData = machineTypeVm()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end