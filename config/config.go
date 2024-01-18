package config

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"strings"
	"sync"

	"github.com/PPIO/pi-collect/agent/services"
	"github.com/PPIO/pi-collect/pkg/util"

	"github.com/bitly/go-simplejson"
	log "github.com/sirupsen/logrus"
)

//type Monitor interface {
//	monitor(src string) bool             // 监听配置更新: true 更新，false: 不更新
//	update(src string, dst string) error // 更新配置
//	notify(m chan bool)                  // 通知配置有更新
//}

//type Update interface {
//	Receive(m chan bool)            // 接收配置变更信号
//	Parse(src string) error         // 解析新配置
//	Notify(m chan []Plugin)  // 通知新配置已解析,需要重新加载配置
//}

type LogConfig struct {
	LogLevel        int
	LogPath         string
	LogName         string
	LogMaxAge       int64
	LogRotationTime int64
}

type Plugin struct {
	Pattern  string // lua
	Category string // input, processor, aggregator, output
	Name     string // cpu, memory, task
	Version  string
	CurHash  string
	Path     string
}

type GlobalConfig struct {
	Interval        int64    `json:"interval"`
	CheckPeriod     int64    `json:"check_period"`
	CacheExpiration int64    `json:"cache_expiration"`
	CenterAddr      string   `json:"center_addr"`
	PluginRootPath  string   `json:"plugin_root_path"`
	PluginCategory  []string `json:"plugin_category"`
	PluginMarking   string   `json:"plugin_marking"`
}

type DockerConfig struct {
	EventsUpdate  int64 `json:"events_update"`
	PollingPeriod int64 `json:"polling_period"`
}

type DBConfig struct {
	DBType       string `json:"type"`
	Path         string `json:"path"`
	Expiration   int64  `json:"expiration"`
	ReportBucket string `json:"report_bucket"`
}

type PluginConfig struct {
	Plugin
	//SrcAdd         string // 插件源地址
	SourceCode     string // 插件源码
	GlobalInterval int64
	PluginInterval int64
	Include        map[string][]string
	Exclude        map[string][]string
	//SpecialConfig  *simplejson.Json
}

type PluginConfigSet struct {
	Inputs      []*PluginConfig
	Processors  []*PluginConfig
	Aggregators []*PluginConfig
	Outputs     []*PluginConfig
}

type JsConfigObj struct {
	Obj  *simplejson.Json
	hash string
}

type Config struct {
	Global      GlobalConfig
	DockerConf  DockerConfig
	DBConf      DBConfig
	Running     PluginConfigSet
	RunningHash map[string]int

	UpdateGlobal GlobalConfig
	UpdateDBConf DBConfig
	Update       PluginConfigSet

	Delete PluginConfigSet

	ConfigObj    JsConfigObj
	Lock         sync.Mutex
	pluginSuffix map[string]interface{}
	//Send chan []Plugin
	//Receiver chan bool
}

func (c *Config) parseGlobalConfig(jsObj *simplejson.Json) {
	c.Global.Interval = jsObj.Get("interval").MustInt64()
	c.Global.CheckPeriod = jsObj.Get("check_period").MustInt64()
	c.Global.CacheExpiration = jsObj.Get("cache_expiration").MustInt64()
	c.Global.CenterAddr = jsObj.Get("center_addr").MustString()
	c.Global.PluginRootPath = jsObj.Get("plugin_root_path").MustString()
	c.Global.PluginCategory = jsObj.Get("plugin_category").MustStringArray()
	c.Global.PluginMarking = jsObj.Get("plugin_marking").MustString()
	log.Debugf("Parse global config: %+v", c.Global)
}

func (c *Config) parseDockerConfig(jsObj *simplejson.Json) {
	c.DockerConf.EventsUpdate = jsObj.Get("events_update").MustInt64()
	c.DockerConf.PollingPeriod = jsObj.Get("polling_period").MustInt64()
	log.Debugf("Parse docker config: %+v", c.DBConf)
}

func (c *Config) parseDBConfig(jsObj *simplejson.Json) {
	c.DBConf.Path = jsObj.Get("path").MustString()
	c.DBConf.DBType = jsObj.Get("type").MustString()
	c.DBConf.Expiration = jsObj.Get("expiration").MustInt64()
	c.DBConf.ReportBucket = jsObj.Get("report_bucket").MustString()
	log.Debugf("Parse database config: %+v", c.DBConf)
}

