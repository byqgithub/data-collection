package executor

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/PPIO/pi-collect/agent/services"
	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/logger"
	"github.com/PPIO/pi-collect/manager"
	operator "github.com/PPIO/pi-collect/pkg/docker_operator"
	"github.com/PPIO/pi-collect/pkg/util"
	"github.com/PPIO/pi-collect/report"
	"github.com/PPIO/pi-collect/storage"

	log "github.com/sirupsen/logrus"
)

var (
	pluginConfig  config.Config
	dataBox       *storage.DataBox
	pluginManager *manager.LuaPluginManager
	ticker        Ticker
)

//Init framework init
func Init(
	ctx context.Context,
	wg *sync.WaitGroup,
	configStr string,
	logConfig config.LogConfig) error {
	log.Infoln("Init environment")

	deviceId := util.GetMachineId()
	util.DeviceId = deviceId
	if deviceId == util.DefaultMachineId {
		return fmt.Errorf("can not get device id")
	}
	if deviceId == "" {
		return fmt.Errorf("device id is empty")
	}
	//log.Debugf("Local machine id %v", deviceId)

	pluginConfig = config.NewConfig()
	err := pluginConfig.Parse(configStr)
	if err != nil {
		log.Errorf("Parse config error: %v", err)
		return err
	}

	go services.AgentInit(deviceId, pluginConfig.Global.CenterAddr)
	go services.ParseWatchPlugin()

	operator.NewDockerOperator(ctx, wg, "polling", pluginConfig.DockerConf)

	dataBox = storage.NewDataBox(
		ctx,
		pluginConfig.Global.CheckPeriod,
		pluginConfig.Global.CacheExpiration,
		pluginConfig.DBConf)

	logger.CreatePluginLoggerPool(logConfig)

	total := pluginConfig.Len()
	pluginManager = manager.NewLuaPluginManager()
	err = pluginManager.InitEnv(total * 2)
	if err != nil {
		log.Errorln("Plugin manager init failed")
		return err
	}
	err = pluginManager.LoadPlugins(&pluginConfig.Running)
	if err != nil {
		log.Errorln("Plugin load failed")
		return err
	}

	ticker = NewTicker(pluginConfig.Global.Interval)
	report.StartHTTPReport(ctx, wg, dataBox, pluginConfig.DBConf.ReportBucket)
	wg.Add(1)
	go pluginManager.Receive(ctx, wg, &pluginConfig)

	return nil
}

func onceExecute(timeRange []time.Duration) {
	pluginManager.Lock.Lock()
	log.Debugf("Get lock, for execute plugins")
	defer pluginManager.Lock.Unlock()

	timeout := time.Duration(pluginConfig.Global.Interval / int64(len(pluginConfig.Global.PluginCategory)))
	for _, plugin := range pluginManager.RunningInput {
		err := plugin.Collect(timeout, dataBox, &pluginConfig)
		if err != nil {
			log.Errorf("Plugin %v %v %v %v run-time error: %v",
				plugin.Pattern, plugin.Category, plugin.Name, plugin.Version, err)
		}
	}
	for _, plugin := range pluginManager.RunningProcessor {
		err := plugin.Dispose(timeout, timeRange, dataBox)
		if err != nil {
			log.Errorf("Plugin %v %v %v %v run-time error: %v",
				plugin.Pattern, plugin.Category, plugin.Name, plugin.Version, err)
		}
	}
	for _, plugin := range pluginManager.RunningAggregator {
		err := plugin.Converge(timeout, timeRange, dataBox)
		if err != nil {
			log.Errorf("Plugin %v %v %v %v run-time error: %v",
				plugin.Pattern, plugin.Category, plugin.Name, plugin.Version, err)
		}
	}
	for _, plugin := range pluginManager.RunningOutput {
		err := plugin.Write(timeout, timeRange, dataBox)
		if err != nil {
			log.Errorf("Plugin %v %v %v %v run-time error: %v",
				plugin.Pattern, plugin.Category, plugin.Name, plugin.Version, err)
		}
	}
}

func waitGapTicker(ctx context.Context, waitGap int64) {
	// now: 				wait_gap	next execution
	// 2020-01-01 10:10:20	280			2020-01-01 10:15:00
	// 2020-01-01 10:10:30	270			2020-01-01 10:15:00
	waitTicker := time.NewTicker(time.Second * time.Duration(waitGap))
	defer waitTicker.Stop()

	//log.Debugf("Wait Gap %v", time.Second * time.Duration(waitGap))
	select {
	case <-ctx.Done():
		log.Debugln("Process stop signal, waitGapTicker exit")
		break
	case <-waitTicker.C:
		//log.Debugln("End wait")
		break
	}
}

func adjustmentTime(ctx context.Context) {
	gap := pluginConfig.Global.Interval
	now := time.Now().Unix()
	integralNow := time.Now().Truncate(time.Second * time.Duration(gap)).Unix()
	if now-integralNow >= gap || now-integralNow == 0 {
		log.Debugf("Now %v, integral time %v, start collection now", now, integralNow)
		return
	} else {
		wait := integralNow + gap - now
		log.Debugf("Now %v, integral time %v, wait %v", now, integralNow, wait)
		waitGapTicker(ctx, wait)
	}
}

// first collect data when framework start
func firstCollect(ctx context.Context) {
	select {
	case <-ctx.Done():
		break
	default:
		pluginManager.Lock.Lock()
		log.Debugf("Get lock, for first collect plugins")
		defer pluginManager.Lock.Unlock()
		//timeRange := ticker.generateTimeRange(pluginConfig.Global.Interval)
		timeout := time.Duration(pluginConfig.Global.Interval / int64(len(pluginConfig.Global.PluginCategory)))
		for _, plugin := range pluginManager.RunningInput {
			err := plugin.Collect(timeout, dataBox, &pluginConfig)
			if err != nil {
				log.Errorf("Plugin %v %v %v %v run-time error: %v",
					plugin.Pattern, plugin.Category, plugin.Name, plugin.Version, err)
			}
		}
	}
}

func Execute(ctx context.Context) {
	adjustmentTime(ctx)
	go firstCollect(ctx)
	ticker.Start()

Loop:
	for {
		select {
		case <-ctx.Done():
			break Loop
		case <-ticker.ticker.C:
			timeRange := ticker.generateTimeRange(pluginConfig.Global.Interval)
			//log.Debugf("timeRange %+v", timeRange)
			onceExecute(timeRange)
		case signal, ok := <-pluginManager.PluginReady:
			if ok && signal == 0 {
				log.Debugf("Receive plugin update signal, update plugin instance")
				pluginManager.ReplaceRunningPlugin()
				pluginConfig.ReplaceRunningConfig()
				log.Debugf("Send plugin update finish signal")
				pluginManager.PluginUpdateFinish <- true
			} else if ok && signal == 1 {
				log.Debugf("Receive plugin delete signal, delete plugin instance")
				pluginManager.RemoveRunningPlugin(&pluginConfig.Delete)
				pluginConfig.RemoveDeleteConfig()
				log.Debugf("Send plugin delete finish signal")
				pluginManager.PluginUpdateFinish <- true
			} else {
				log.Warningf("Plugin ready signal channel close")
			}
		}
	}
}

func Stop(cancel context.CancelFunc) {
	cancel()
	operator.Close()
	pluginManager.RemovePlugins()
	close(pluginManager.PluginUpdateFinish)
	dataBox.CloseDataBox()
	ticker.Close()
}
