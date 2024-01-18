-- Marking: lua,input,dcache_task,1

local input = {
    category = "input",
    name = "dcache_task",
    dataVersion = "1",
    indicator = "dcache_task"
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

local function checkDcacheExits()
    local cmd = [=[
        DCACHE_CONFIG_FILE="/opt/soft/ipes/var/db/ipes/dcache-conf/dcache.xml"
    	if [ $(ps aux | grep "ipes start -w /opt/soft/ipes" | grep -v grep | wc -l) -gt 0 ]; then
            if [ -f $DCACHE_CONFIG_FILE ]; then
                echo 1
            else
                echo 0
            fi
	    else
		    echo 0
	    fi
    ]=]
    local reslut = executeCmd(cmd)
    return reslut
end

local function checkDcache()
    local cmd = [=[
#!/bin/bash

DCACHE_CONFIG_FILE="/opt/soft/ipes/var/db/ipes/dcache-conf/dcache.xml"

check_dcache_running_status()
{
	if [ $(ps -ef | grep dcache | grep -v grep | wc -l ) -eq 0 ];then
		echo 0
		return
	fi

	if [ $(ps -ef | grep ipes | grep -v grep | wc -l ) -eq 0 ];then
		echo 0
		return
	fi

	if [ $(ps -ef | grep css | grep -v grep | wc -l ) -eq 0 ];then
		echo 0
		return
	fi

	echo 1
}

check_dcache_mem()
{
	local used_cache=$(cat $DCACHE_CONFIG_FILE 2>/dev/null | grep usecache | grep -Eo '[0-9]+')
	local IS_MULTI=0
	if [ $(docker ps 2>/dev/null | tail -n +2 | grep -v ipes | wc -l) -gt 0 ]; then
		IS_MULTI=1
	fi

	local B="$(free -m | tail -n +2 | head -1 | awk '{print $2}')"
	local C="$(expr $B - 16000)"
	if [ $IS_MULTI -eq 1 ]; then
		C="$(expr $C / 2)"
	fi
	local LEVEL=1
	if [ "$used_cache" -gt $C ]; then
		LEVEL=0
	fi
	used_cache=$(($used_cache * 1024 * 1024))
	echo "$used_cache++$LEVEL"
}

check_dcache_nat()
{
	local host_net_type=$1
	local nat=$(cat $DCACHE_CONFIG_FILE 2>/dev/null | grep EnableNatCheck | grep -Eo '[0-9]+')

	if_correct=0
	if [ $nat -eq 1 ]; then
		if [ $host_net_type -eq 2 -o $host_net_type -eq 3  ]; then
			if_correct=1
		fi
	else
		if [ $host_net_type -eq 1 -o $host_net_type -eq 4 -o $host_net_type -eq 5 ]; then
			if_correct=1
		fi
	fi

	echo "$nat++$if_correct"
}

check_dcache_multiline()
{
	local host_net_type=$1
	local multiLine=$(cat $DCACHE_CONFIG_FILE | grep MultiLineScene | grep -Eo '[0-9]+')

	if_correct=0
	if [ $multiLine -eq 1 ]; then
		if [ $host_net_type -eq 1 -o $host_net_type -eq 2 -o $host_net_type -eq 5  ]; then
			if_correct=1
		fi
	else
		if [ $host_net_type -eq 3 -o $host_net_type -eq 4 ]; then
			if_correct=1
		fi
	fi

	echo "$multiLine++$if_correct"
}

check_dcache_port_8400()
{
	if_port_listen=$(ss -nltp |grep 8400 | grep dcache | wc -l)
	echo $if_port_listen
}

check_dcache_process_info()
{
	local p_info=$(ps -eo etime,rsz,comm | grep "dcache")
	local exec_time=$(echo $p_info | awk '{print $1}')
	local p_mem=$(echo $p_info | awk '{print $2}')
	p_mem=$(($p_mem * 1024))
	#echo "exec_time:$exec_time"
	local time_field_count=`echo $exec_time | awk -F: '{print NF}'`
	local count_of_minutes=`echo $exec_time | awk -F: '{print $(NF-1)}'`
	local count_of_seconds=`echo $exec_time | awk -F: '{print $NF}'`
	#echo "time_field_count:$time_field_count  count_of_minutes:$count_of_minutes count_of_seconds:$count_of_seconds"

	if [ $time_field_count -lt 3 ]; then
		count_of_hours=0
		count_of_days=0
	else
		local tmp=`echo $exec_time | awk -F: '{print $(NF-2)}'`
		fields=`echo $tmp | awk -F- '{print NF}'`
		#echo "tmp:$tmp  fields:$fields"
		if [ $fields -ne 1 ]; then
			count_of_days=`echo $tmp | awk -F- '{print $1}'`
			count_of_hours=`echo $tmp | awk -F- '{print $2}'`
		else
			count_of_days=0
			count_of_hours=$tmp
		fi
	fi
	if [ "$count_of_hours" != "0" ];then
		count_of_hours=$(if [ `echo $count_of_hours | grep ^0` ]; then echo ${count_of_hours:1}; else echo $count_of_hours; fi)
	fi
	if [ "$count_of_minutes" != "0" ];then
		count_of_minutes=$(if [ `echo $count_of_minutes | grep ^0` ]; then echo ${count_of_minutes:1}; else echo $count_of_minutes; fi)
	fi
	if [ "$count_of_seconds" != "0" ];then
		count_of_seconds=$(if [ `echo $count_of_seconds | grep ^0` ]; then echo ${count_of_seconds:1}; else echo $count_of_seconds; fi)
	fi
	#echo "count_of_days:$count_of_days  count_of_hours:$count_of_hours count_of_seconds:$count_of_seconds"
	p_time=$(($count_of_days*86400 + $count_of_hours*3600 + $count_of_minutes*60 + $count_of_seconds))
	echo "$p_time++$p_mem"
}

check_dcache_disk()
{
	local if_ok=1
	local total_size=0
	local used_size=0
	local total_rota=0
	for i in $(cat $DCACHE_CONFIG_FILE 2>/dev/null | grep file_path | awk -F\" '{print $2}' | awk -F/ '{print $2}')
	do
		read if_find total used rota <<< $(real_check_one_disk $i)
		if [ $if_find -eq 0 ]; then
			if_ok=0
			continue
		fi

		total_size=$(($total_size + $total))
		used_size=$(($used_size + $used))
		total_rota=$(($total_rota + $rota))
	done

	if [ $total_size -gt 0 ]; then
		usage=$(($used_size * 1000 / $total_size))
		echo "$if_ok++$total_size++$usage++$total_rota"
	else
		echo "0++0++0++1"
	fi
}

real_check_one_disk()
{
	local disk_path=$1
	local info=$(df | grep $disk_path$)

	if [ "$info" == "" ]; then
		echo "0 0 0 1"
		return
	fi

	local total_size=$(echo $info | awk '{print $2}')
	local used_size=$(echo $info | awk '{print $3}')
	local rota=$(lsblk -d -o name,rota $(echo $info | awk '{print $1}') 2>/dev/null | tail -n 1 | awk '{print $NF}')
	if [ "$rota" == "" ]; then
		echo "0 0 0 1"
	else
		echo 1 $total_size $used_size $rota
	fi
}

check_dcache_deviceid()
{
	local device_id=$(cat /opt/soft/dcache/deviceid 2>/dev/null )
	echo $device_id
}

check_dcache_net_flow()
{
#       net_flow=$(tail -n 100 /opt/soft/dcache/log/dcache.log 2>/dev/null | grep "deliver flow" | tail -n 1 | awk -F"deliver flow:" '{print $2}' | awk '{print $1}')
#       net_flow=$(( $net_flow * 1024 ))
#       echo $net_flow
    python3 /opt/quality/get_dcache_logflow.py --tasklogflow
}

check_if_ks_exist()
{
    local cnt=$(ps --no-heading -fC ksp2p-server | wc -l)
    if [ $cnt -gt 0 ]; then
	echo 1
    else
	echo 0
    fi
}

check_dcache_bandwidth() {
    bandwidth=`cat /opt/soft/ipes/var/db/ipes/dcache-conf/dcache.xml 2>/dev/null | grep 'bandwidth' | awk -F'>' '{split($2,a,"<");print a[1]}'`
    if [ ! -z ${bandwidth} ];then
      echo ${bandwidth}
    else
      echo 0
    fi
}


check_dcache_user_speed() {
  m=""
  for((i=1;i<6;i++));do
    if [ ${i} -eq 1 ];then
      m=$(date "+%Y-%m-%d %H:%M" -d "${i} min ago")
    else
      m="$(date "+%Y-%m-%d %H:%M" -d "${i} min ago")|${m}"
    fi
  done
  #echo ${m}
  #speed kbps
  grep -E "${m}" /opt/soft/dcache/log/access.log* 2>/dev/null | grep 'SPEED' | awk -F'(SPEED:|kbps)' '{count++;if($2>0){gzcount++};speed+=$2}END{if(gzcount>0){printf "%s++%s++%s", count,gzcount,speed/gzcount}else{printf "0++0++0"}}'
}



net_type=$(/opt/quality/net.sh net_type)
echo "1++$(check_dcache_running_status)++$(check_dcache_process_info)++$(check_dcache_mem)++$(check_dcache_nat $net_type)++$(check_dcache_multiline $net_type)++$(check_dcache_port_8400)++$(check_dcache_disk)++$(check_dcache_deviceid)++$(check_dcache_net_flow)++$(check_dcache_bandwidth)++$(check_dcache_user_speed)++$(check_if_ks_exist)"
    ]=]
    local res = executeCmd(cmd)
    return res
end

--checkDcache()

local function numberTobool(num)
    if num == 1 then
        return true
    end
    return false
end

local function parseLine(line)

    local dockers = {}
    local dcache = {}

    local dcacheSplit = split(line, "++")

    local dcache_running_status = numberTobool(tonumber(dcacheSplit[2]))
    local dcache_uptime = tonumber(dcacheSplit[3])
    local dcache_used_mem = tonumber(dcacheSplit[4])
    local dcache_config_mem = tonumber(dcacheSplit[5])
    local dcache_mem_correct = numberTobool(tonumber(dcacheSplit[6]))
    local dcache_config_nat = numberTobool(tonumber(dcacheSplit[7]))
    local if_net_correct = numberTobool(tonumber(dcacheSplit[8]))

    local dcache_config_multiline = numberTobool(tonumber(dcacheSplit[9]))
    local new_net_correct = numberTobool(tonumber(dcacheSplit[10]))
    local dcache_runtime_8400 = numberTobool(tonumber(dcacheSplit[11]))
    local dcache_disk_correct = numberTobool(tonumber(dcacheSplit[12]))
    local dcache_disk_total_size = tonumber(dcacheSplit[13])
    local dcache_disk_usage = tonumber(dcacheSplit[14])
    local dcache_disk_type = tonumber(dcacheSplit[15])
    local dcache_deviceid = dcacheSplit[16]

    local dcache_net_flow = tonumber(dcacheSplit[17])
    local dcache_bw_config = tonumber(dcacheSplit[18])
    dcache_bw_config = dcache_bw_config * 8 * 1024 * 1024

    local dcache_user_speed_count = tonumber(dcacheSplit[19])
    local dcache_user_speed_gt_zero_count = tonumber(dcacheSplit[20])
    local dcache_user_agv_speed = tonumber(dcacheSplit[21])

    if if_net_correct == true then
        if_net_correct = new_net_correct
    end

    if if_net_correct == true then
        if_net_correct = dcache_runtime_8400
    end

    dcache["exist"] = true
    dcache["config_mem"] = dcache_config_mem
    dcache["mem_correct"] = dcache_mem_correct
    dcache["config_nat"] = dcache_config_nat
    dcache["config_multiline"] = dcache_config_multiline
    dcache["runtime_8400"] = dcache_runtime_8400
    dcache["network_correct"] = if_net_correct
    dcache["disk_correct"] = dcache_disk_correct

    dockers["name"] = "dcache"
    dockers["idx"] = 1
    dockers["docker_id"] = ""
    dockers["custom_id"] = dcache_deviceid
    dockers["version"] = "0.0.0"
    dockers["version_program"] = "0.0.0"
    if dcache_disk_type == 0 then
        dockers["storage_type"] = "ssd"
    else
        dockers["storage_type"] = "hdd"
    end

    dockers["storage_size"] = dcache_disk_total_size
    dockers["storage_size"] = dcache_disk_usage / 10
    dockers["network_mode"] = "program"
    dockers["running_status"] = dcache_running_status
    dockers["running_count"] = 3
    dockers["uptime"] = math.floor(dcache_uptime)
    dockers["mem_size"] = dcache_config_mem
    dockers["mem_usage"] = (dcache_used_mem) * 100 / dcache_config_mem
    dockers["ping_ttl"] = 0
    dockers["ping_time"] = 0
    dockers["ping_success"] = 0
    dockers["incoming"] = 0
    dockers["outgoing"] = 0
    dockers["outer_ip"] = "0.0.0.0"
    dockers["cpu_usage"] = 0

    dockers["bs_bw_upload"] = dcache_net_flow

    dockers["bw_upload"] = 0
    dockers["bw_download"] = 0
    dockers["bw_config"] = dcache_bw_config
    dockers["user_speed_count"] = dcache_user_speed_count
    dockers["user_speed_gt_zero_count"] = dcache_user_speed_gt_zero_count
    dockers["user_avg_speed"] = dcache_user_agv_speed
    --if_have_dcache_running = true
    return dcache, dockers

end

local function dcacheCollect()
    local curTime = os.time()
    local dcache = {}
    local dockers = {}
    local dcacheTable = {
        ["timestamp"] = curTime,
        ["status"] = {},
        ["dcache"] = {}
    }
    local machineId = machineID()

    local dcacheStatus = {
        ["fields"] = {},
        ["tags"] = {
            ["machine_id"] = machineId
        }
    }

    local dcacheTmp = {
        ["fields"] = {},
        ["tags"] = {
            ["machine_id"] = machineId
        }
    }
    local isDcache = checkDcacheExits()
    if (tonumber(isDcache) == 0) then
        dcache["exist"] = false
        dcache["running"] = false
        dcache["mem"] = -1
        dcache["mem_correct"] = false
        dcache["nat"] = false
        dcache["multiline"] = false
        dcache["runtime_8400"] = false
        dcache["network_correct"] = false
        dcache["disk_correct"] = false

        dcacheStatus["fields"] = dcache

        dcacheTable["status"][1] = dcacheStatus
        dcacheTable["dcache"] = nil
        --dcacheTable["dcache"][1] = dcacheTmp
        return dcacheTable
    end

    local dcacheResult = checkDcache()
    dcache, dockers = parseLine(dcacheResult)

    dcacheStatus["fields"] = dcache
    dcacheTmp["fields"] = dockers

    dcacheTable["status"][1] = dcacheStatus
    dcacheTable["dcache"][1] = dcacheTmp
    for k, v in pairs(dcache) do
        print(k,v)
    end

    for k, v in pairs(dockers) do
        print(k, v)
    end
    return dcacheTable
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

--dcacheCollect()

--function collect(out, configObject)
    -- read task from local file
    --local globalStr = configObject:ConfigRawContent("global")
    --local globalConfig = jsonUnMarshal(globalStr)
    --local rootPath = globalConfig["plugin_root_path"]
    --local folder = string.format("%s/../output/", rootPath)
    --local fileName = "runningTask.txt"
    --local taskFile = folder .. fileName
    --local task = readFile(taskFile)
    --local isDcache = false
    --for _, v in pairs(task) do
    --    if string.find(v, "dcache") ~= nil then
    --        isDcache = true
    --        break
    --    end
    --end
    --
    --if isDcache == false then
    --    return
    --end
--end


function collect(out)
    local curTime = os.time()
    local statData = dcacheCollect()
    for key, data in pairs(statData) do
        print("input plugin: ", key, data)
    end
    local dataJson = jsonMarshal(statData)
    print("dev Data json: ", dataJson)
    out:AddField(input.category, input.name, input.dataVersion, input.indicator, "", dataJson, curTime)
end