func (c *Config) parseOtherConfig(jsObj *simplejson.Json) {
	c.pluginSuffix = jsObj.Get("suffix").MustMap()
	log.Debugf("Parse suffix config: %+v", c.pluginSuffix)
}

func (c *Config) insertConfig(rawConfig []*PluginConfig, jsObj *simplejson.Json, category string) {
	log.Debugf("Read config file, insert %v config.", category)
	arrayLen := len(jsObj.Get(category).MustArray())
	for i := 0; i < arrayLen; i++ {
		for _, rc := range rawConfig {
			patter, err := jsObj.Get(category).GetIndex(i).Get("pattern").String()
			if err != nil {
				log.Errorf("Parse plugin config, can not get plugin pattern")
				continue
			}
			name, err := jsObj.Get(category).GetIndex(i).Get("name").String()
			if err != nil {
				log.Errorf("Parse plugin config, can not get plugin name")
				continue
			}
			if (*rc).Pattern == patter && (*rc).Name == name {
				(*rc).GlobalInterval = c.Global.Interval
				(*rc).PluginInterval = jsObj.Get(category).GetIndex(i).Get("interval").MustInt64()
				if (*rc).PluginInterval == 0 {
					(*rc).PluginInterval = rc.GlobalInterval
				}
				tmpByte, err := jsObj.Get(category).GetIndex(i).Get("include").MarshalJSON()
				if err != nil {
					log.Errorf("Parse plugin config, can not parse include, error:", err)
				}
				err = json.Unmarshal(tmpByte, &(*rc).Include)
				if err != nil {
					log.Errorf("Parse plugin config, can not parse include, error:", err)
				}
				tmpByte, err = jsObj.Get(category).GetIndex(i).Get("exclude").MarshalJSON()
				if err != nil {
					log.Errorf("Parse plugin config, can not parse exclude, error:", err)
				}
				err = json.Unmarshal(tmpByte, &(*rc).Exclude)
				if err != nil {
					log.Errorf("Parse plugin config, can not parse exclude, error:", err)
				}
				//(*rc).SpecialConfig = jsObj.Get(category).GetIndex(i).Get("special_config")
				log.Debugf("Insert plugin config: Pattern: %+v, Name: %+v",
					(*rc).Pattern, (*rc).Name)
				log.Debugf("Insert plugin config: GlobalInterval: %+v, PluginInterval: %+v",
					(*rc).GlobalInterval, (*rc).PluginInterval)
				log.Debugf("Insert plugin config: Include: %+v, Exclude: %+v",
					(*rc).Include, (*rc).Exclude)
			}
		}
	}
}

func (c *Config) readPluginFile() map[string]string {
	files := util.FetchFiles(c.Global.PluginRootPath)
	log.Debugf("plugin files: %v", files)
	pluginContent := make(map[string]string)
	if len(files) > 0 {
		for _, filePath := range files {
			file, err := os.Open(filePath)
			if err != nil {
				log.Debugf("Read plugin file error: %v", err)
				continue
			}

			content, err := ioutil.ReadAll(file)
			hash := util.GetMd5Hash(string(content))
			pluginContent[hash] = string(content)
			func() { _ = file.Close() }()
		}
	}
	log.Debugf("plugin hash and content map len: %v", len(pluginContent))
	return pluginContent
}

func (c *Config) storageConfig(buffer []byte) {
	storageRootPath := c.Global.PluginRootPath
	dir := path.Join(storageRootPath, "..", "config")
	if !util.IsExists(dir) {
		if err := os.MkdirAll(dir, 777); err != nil {
			log.Errorf("Can not create dir %v, error: %v", dir, err)
			return
		}
	}

	filePath := path.Join(dir, fmt.Sprintf("%s", "collect.json"))
	err := ioutil.WriteFile(filePath, buffer, 0644)
	if err != nil {
		log.Errorf("Storage config error %v", err)
	} else {
		log.Debugf("Storage config path: %v", filePath)
	}
}

func (c *Config) tryUpdateConfig(hashMap map[string]string) {
	for hash, src := range hashMap {
		buffer := []byte(src)
		tmpObj, err := simplejson.NewJson(buffer)
		if err != nil {
			continue
		}

		if c.ConfigObj.hash == hash {
			log.Warningln("Have file format is Json, but the same hash.")
			continue
		}

		c.RunningHash[hash] = 1
		log.Infoln("Have file format is Json, try to update config.")
		c.storageConfig(buffer)
		c.ConfigObj = JsConfigObj{Obj: tmpObj, hash: hash}
		//c.parseGlobalConfig(c.ConfigObj.Obj.Get("global"))
		//c.parseOtherConfig(c.ConfigObj.Obj)
	}
}

