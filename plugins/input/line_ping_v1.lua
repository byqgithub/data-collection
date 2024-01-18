-- Marking: lua,input,line_ping,1

local input = {
    category = "input",
    name = "line_ping",
    dataVersion = "1",
    indicator = "line_ping"
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

local function lineCount()
    local count = 1
    local pppcmd = "ip addr | grep inet | grep ppp | wc -l"
    local pppCount = executeCmd(pppcmd)
    if tonumber(pppCount) > 0 then
        local cntcmd = "ip addr | grep inet | grep global | grep ppp 2>/dev/null |wc -l"
        local cnt = executeCmd(cntcmd)
        count = tonumber(cnt)
        --for k ,v in pairs(count) do
        --    print(k,v)
        --end
        return count
    end

    local wancmd = "ip addr | grep inet | grep wan | wc -l"
    local wanCount = executeCmd(wancmd)
    if tonumber(wanCount) > 0 then
        local cntcmd = "ip addr | grep inet | grep global | grep wan 2>/dev/null |wc -l"
        local cnt = executeCmd(cntcmd)
        count = tonumber(cnt)
        --for k ,v in pairs(count) do
        --    print(k,v)
        --end
        return count
    end
    --for k ,v in pairs(count) do
    --    print(k,v)
    --end
    return count
end


local function pingCheck()
    local cmd = [=[
#!/bin/bash

source /etc/profile

OUTER_TEST_URL="47.114.74.103:60080"
OUTER_TEST_IPV6_URL_1="2408:4002:1109:5940:ef4d:abe8:6fa8:2c09:60078"
OUTER_TEST_IPV6_URL_2="2408:400d:1000:d01:523:d4f1:1107:65de:60078"

real_ping_check(){
	local interface=$1
	local ip=$2
	ping_v=`ping -c 1 -w 2 $ip -I $interface 2>/dev/null`

	ping_count=$(echo $ping_v | grep ttl | wc -l)

	if [ "$ping_count" == "1" ];then
		TTL=$(echo $ping_v | awk -Ficmp_seq '{print $2}' | awk '{print $2}' | awk -F= '{print $2}')
		TIME=$(echo $ping_v | awk -Ficmp_seq '{print $2}' | awk '{print $3}' | awk -F= '{print $2}')
	else
		TTL=-1
		TIME=-1
	fi

	#echo "$interface-$TTL-$TIME"
}

ping_check_one_line()
{
	local dev_ip=$2
	local interface=$1

	local ips=("api.painet.work" "internal.api.paigod.work" "datachannel.painet.work")
	local success=0
	local ttl=0
	local time=0.0

	for i in ${ips[@]}
	do
		#echo "ping_check $interface $i"
		real_ping_check $interface $i
		if [ $TTL -gt 0 ]; then
			success=$(($success + 1))
			ttl=$(($ttl+$TTL))
			time=$(echo "$time $TIME" | awk '{printf("%0.1f", $1 + $2)}')
		fi
	done

	local flow=$(dev_net_flow $dev)
	local outer_ip=$(find_dev_outer_ip $interface)
	local ipv6=$(ip addr | grep -wA 3 $interface | grep inet6 | grep global | awk '{split($2,a, "/");print a[1]}')
	local ipv6_status="0"
  if [ ! -z "${ipv6}" ]; then
    ipv6_status=$(check_ip_v6 $dev)
  fi

    if [ $ipv6 =="" ]; then
        ipv6=1
    fi

	if [ "$outer_ip" == "" ]; then
		echo "$interface-$dev_ip-$ipv6-${ipv6_status}-$success-$ttl-$time-$flow-0-1-0-0"
	else
		echo "$interface-$outer_ip-$ipv6-${ipv6_status}-$success-$ttl-$time-$flow-1-1-0-0"
	fi

}

ping_check()
{
	if [ $(ip addr | grep inet | grep ppp | wc -l) -gt 0 ]; then
		ip addr | grep inet | grep global | grep ppp | while read line
		do
			local dev_ip=$(echo $line | awk '{print $2}' | awk -F/ '{print $1}')
			local dev=$(echo $line | awk '{print $NF}')
			ping_check_one_line $dev $dev_ip
		done

	elif [ $(ip addr | grep inet | grep wan | wc -l) -gt 0 ]; then

		ip addr | grep inet | grep global | grep wan | while read line
		do
			local dev_ip=$(echo $line | awk '{print $2}' | awk -F/ '{print $1}')
			local dev=$(echo $line | awk '{print $NF}')

			ping_check_one_line $dev $dev_ip
		done
	else
		default_gateway=$(ip route  | grep default | head -n 1)
		if [ "$default_gateway" == "" ]; then
			return
		fi

		local dev_ip=$(echo $default_gateway | awk '{print $3}')
		local dev=$(echo $default_gateway | awk '{print $5}')

		ping_check_one_line $dev $dev_ip
		return
	fi
}

find_dev_ip()
{
	local dev=$1
	ip=$(ip addr show $dev | grep inet | grep global | awk -F/ '{print $1}' | awk '{print $2}')
	echo $ip
}

find_dev_outer_ip()
{
	local dev=$1
	local result=$(curl --interface $dev --connect-timeout 2 -m 3 $OUTER_TEST_URL 2>/dev/null)

	if [ $? -gt 0 ]; then
		echo ""
	else
		local outer_ip=$(echo $result | awk -F: '{print $1}')
		echo $outer_ip
	fi
}

if_public_ip()
{
	local dev_ip=$1
	local dev=$2

	local outer_ip=$(find_dev_outer_ip $dev)

	if [ "$dev_ip" == "$outer_ip" ]; then
		echo "1"
	else
		echo "0"
	fi
}

check_ip_v6() {
  local dev=$1
  local status="0"
  if [ ! -z "$dev" ];then
    curl -s --interface $dev --connect-timeout 2 -m 3 -6 $OUTER_TEST_IPV6_URL_1 2>&1 >/dev/null
		if [ $? -gt 0 ]; then
			curl -s --interface $dev --connect-timeout 2 -m 3 -6 $OUTER_TEST_IPV6_URL_2 2>&1 >/dev/null
			if [ $? -gt 0 ]; then
			  status="0"
			else
			  status="1"
			fi
		else
		  status="1"
		fi
	fi
	echo $status
}

dev_net_flow()
{
	local dev=$1
	rc=$(cat /proc/net/dev | grep -w "$dev:" | awk '{print $2}')
	if [ "$rc" == "" ]; then
		rc="0"
	fi

	sd=$(cat /proc/net/dev | grep -w "$dev:" | awk '{print $10}')
	if [ "$sd" == "" ]; then
		sd="0"
	fi

	echo "$rc-$sd"
}

ping_check
    ]=]
    local curTime = os.time()
    local machineId = machineID()
    local pingTable = {
        ["timestamp"] = curTime,
        ["lines"] = {},
        ["line_count"] = nil,
        ["line_drop"] = nil,
    }
    local pingData = {}
    local pingRes = executeCmd(cmd)
    print(pingRes)
    local pingResSplit = split(pingRes, "\n")
    local index = 1
    for idx, line in ipairs(pingResSplit) do
        local lineSplit = split(line, "-")
        --for i, k in ipairs(lineSplit) do
        --    print(i, k)
        --end
        --    Name                string  `json:"name"` // net card of this line, TODO: consider line redial ?
        --IP                  string  `json:"ip"`
        --IPV6                string  `json:"ip_v6"`
        --IPV6_Outgoing       bool    `json:"ipv6_outgoing"`
        --TTL                 int32   `json:"ttl"`
        --Time                float32 `json:"time"`
        --Success             float32 `json:"success"`
        --Bw_upload           int64   `json:"bw_upload"`
        --Bw_download         int64   `json:"bw_download"`
        --Outgoing            bool    `json:"outgoing"`
        --Incoming            bool    `json:"incoming"`
        --Press_upload_bw_max int64   `json:"press_upload_bw_max"` // ASK: not from Bw_upload
        --    Press_upload_bw_avg int64   `json:"press_upload_bw_avg"` // ASK: the same as max ?
        --Nat_type            int64   `json:"nat_type"`
        --TcpResendRatio      float64 `json:"tcp_resend_ratio"`

        local ipv6_out = tonumber(lineSplit[4])
        local ipv6_outgoing = false
        if ipv6_out > 0 then
            ipv6_outgoing = true
        end

        local ipv6 = lineSplit[3]
        if ipv6 == "1" then
            ipv6 = ""
        end

        local success_count = tonumber(lineSplit[5])
        local ttl = -1
        local time = -1
        if success_count > 0 then
            ttl = math.floor(tonumber(lineSplit[6]) / success_count)
            time = tonumber(lineSplit[7]) / success_count
        end
        local success = success_count * 100 / 3.0

        local incoming = false
        local outgoing = false

        local ifi = tonumber(lineSplit[10])
        if ifi > 0 then
            outgoing = true
        end

        local ifo = tonumber(lineSplit[11])
        if ifo > 0 then
            incoming = true
        end

        local tmp = {
            --["name"] = lineSplit[1],
            ["ip"] = lineSplit[2],
            ["ipv6"] = ipv6,
            ["ipv6_outgoing"] = ipv6_outgoing,
            ["ttl"] = ttl,
            ["time"] = time,
            ["success"] = success,
            ["outgoing"] = outgoing,
            ["incoming"] = incoming,
            ["bw_upload"] = 0,
            ["bw_download"] = 0,
            ["press_upload_bw_max"] = -1,
            ["press_upload_bw_avg"] = -1
        }
        pingData[idx] = tmp


        local tags = {
            ["machine_id"] = machineId,
            ["name"] = lineSplit[1],
        }

        local tmp_data = {
            ["tags"] = tags,
            ["fields"] = tmp
        }
        pingTable["lines"][index] = tmp_data
        index = index + 1
    end
    --for k, v in pairs(pingData) do
    --    for kk,vv in pairs(v) do
    --        print(k, kk, vv)
    --    end
    --end
    local lineC = lineCount()
    local lineDrop = false
    if lineC > tableLen(pingData) then
        lineDrop = true
    end
    --pingTable["ping"] = pingData

    --local line_count = {
    --    ["fields"] = {
    --        ["line_count"] = lineC
    --    },
    --    ["tags"] = {
    --        ["machine_id"] = machineId
    --    }
    --}
    --
    --local line_drop = {
    --    ["fields"] = {
    --        ["line_drop"] = lineDrop
    --    },
    --    ["tags"] = {
    --        ["machine_id"] = machineId
    --    }
    --}

    pingTable["line_count"] = lineC
    pingTable["line_drop"] = lineDrop
    return pingTable
end

--pingCheck()
--test pass


function collect(out)
    local curTime = os.time()
    local statData = pingCheck()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end