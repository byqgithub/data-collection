package manager

import (
	"context"
	"fmt"
	"sort"
	"sync"

	"github.com/PPIO/pi-collect/agent/services"
	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/models/luaplugin"
	"github.com/PPIO/pi-collect/pkg/engine"
	log "github.com/sirupsen/logrus"
)

// LuaPluginManager lua pluginManager struct
type LuaPluginManager struct {
	RunningInput      []*luaplugin.LuaInput
	RunningProcessor  []*luaplugin.LuaProcessor
	RunningAggregator []*luaplugin.LuaAggregator
	RunningOutput     []*luaplugin.LuaOutput

	UpdateInput      []*luaplugin.LuaInput
	UpdateProcessor  []*luaplugin.LuaProcessor
	UpdateAggregator []*luaplugin.LuaAggregator
	UpdateOutput     []*luaplugin.LuaOutput

	Lock               sync.Mutex
	PluginReady        chan int   // 0: 更换运行插件; 1: 删除运行插件
	PluginUpdateFinish chan bool
	//receiver       chan []luaplugin.LuaPlugin
}

var (
	//dataBox       *storage.DataBox
	pool          *engine.LStatePool
)

// InitEnv inti lua plugin env
func (lm *LuaPluginManager) InitEnv(total int) error {
	pool = engine.InitLStatePool(total)
	//dataBox = storage.NewDataBox(ctx, period, cacheExpiration, dbExpiration)
	err := luaplugin.InitLuaPlugin()
	if err != nil {
		log.Errorf("Init lua plugin error: %v", err)
	}
	return err
}


// Load load lua plugin
func (lm *LuaPluginManager) Load(conf config.PluginConfig, isUpdate bool) error {
	instance, err := luaplugin.CreateLuaPlugin(pool, &conf)
	if err != nil {
		return err
	}

	switch conf.Category {
	case "input":
		if !isUpdate {
			lm.RunningInput = append(lm.RunningInput, instance.(*luaplugin.LuaInput))
		} else {
			lm.UpdateInput = append(lm.UpdateInput, instance.(*luaplugin.LuaInput))
		}
	case "processor":
		if !isUpdate {
			lm.RunningProcessor = append(lm.RunningProcessor, instance.(*luaplugin.LuaProcessor))
		} else {
			lm.UpdateProcessor = append(lm.UpdateProcessor, instance.(*luaplugin.LuaProcessor))
		}
	case "aggregator":
		if !isUpdate {
			lm.RunningAggregator = append(lm.RunningAggregator, instance.(*luaplugin.LuaAggregator))
		} else {
			lm.UpdateAggregator = append(lm.UpdateAggregator, instance.(*luaplugin.LuaAggregator))
		}
	case "output":
		if !isUpdate {
			lm.RunningOutput = append(lm.RunningOutput, instance.(*luaplugin.LuaOutput))
		} else {
			lm.UpdateOutput = append(lm.UpdateOutput, instance.(*luaplugin.LuaOutput))
		}
	default:
		log.Errorf("Can not match plugin category %v", conf.Category)
		return fmt.Errorf("can not match plugin category %v", conf.Category)
	}

	return nil
}

// LoadPlugins load plugins
func (lm *LuaPluginManager) LoadPlugins(pluginConfig *config.PluginConfigSet) error {
	var err error
	for _, conf := range pluginConfig.Inputs {
		err = lm.Load(*conf, false)
		if err != nil {
			log.Errorf("Load %v %v %v %v failed, plugin hash %v",
				conf.Pattern, conf.Category, conf.Name, conf.Version, conf.CurHash)
			return err
		}
	}

	for _, conf := range pluginConfig.Processors {
		err = lm.Load(*conf, false)
		if err != nil {
			log.Errorf("Load %v %v %v %v failed, plugin hash %v",
				conf.Pattern, conf.Category, conf.Name, conf.Version, conf.CurHash)
			return err
		}
	}

	for _, conf := range pluginConfig.Aggregators {
		err = lm.Load(*conf, false)
		if err != nil {
			log.Errorf("Load %v %v %v %v failed, plugin hash %v",
				conf.Pattern, conf.Category, conf.Name, conf.Version, conf.CurHash)
			return err
		}
	}

	for _, conf := range pluginConfig.Outputs {
		err = lm.Load(*conf, false)
		if err != nil {
			log.Errorf("Load %v %v %v %v failed, plugin hash %v",
				conf.Pattern, conf.Category, conf.Name, conf.Version, conf.CurHash)
			return err
		}
	}

	return nil
}