func (c *Config) delHash(hash string) {
	if _, ok := c.RunningHash[hash]; ok {
		delete(c.RunningHash, hash)
		log.Debugf("Ready to unload plugin, hash: %v", hash)
	}
}

func (c *Config) compareHash(hash string) bool {
	if _, ok := c.RunningHash[hash]; !ok {
		c.RunningHash[hash] = 1
		log.Debugf("Can not find the same plugin, load plugin, hash %v", hash)
		return true
	} else {
		log.Warningf("Plugin is running, ignore update, hash %v", hash)
		return false
	}
}

func (c *Config) ParsePluginMarking(
	conf *PluginConfigSet,
	hashMap map[string]string) []PluginConfig {
	cache := make([]PluginConfig, 0, len(hashMap))
	// Check file format, try to update config preferentially
	c.tryUpdateConfig(hashMap)
	for hash, pluginStr := range hashMap {
		if !c.compareHash(hash) {
			continue
		}

		lines := strings.Split(pluginStr, "\n")
		for _, content := range lines {
			if strings.Contains(content, c.Global.PluginMarking) {
				contentSplit := strings.Split(content, fmt.Sprintf("%s:", c.Global.PluginMarking))
				if len(contentSplit) < 2 {
					log.Errorf("Plugin marking cannot be split, marking: %v", content)
					continue
				}
				markingStr := strings.TrimSpace(contentSplit[1])
				marking := strings.Split(markingStr, ",")
				if len(marking) < 4 {
					log.Errorf("Plugin marking cannot be split, marking: %v", content)
					continue
				}
				tmp := NewPluginConfig(marking[0], marking[1], marking[2], marking[3], hash, "", pluginStr)
				cache = append(cache, tmp)
				if marking[0] == "lua" {
					switch marking[1] {
					case "input":
						conf.Inputs = append(conf.Inputs, &tmp)
					case "processor":
						conf.Processors = append(conf.Processors, &tmp)
					case "aggregator":
						conf.Aggregators = append(conf.Aggregators, &tmp)
					case "output":
						conf.Outputs = append(conf.Outputs, &tmp)
					}
				}
				break
			}
		}
	}

	log.Debugf("Parse plugin marking, update config:%v, %v, %v, %v",
		len(conf.Inputs), len(conf.Processors), len(conf.Aggregators), len(conf.Outputs))
	//for _, one := range c.Inputs {
	//	log.Debugf("Input plugin config: %+v", one)
	//}
	//for _, one := range c.Processors {
	//	log.Debugf("Processor plugin config: %+v", one)
	//}
	//for _, one := range c.Aggregators {
	//	log.Debugf("Aggregator plugin config: %+v", one)
	//}
	//for _, one := range c.Outputs {
	//	log.Debugf("Output plugin config: %+v", one)
	//}
	return cache
}

func (c *Config) ParsePluginConfig(jsObj *simplejson.Json, configSet *PluginConfigSet) {
	c.Lock.Lock()
	log.Debugf("Get lock, for parse plugin config")
	defer c.Lock.Unlock()

	log.Debugf("Config json object %v", jsObj)
	for _, category := range c.Global.PluginCategory {
		switch category {
		case "input":
			c.insertConfig(configSet.Inputs, jsObj, category)
		case "processor":
			c.insertConfig(configSet.Processors, jsObj, category)
		case "aggregator":
			c.insertConfig(configSet.Aggregators, jsObj, category)
		case "output":
			c.insertConfig(configSet.Outputs, jsObj, "output")
		default:
			log.Errorf("Error plugin category %v", category)
		}
	}
}

func (c *Config) Parse(src string) error {
	buffer := []byte(src)
	tmpObj, err := simplejson.NewJson(buffer)
	if err != nil {
		return err
	}
	configHash := util.GetMd5Hash(src)
	c.ConfigObj = JsConfigObj{Obj: tmpObj, hash: configHash}
	c.RunningHash[configHash] = 1
	c.parseGlobalConfig(c.ConfigObj.Obj.Get("global"))
	c.parseDockerConfig(c.ConfigObj.Obj.Get("docker"))
	c.parseDBConfig(c.ConfigObj.Obj.Get("database"))
	c.parseOtherConfig(c.ConfigObj.Obj)
	pluginContent := c.readPluginFile()
	//for hash := range pluginContent {
	//	log.Debugf("Read local plugin: hash %+v", hash)
	//}
	configCache := c.ParsePluginMarking(&c.Running, pluginContent)
	c.StoragePlugin(configCache)
	c.ParsePluginConfig(c.ConfigObj.Obj, &c.Running)
	c.reportLocalPlugins(services.LocalPluginChan, pluginContent)

	return nil
}

