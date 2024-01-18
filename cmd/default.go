package cmd

import "time"

const (
	//defaultRootPath = "/ipaas/collect"

	// log
	defaultLogPath         = "/ipaas/collect_framework/logs"
	defaultLogName         = "pi-collect.log"
	defaultLogLevel        = 5
	defaultLogMaxAge       = time.Hour * 1200
	defaultLogRotationTime = time.Hour * 24

	// config
	defaultConfigPath = "/ipaas/collect_framework/config/collect.json"

	// default machine id
	defaultMachineId = "123456789"
)