// RemovePlugins remove plugins array
func (lm *LuaPluginManager) RemovePlugins() {
	for index := range lm.RunningInput {
		lm.RunningInput[index].Close()
	}
	for index := range lm.RunningProcessor {
		lm.RunningProcessor[index].Close()
	}
	for index := range lm.RunningAggregator {
		lm.RunningAggregator[index].Close()
	}
	for index := range lm.RunningOutput {
		lm.RunningOutput[index].Close()
	}

	for index := range lm.UpdateInput {
		lm.UpdateInput[index].Close()
	}
	for index := range lm.UpdateProcessor {
		lm.UpdateProcessor[index].Close()
	}
	for index := range lm.UpdateAggregator {
		lm.UpdateAggregator[index].Close()
	}
	for index := range lm.UpdateOutput {
		lm.UpdateOutput[index].Close()
	}

	close(lm.PluginReady)
}

//func (lm *LuaPluginManager) GetVersion(category string, name string) (string, string) {
//	return "0", ""
//}

func (lm *LuaPluginManager) notify(signal int) {
	log.Debugf("Send plugin manager ready signal")
	lm.PluginReady <- signal
	if _, ok := <- lm.PluginUpdateFinish; ok {
		log.Debugf("Receive plugin update/delete finish signal")
	} else {
		log.Warningf("Plugin update/delete finish channel close")
	}
}

// Receive receive agent signal to update/delete plugins or config
func (lm *LuaPluginManager) Receive(
	ctx context.Context,
	wg *sync.WaitGroup,
	pluginConfig *config.Config) {
	defer wg.Done()

	Loop:
		for {
			select {
			case hashMap, ok := <- services.PluginUpdateChan:
				if ok {
					log.Debugf("Receive agent plugin update signal")
					lm.update(pluginConfig, hashMap)
				} else {
					log.Warningf("Plugin update channel close")
				}
			case hashList, ok := <- services.PluginDeleteChan:
				if ok {
					log.Debugf("Receive agent plugin delete signal")
					lm.remove(pluginConfig, hashList)
				} else {
					log.Warningf("Plugin update channel close")
				}
			case <-ctx.Done():
				break Loop
			}
		}
}

func (lm *LuaPluginManager) update(pluginConfig *config.Config, hashMap map[string]string) {
	configCache := pluginConfig.ParsePluginMarking(&pluginConfig.Update, hashMap)
	if len(configCache) <= 0 {
		return
	}
	pluginConfig.StoragePlugin(configCache)
	pluginConfig.ParsePluginConfig(pluginConfig.ConfigObj.Obj, &pluginConfig.Update)

	log.Debugf("Update plugin config number: %v, %v, %v, %v",
		len(pluginConfig.Update.Inputs), len(pluginConfig.Update.Processors),
		len(pluginConfig.Update.Aggregators), len(pluginConfig.Update.Outputs))
	//for _, one := range pluginConfig.UpdateInputs {
	//	log.Debugf("Update Input plugin config: %+v", one)
	//}
	//for _, one := range pluginConfig.UpdateProcessors {
	//	log.Debugf("Update Processor plugin config: %+v", one)
	//}
	//for _, one := range pluginConfig.UpdateAggregators {
	//	log.Debugf("Update Aggregator plugin config: %+v", one)
	//}
	//for _, one := range pluginConfig.UpdateOutputs {
	//	log.Debugf("Update Output plugin config: %+v", one)
	//}

	err := lm.updatePlugins(&pluginConfig.Update)
	if err != nil {
		log.Errorf("Update plugin error: %v", err)
		lm.removeUpdateCache()
		return
	}
	lm.notify(0)
}