func (c *Config) reportLocalPlugins(ch chan []string, content map[string]string) {
	hashArray := make([]string, 0, len(content))
	for key := range content {
		hashArray = append(hashArray, key)
	}

	select {
	case ch <- hashArray:
		log.Debugf("Report local plugins: %v", hashArray)
	default:
		log.Errorf("Can not report local plugins")
	}
}

// Len running plugin number
func (c *Config) Len() int {
	total := len(c.Running.Inputs) +
		len(c.Running.Processors) +
		len(c.Running.Aggregators) +
		len(c.Running.Outputs)
	return total
}

func (c *Config) ReplaceRunningConfig() {
	c.Lock.Lock()
	log.Debugf("Get lock, for replace running config")
	defer c.Lock.Unlock()

	c.parseGlobalConfig(c.ConfigObj.Obj.Get("global"))
	c.parseOtherConfig(c.ConfigObj.Obj)

	for index := range c.Update.Inputs {
		c.Running.Inputs = append(c.Running.Inputs, c.Update.Inputs[index])
	}
	for index := range c.Update.Processors {
		c.Running.Processors = append(c.Running.Processors, c.Update.Processors[index])
	}
	for index := range c.Update.Aggregators {
		c.Running.Aggregators = append(c.Running.Aggregators, c.Update.Aggregators[index])
	}
	for index := range c.Update.Outputs {
		c.Running.Outputs = append(c.Running.Outputs, c.Update.Outputs[index])
	}

	c.Update.Inputs = make([]*PluginConfig, 0)
	c.Update.Processors = make([]*PluginConfig, 0)
	c.Update.Aggregators = make([]*PluginConfig, 0)
	c.Update.Outputs = make([]*PluginConfig, 0)
}

func (c *Config) StoragePlugin(cache []PluginConfig) {
	storageRootPath := c.Global.PluginRootPath

	for _, unit := range cache {
		dir := path.Join(storageRootPath, unit.Category)
		if !util.IsExists(dir) {
			if err := os.MkdirAll(dir, 777); err != nil {
				log.Errorf("Can not create dir %v, error: %v", dir, err)
				continue
			}
		}
		suffix := "plugin"
		if _, ok := c.pluginSuffix[unit.Pattern]; ok {
			suffix = c.pluginSuffix[unit.Pattern].(string)
		}
		filePath := path.Join(dir, fmt.Sprintf("%s.%s", unit.Name, suffix))
		err := ioutil.WriteFile(filePath, []byte(unit.SourceCode), 0644)
		if err != nil {
			log.Errorf("Storage plugin error %v", err)
		} else {
			log.Debugf("Storage plugin path: %v", filePath)
		}
	}
}

func (c *Config) CheckoutConfig(hashList []string) []PluginConfig {
	cache := make([]PluginConfig, 0, len(hashList))
	for _, hash := range hashList {
		c.delHash(hash)

		for _, conf := range c.Running.Inputs {
			if conf.CurHash == hash {
				c.Delete.Inputs = append(c.Delete.Inputs, conf)
				cache = append(cache, *conf)
				continue
			}
		}
		for _, conf := range c.Running.Processors {
			if conf.CurHash == hash {
				c.Delete.Processors = append(c.Delete.Processors, conf)
				cache = append(cache, *conf)
				continue
			}
		}
		for _, conf := range c.Running.Aggregators {
			if conf.CurHash == hash {
				c.Delete.Aggregators = append(c.Delete.Aggregators, conf)
				cache = append(cache, *conf)
				continue
			}
		}
		for _, conf := range c.Running.Outputs {
			if conf.CurHash == hash {
				c.Delete.Outputs = append(c.Delete.Outputs, conf)
				cache = append(cache, *conf)
				continue
			}
		}
	}

	return cache
}

