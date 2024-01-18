package cmd

import (
	"context"
	"fmt"
	"io/ioutil"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/PPIO/pi-collect/build"
	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/executor"
	"github.com/PPIO/pi-collect/logger"
	"github.com/PPIO/pi-collect/pkg/util"

	log "github.com/sirupsen/logrus"
	command "github.com/spf13/cobra"
)

var (
	logConf          config.LogConfig // log config
	configFile       string
	specialMachineId string

	// RootCmd root command
	RootCmd          *command.Command
)

// ParseOpt parse opt
func ParseOpt()  {
	RootCmd = &command.Command{
		Use:     "pi-collect",
		Short:   "data collect framework",
		Version: build.Version,
	}

	var runCollectCmd = &command.Command{
		Use:     "collect",
		Short:   "start data collect",
		Args:  command.MaximumNArgs(10),
		RunE: func(cmd *command.Command, args []string) error {
			err := runCollect()
			if err != nil {
				fmt.Printf("Collect start error: %v\n", err)
				return err
			}
			return nil
		},
	}

	RootCmd.PersistentFlags().IntVar(
		&logConf.LogLevel,
		"log-level",
		defaultLogLevel,
		"log level, 0 panic, 1 fatal, 2 error, 3 warn, 4 info, 5 debug, 6 trace")

	RootCmd.PersistentFlags().StringVar(
		&logConf.LogPath,
		"log-path",
		defaultLogPath,
		"log path")

	RootCmd.PersistentFlags().StringVar(
		&logConf.LogName,
		"log-name",
		defaultLogName,
		"log name")

	RootCmd.PersistentFlags().Int64Var(
		&logConf.LogMaxAge,
		"log-age",
		int64(defaultLogMaxAge),
		"log max age")

	RootCmd.PersistentFlags().Int64Var(
		&logConf.LogRotationTime,
		"log-rotation",
		int64(defaultLogRotationTime),
		"log rotation time")

	RootCmd.PersistentFlags().StringVar(
		&configFile,
		"config-path",
		defaultConfigPath,
		"config path")

	runCollectCmd.PersistentFlags().StringVar(
		&specialMachineId,
		"special-machineId",
		"",
		"special machine Id")

	var versionCmd = &command.Command{
		Use:   "version",
		Short: "show version",
		Run: func(cmd *command.Command, args []string) {
			fmt.Printf("pi-collect version %s\n", build.Version)
		},
	}

	RootCmd.AddCommand(versionCmd)
	RootCmd.AddCommand(runCollectCmd)
	RootCmd.SetVersionTemplate(build.Version)
}

func runCollect() error {
	var err error
	fmt.Printf("Log Path %v\n", logConf.LogPath)
	logger.InitLog(
		logConf.LogPath,
		logConf.LogName,
		logConf.LogMaxAge,
		logConf.LogRotationTime,
		logConf.LogLevel)
	log.Infof("version: %v", build.Version)

	log.Debugf("Config file: %v", configFile)
	if !util.IsExists(configFile) {
		return fmt.Errorf("config file %v is not exists", configFile)
	}

	util.SpecialMachineId = specialMachineId
	util.DefaultMachineId = defaultMachineId

	ctx, cancel := context.WithCancel(context.Background())
	var wg sync.WaitGroup

	file, err := os.Open(configFile)
	if err != nil {
		return fmt.Errorf("open config %v error: %v", configFile, err)
	}
	defer func() { _ = file.Close() }()
	content, err := ioutil.ReadAll(file)

	err = executor.Init(ctx, &wg, string(content), logConf)
	if err != nil {
		log.Errorln("Collect framework start failed")
		return err
	}

	go executor.Execute(ctx)

	// quit
	sigquit := make(chan os.Signal)
	signal.Notify(sigquit, syscall.SIGTERM, syscall.SIGINT)
	log.Infoln("Start normally")
	select {
	case <-sigquit:
		log.Infoln("Stop sign")
		executor.Stop(cancel)
		wg.Wait()
		log.Infoln("Quit normally")
		return nil
	}
}