func (lm *LuaPluginManager) remove(pluginConfig *config.Config, hashList []string) {
	cache := pluginConfig.CheckoutConfig(hashList)
	pluginConfig.DeletePlugin(cache)

	log.Debugf("Delete plugin config number: %v, %v, %v, %v",
		len(pluginConfig.Delete.Inputs), len(pluginConfig.Delete.Processors),
		len(pluginConfig.Delete.Aggregators), len(pluginConfig.Delete.Outputs))
	//for _, one := range pluginConfig.Delete.Inputs {
	//	log.Debugf("Delete Input plugin config: %+v", one)
	//}
	//for _, one := range pluginConfig.Delete.Processors {
	//	log.Debugf("Delete Processor plugin config: %+v", one)
	//}
	//for _, one := range pluginConfig.Delete.Aggregators {
	//	log.Debugf("Delete Aggregator plugin config: %+v", one)
	//}
	//for _, one := range pluginConfig.Delete.Outputs {
	//	log.Debugf("Delete Output plugin config: %+v", one)
	//}

	lm.notify(1)
	//conf := pluginConfig.UpdateInputs[0]
	//switch conf.Category {
	//case "input":
	//	delIndex := 0
	//	for index := range lm.RunningInput {
	//		if lm.RunningInput[index].CurHash == conf.CurHash {
	//			delIndex = index
	//			break
	//		}
	//	}
	//	lm.RunningInput[delIndex].Close()
	//	lm.RunningInput = append(lm.RunningInput[:delIndex], lm.RunningInput[delIndex+1:]...)
	//case "processor":
	//	delIndex := 0
	//	for index := range lm.RunningProcessor {
	//		if lm.RunningProcessor[index].CurHash == conf.CurHash {
	//			delIndex = index
	//			break
	//		}
	//	}
	//	lm.RunningProcessor[delIndex].Close()
	//	lm.RunningProcessor = append(lm.RunningProcessor[:delIndex], lm.RunningProcessor[delIndex+1:]...)
	//case "aggregator":
	//	delIndex := 0
	//	for index := range lm.RunningAggregator {
	//		if lm.RunningAggregator[index].CurHash == conf.CurHash {
	//			delIndex = index
	//			break
	//		}
	//	}
	//	lm.RunningAggregator[delIndex].Close()
	//	lm.RunningAggregator = append(lm.RunningAggregator[:delIndex], lm.RunningAggregator[delIndex+1:]...)
	//case "output":
	//	delIndex := 0
	//	for index := range lm.RunningOutput {
	//		if lm.RunningOutput[index].CurHash == conf.CurHash {
	//			delIndex = index
	//			break
	//		}
	//	}
	//	lm.RunningOutput[delIndex].Close()
	//	lm.RunningOutput = append(lm.RunningOutput[:delIndex], lm.RunningOutput[delIndex+1:]...)
	//default:
	//	log.Errorf("Can not match plugin category %v", conf.Category)
	//}
}

func (lm *LuaPluginManager) updatePlugins(pluginConfig *config.PluginConfigSet) error {
	var err error
	for _, conf := range pluginConfig.Inputs {
		err = lm.Load(*conf, true)
		if err != nil {
			log.Errorf("Update %v %v %v %v failed, plugin hash %v",
				conf.Pattern, conf.Category, conf.Name, conf.Version, conf.CurHash)
			return err
		}
	}

	for _, conf := range pluginConfig.Processors {
		err = lm.Load(*conf, true)
		if err != nil {
			log.Errorf("Update %v %v %v %v failed, plugin hash %v",
				conf.Pattern, conf.Category, conf.Name, conf.Version, conf.CurHash)
			return err
		}
	}

	for _, conf := range pluginConfig.Aggregators {
		err = lm.Load(*conf, true)
		if err != nil {
			log.Errorf("Update %v %v %v %v failed, plugin hash %v",
				conf.Pattern, conf.Category, conf.Name, conf.Version, conf.CurHash)
			return err
		}
	}

	for _, conf := range pluginConfig.Outputs {
		err = lm.Load(*conf, true)
		if err != nil {
			log.Errorf("Update %v %v %v %v failed, plugin hash %v",
				conf.Pattern, conf.Category, conf.Name, conf.Version, conf.CurHash)
			return err
		}
	}
	log.Debugf("Update plugin instance number: %v, %v, %v, %v",
		len(pluginConfig.Inputs), len(pluginConfig.Processors),
		len(pluginConfig.Aggregators), len(pluginConfig.Outputs))
	return nil
}