func (c *Config) DeletePlugin(cache []PluginConfig) {
	storageRootPath := c.Global.PluginRootPath

	for _, unit := range cache {
		dir := path.Join(storageRootPath, unit.Category)
		if !util.IsExists(dir) {
			log.Errorf("Plugin dir %v is not exists", dir)
			continue
		}

		suffix := "plugin"
		if _, ok := c.pluginSuffix[unit.Pattern]; ok {
			suffix = c.pluginSuffix[unit.Pattern].(string)
		}
		filePath := path.Join(dir, fmt.Sprintf("%s.%s", unit.Name, suffix))
		err := os.Remove(filePath)
		if err != nil {
			log.Errorf("Delete plugin error %v", err)
		} else {
			log.Debugf("Delete plugin: path: %v", filePath)
		}
	}
}

func (c *Config) RemoveDeleteConfig() {
	c.Delete.Inputs = make([]*PluginConfig, 0)
	c.Delete.Processors = make([]*PluginConfig, 0)
	c.Delete.Aggregators = make([]*PluginConfig, 0)
	c.Delete.Outputs = make([]*PluginConfig, 0)
	log.Debugln("Clean config cache")
}

func (c *Config) ConfigRawContent(section string) string {
	jsonByte, err := c.ConfigObj.Obj.Get(section).MarshalJSON()
	if err != nil {
		log.Errorf("Can not encode config json to string, error: %v", err)
		return ""
	}
	return string(jsonByte)
}

func NewPluginConfig(
	pattern,
	category,
	name,
	version,
	hash,
	path,
	sourceCode string) PluginConfig {
	return PluginConfig{
		Plugin: Plugin{
			Pattern:  pattern,
			Category: category,
			Name:     name,
			Version:  version,
			CurHash:  hash,
			Path:     path,
		},
		SourceCode: sourceCode,
	}
}

func NewConfig() Config {
	return Config{
		RunningHash: make(map[string]int),
	}
}

//func (c *Config) test() {
//	file, err := os.Open("/mnt/d/code/myself/build_test/project_lua/input.lua")
//	if err != nil {
//		panic(err)
//	}
//	inputContent, err := ioutil.ReadAll(file)
//	func() { _ = file.Close() }()
//
//	file, err = os.Open("/mnt/d/code/myself/build_test/project_lua/processor.lua")
//	if err != nil {
//		panic(err)
//	}
//	processorContent, err := ioutil.ReadAll(file)
//	func() { _ = file.Close() }()
//
//	file, err = os.Open("/mnt/d/code/myself/build_test/project_lua/aggregator.lua")
//	if err != nil {
//		panic(err)
//	}
//	aggregatorContent, err := ioutil.ReadAll(file)
//	func() { _ = file.Close() }()
//
//	file, err = os.Open("/mnt/d/code/myself/build_test/project_lua/output.lua")
//	if err != nil {
//		panic(err)
//	}
//	outputContent, err := ioutil.ReadAll(file)
//	func() { _ = file.Close() }()
//
//	tmpInput := PluginConfig{
//		Plugin:Plugin{
//			Pattern: "lua",
//			Category: "input", // input, processor, aggregator, output
//			Name: "memory", // cpu, memory, task
//			Version: "1",
//			CurHash: "xxxx",
//			Path: "",
//		},
//		SourceCode: string(inputContent),
//	}
//
//	tmpProcessor := PluginConfig{
//		Plugin:Plugin{
//			Pattern: "lua",
//			Category: "processor", // input, processor, aggregator, output
//			Name: "diff", // cpu, memory, task
//			Version: "1",
//			CurHash: "xxxx",
//			Path: "",
//		},
//		SourceCode: string(processorContent),
//	}
//
//	tmpAggregator := PluginConfig{
//		Plugin:Plugin{
//			Pattern: "lua",
//			Category: "aggregator", // input, processor, aggregator, output
//			Name: "converge",
//			Version: "1",
//			CurHash: "xxxx",
//			Path: "",
//		},
//		SourceCode: string(aggregatorContent),
//		Include: map[string][]string{"memory": {"input|memory|1|memory", "processor|diff|1|memory_diff"}},
//	}
//
//	tmpOutput := PluginConfig{
//		Plugin:Plugin{
//			Pattern: "lua",
//			Category: "output", // input, processor, aggregator, output
//			Name: "writeFile",
//			Version: "1",
//			CurHash: "xxxx",
//			Path: "",
//		},
//		SourceCode: string(outputContent),
//	}
//
//	c.Running.Inputs = append(c.Running.Inputs, &tmpInput)
//	c.Running.Processors = append(c.Running.Processors, &tmpProcessor)
//	c.Running.Aggregators = append(c.Running.Aggregators, &tmpAggregator)
//	c.Running.Outputs = append(c.Running.Outputs, &tmpOutput)
//}
