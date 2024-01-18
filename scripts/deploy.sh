#!/bin/bash
systemctl stop trafficminute
bin_path="/ipaas/collect/bin"
conf_path="/ipaas/collect/config"
plugins_input="/ipaas/collect/plugins/input"
plugins_processor="/ipaas/collect/plugins/processor"
plugins_aggregator="/ipaas/collect/plugins/aggregator"
plugins_output="/ipaas/collect/plugins/output"
logs_path="/ipaas/collect/logs"
storage_path="/ipaas/collect/storage"
mkdir -p ${bin_path}
mkdir -p ${conf_path}
mkdir -p ${plugins_input}
mkdir -p ${plugins_processor}
mkdir -p ${plugins_aggregator}
mkdir -p ${plugins_output}
mkdir -p ${logs_path}
mkdir -p ${storage_path}

wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/collect -O ${bin_path}/collect
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/collect.json -O ${conf_path}/collect.json
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/input/iptables_rules.lua -O ${plugins_input}/iptables_rules.lua
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/input/machine_traffic.lua -O ${plugins_input}/machine_traffic.lua
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/input/task_identify.lua -O ${plugins_input}/task_identify.lua
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/input/task_traffic.lua -O ${plugins_input}/task_traffic.lua
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/processor/diff_value.lua -O ${plugins_processor}/diff_value.lua
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/aggregator/aggregation_data.lua -O ${plugins_aggregator}/aggregation_data.lua
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/output/http_report.lua -O ${plugins_output}/http_report.lua
wget http://pi-miner.oss-cn-beijing.aliyuncs.com/devops/pi-collect/collect.service -O ${bin_path}/collect.service

chmod 777 ${bin_path}/collect
#systemctl stop trafficminute
#rm -rf /usr/bin/paitraffic
#rm -rf /usr/lib/systemd/system/paitraffic.service
cp ${bin_path}/collect.service /usr/lib/systemd/system/
systemctl daemon-reload
systemctl start collect
systemctl enable collect

#python3 /opt/traffic/pai_flow_tag.py tag --clear
#echo "*/1 * * * * root python3 /ipaas/traffic/scripts/pai_flow_tag.py tag" > /etc/cron.d/paitraffic.cron
#cat > /etc/cron.d/paitraffic.cron << EOF
##*/1 * * * * root timeout 50 /usr/bin/python3 /ipaas/traffic/scripts/pai_flow_tag.py tag >/dev/null 2>/dev/null &
#*/1 * * * * root timeout 50 /usr/bin/python3 /ipaas/traffic/test/scripts/pai_flow_tag.py tag >/dev/null 2>/dev/null &
#EOF
#chattr +i /etc/cron.d/paitraffic.cron
#rm -rf /opt/traffic/*