// ReplaceRunningPlugin replace running plugins
func (lm *LuaPluginManager) ReplaceRunningPlugin() {
	lm.Lock.Lock()
	log.Debugf("Get lock, for replace running plugins")
	defer lm.Lock.Unlock()

	replaceIndex := make([]int, 0)
	for indexUpdate := range lm.UpdateInput {
		for indexRunning := range lm.RunningInput {
			if lm.RunningInput[indexRunning].Category == lm.UpdateInput[indexUpdate].Category &&
				lm.RunningInput[indexRunning].Name == lm.UpdateInput[indexUpdate].Name {
				replaceIndex = append(replaceIndex, indexRunning)
			}
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(replaceIndex)))
	for _, delIndex := range replaceIndex {
		lm.RunningInput[delIndex].ClosePlugin()
		lm.RunningInput = append(lm.RunningInput[:delIndex], lm.RunningInput[delIndex+1:]...)
	}
	for addIndex := range lm.UpdateInput {
		lm.RunningInput = append(lm.RunningInput, lm.UpdateInput[addIndex])
	}
	lm.UpdateInput = make([]*luaplugin.LuaInput, 0)


	replaceIndex = make([]int, 0)
	for indexUpdate := range lm.UpdateProcessor {
		for indexRunning := range lm.RunningProcessor {
			if lm.RunningProcessor[indexRunning].Category == lm.UpdateProcessor[indexUpdate].Category &&
				lm.RunningProcessor[indexRunning].Name == lm.UpdateProcessor[indexUpdate].Name {
				replaceIndex = append(replaceIndex, indexRunning)
			}
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(replaceIndex)))
	for _, delIndex := range replaceIndex {
		lm.RunningProcessor[delIndex].ClosePlugin()
		lm.RunningProcessor = append(lm.RunningProcessor[:delIndex], lm.RunningProcessor[delIndex+1:]...)
	}
	for addIndex := range lm.UpdateProcessor {
		lm.RunningProcessor = append(lm.RunningProcessor, lm.UpdateProcessor[addIndex])
	}
	lm.UpdateProcessor = make([]*luaplugin.LuaProcessor, 0)


	replaceIndex = make([]int, 0)
	for indexUpdate := range lm.UpdateAggregator {
		for indexRunning := range lm.RunningAggregator {
			if lm.RunningAggregator[indexRunning].Category == lm.UpdateAggregator[indexUpdate].Category &&
				lm.RunningAggregator[indexRunning].Name == lm.UpdateAggregator[indexUpdate].Name {
				replaceIndex = append(replaceIndex, indexRunning)
			}
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(replaceIndex)))
	for _, delIndex := range replaceIndex {
		lm.RunningAggregator[delIndex].ClosePlugin()
		lm.RunningAggregator = append(lm.RunningAggregator[:delIndex], lm.RunningAggregator[delIndex+1:]...)
	}
	for addIndex := range lm.UpdateAggregator {
		lm.RunningAggregator = append(lm.RunningAggregator, lm.UpdateAggregator[addIndex])
	}
	lm.UpdateAggregator = make([]*luaplugin.LuaAggregator, 0)


	replaceIndex = make([]int, 0)
	for indexUpdate := range lm.UpdateOutput {
		for indexRunning := range lm.RunningOutput {
			if lm.RunningOutput[indexRunning].Category == lm.UpdateOutput[indexUpdate].Category &&
				lm.RunningOutput[indexRunning].Name == lm.UpdateOutput[indexUpdate].Name {
				replaceIndex = append(replaceIndex, indexRunning)
			}
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(replaceIndex)))
	for _, delIndex := range replaceIndex {
		lm.RunningOutput[delIndex].ClosePlugin()
		lm.RunningOutput = append(lm.RunningOutput[:delIndex], lm.RunningOutput[delIndex+1:]...)
	}
	for addIndex := range lm.UpdateOutput {
		lm.RunningOutput = append(lm.RunningOutput, lm.UpdateOutput[addIndex])
	}
	lm.UpdateOutput = make([]*luaplugin.LuaOutput, 0)

	log.Debugf("Replace completely, running plugin len: %v, %v, %v, %v",
		len(lm.RunningInput), len(lm.RunningProcessor),
		len(lm.RunningAggregator), len(lm.RunningOutput))
	log.Debugf("Clean update cache, update plugin len: %v, %v, %v, %v",
		len(lm.UpdateInput), len(lm.UpdateProcessor),
		len(lm.UpdateAggregator), len(lm.UpdateOutput))
}

func (lm *LuaPluginManager) removeUpdateCache() {
	for index := range lm.UpdateInput {
		lm.UpdateInput[index].Close()
	}
	for index := range lm.UpdateProcessor {
		lm.UpdateProcessor[index].Close()
	}
	for index := range lm.UpdateAggregator {
		lm.UpdateAggregator[index].Close()
	}
	for index := range lm.UpdateOutput {
		lm.UpdateOutput[index].Close()
	}
	lm.UpdateInput = make([]*luaplugin.LuaInput, 0)
	lm.UpdateProcessor = make([]*luaplugin.LuaProcessor, 0)
	lm.UpdateAggregator = make([]*luaplugin.LuaAggregator, 0)
	lm.UpdateOutput = make([]*luaplugin.LuaOutput, 0)
	log.Debugf("Remove update cache, update plugin len: %v, %v, %v, %v",
		len(lm.RunningInput), len(lm.RunningProcessor),
		len(lm.RunningAggregator), len(lm.RunningOutput))
}

// RemoveRunningPlugin remove running plugins
func (lm *LuaPluginManager) RemoveRunningPlugin(config *config.PluginConfigSet) {
	lm.Lock.Lock()
	log.Debugf("Get lock, for remove running plugins")
	defer lm.Lock.Unlock()

	removeIndex := make([]int, 0)
	for indexConfig := range config.Inputs {
		for indexRunning := range lm.RunningInput {
			if lm.RunningInput[indexRunning].CurHash == config.Inputs[indexConfig].CurHash {
				removeIndex = append(removeIndex, indexRunning)
			}
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(removeIndex)))
	for _, delIndex := range removeIndex {
		lm.RunningInput[delIndex].ClosePlugin()
		lm.RunningInput = append(lm.RunningInput[:delIndex], lm.RunningInput[delIndex+1:]...)
	}


	removeIndex = make([]int, 0)
	for indexConfig := range config.Processors {
		for indexRunning := range lm.RunningProcessor {
			if lm.RunningProcessor[indexRunning].CurHash == config.Processors[indexConfig].CurHash {
				removeIndex = append(removeIndex, indexRunning)
			}
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(removeIndex)))
	for _, delIndex := range removeIndex {
		lm.RunningProcessor[delIndex].ClosePlugin()
		lm.RunningProcessor = append(lm.RunningProcessor[:delIndex], lm.RunningProcessor[delIndex+1:]...)
	}


	removeIndex = make([]int, 0)
	for indexConfig := range config.Aggregators {
		for indexRunning := range lm.RunningAggregator {
			if lm.RunningAggregator[indexRunning].CurHash == config.Aggregators[indexConfig].CurHash {
				removeIndex = append(removeIndex, indexRunning)
			}
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(removeIndex)))
	for _, delIndex := range removeIndex {
		lm.RunningAggregator[delIndex].ClosePlugin()
		lm.RunningAggregator = append(lm.RunningAggregator[:delIndex], lm.RunningAggregator[delIndex+1:]...)
	}


	removeIndex = make([]int, 0)
	for indexConfig := range config.Outputs {
		for indexRunning := range lm.RunningOutput {
			if lm.RunningOutput[indexRunning].CurHash == config.Outputs[indexConfig].CurHash {
				removeIndex = append(removeIndex, indexRunning)
			}
		}
	}
	sort.Sort(sort.Reverse(sort.IntSlice(removeIndex)))
	for _, delIndex := range removeIndex {
		lm.RunningOutput[delIndex].ClosePlugin()
		lm.RunningOutput = append(lm.RunningOutput[:delIndex], lm.RunningOutput[delIndex+1:]...)
	}

	log.Debugf("Delete running plugin, running plugin len: %v, %v, %v, %v",
		len(lm.RunningInput), len(lm.RunningProcessor),
		len(lm.RunningAggregator), len(lm.RunningOutput))
}

// NewLuaPluginManager new lua plugin manager
func NewLuaPluginManager() *LuaPluginManager {
	return &LuaPluginManager{
		PluginReady: make(chan int, 1),
		PluginUpdateFinish: make(chan bool, 1),
	}
}
