package luaplugin

import (
	"errors"
	"fmt"
	"time"

	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/logger"
	"github.com/PPIO/pi-collect/pkg/converter"
	"github.com/PPIO/pi-collect/pkg/engine"
	"github.com/PPIO/pi-collect/storage"

	log "github.com/sirupsen/logrus"
	lua "github.com/yuin/gopher-lua"
	luar "layeh.com/gopher-luar"
)

type aggregatorConfig struct {
	triggerInterval int64
	include map[string][]string
}

type LuaAggregator struct {
	aggregatorConfig // aggregator plugin config
	LuaPlugin        // aggregator plugin instance
	executeCount  int64
}

func (p *LuaAggregator) parseConfig(c *config.PluginConfig) error {
	if c.PluginInterval > 0 &&
		c.GlobalInterval > 0 &&
		c.PluginInterval > c.GlobalInterval {
		interval := c.PluginInterval / c.GlobalInterval
		if interval > 0 { p.triggerInterval = interval }
	}

	if p.triggerInterval < 1 {
		p.triggerInterval = 1
	}
	return nil
}

func (p *LuaAggregator) Init() error {
	log.Debugf("Plugin detail: Pattern: %v, Category: %v, Name: %v, Version: %v, Hash: %v",
		p.Pattern, p.Category, p.Name, p.Version, p.CurHash)
	log.Debugf("Plugin config: %+v", p.aggregatorConfig)
	p.executeCount = 0

	if err := p.curIns.DoString(p.luaString); err != nil {
		return fmt.Errorf("aggregator plugin new error: %v", err)
	}

	pluginLogger := logger.PluginLoggerPool.Init(p.Pattern, p.Category, p.Name, p.curIns)
	p.curIns.SetGlobal("log", luar.New(p.curIns, pluginLogger))
	p.curIns.SetGlobal("NewError", luar.New(p.curIns, errors.New))
	p.curIns.SetGlobal("jsonMarshal", p.curIns.NewFunction(converter.JsonMarshal))
	p.curIns.SetGlobal("jsonUnMarshal", p.curIns.NewFunction(converter.JsonUnMarshal))
	p.curIns.SetGlobal("arrayUnMarshal", p.curIns.NewFunction(converter.ArrayUnMarshal))
	//p.GetDescription()
	//if ok := p.CheckDescription(*u); !ok {
	//	return fmt.Errorf("aggregator plugin load error")
	//}
	return nil
}

//func (p *LuaAggregator) extract(
//	timeRange []time.Duration,
//	dataBox *storage.DataBox,
//	item string) (map[string]interface{}, error) {
//	splitString := parseItem(item)
//	var start, end time.Duration
//	if len(timeRange) >= 2 {
//		start = timeRange[0]
//		end = timeRange[1]
//	} else {
//		return nil, fmt.Errorf("plugin param time range error: length < 2")
//	}
//
//	if err := p.curIns.CallByParam(lua.P{
//		Fn:      p.curIns.GetGlobal("extract"),
//		NRet:    1,
//		Protect: true,
//	},
//		luar.New(p.curIns, start),
//		luar.New(p.curIns, end),
//		luar.New(p.curIns, dataBox),
//		luar.New(p.curIns, splitString[0]),
//		luar.New(p.curIns, splitString[1]),
//		luar.New(p.curIns, splitString[2]),
//		luar.New(p.curIns, splitString[3]),
//		//luar.New(p.curIns, now),
//	); err != nil {
//		//p.Close()
//		return nil, fmt.Errorf("aggregator plugin error: %v", err)
//	}
//	result := p.curIns.CheckAny(-1) // fetch result
//	p.curIns.Pop(1)                 // clear result
//
//	if result == lua.LNil {
//		return nil, fmt.Errorf("converge data is NULL")
//	} else {
//		if v, ok := result.(*lua.LTable); ok {
//			cache := make(map[string]interface{})
//			v.ForEach(func(key lua.LValue, value lua.LValue) {
//				cache[key.String()] = value
//			})
//			return cache, nil
//		} else {
//			return nil, fmt.Errorf("converge data type is not lua userdata")
//		}
//	}
//}

func (p *LuaAggregator) Converge(
	timeout time.Duration,
	timeRange []time.Duration,
	dataBox *storage.DataBox) error {
	p.executeCount ++
	if p.executeCount < p.triggerInterval {
		return nil
	}
	p.executeCount = 0

	var start, end time.Duration
	if len(timeRange) >= 2 {
		start = timeRange[0]
		end = timeRange[1]
	} else {
		return fmt.Errorf("plugin param time range error: length < 2")
	}

	if err := p.curIns.CallByParam(lua.P{
		Fn:      p.curIns.GetGlobal("converge"),
		NRet:    1,
		Protect: true,
	},
		luar.New(p.curIns, start),
		luar.New(p.curIns, end),
		luar.New(p.curIns, dataBox),
	); err != nil {
		//p.Close()
		return fmt.Errorf("aggregator plugin error: %v", err)
	}
	//aggregatedData := make(map[string][]map[string]interface{})
	//for name, itemList := range p.include {
	//	for _, item := range itemList {
	//		cache, err := p.extract(timeRange, dataBox, item)
	//		if err != nil {
	//			log.Errorf("Aggregator Converge extract error %v", err)
	//		} else {
	//			log.Debugf("Aggregator Converge extract %v", cache)
	//		}
	//		aggregatedData[name] = append(aggregatedData[name], cache)
	//	}
	//}
	//log.Debugf("Aggregator all data %+v", aggregatedData)
	//reportData := storage.HTTPReport{}
	//reportData.Tags = map[string]string{"machine_id": "123455"}
	//reportData.Fields = aggregatedData
	//byteArray, err := json.Marshal(reportData)
	//if err != nil {
	//	log.Errorf("Report data convert to json, error %v", err)
	//	return err
	//}
	//log.Debugf("Report data json %+v", string(byteArray))
	//err = dataBox.AddField(p.Category, p.Name, p.Version,
	//	"writeFile", "", string(byteArray),
	//	time.Duration(time.Now().Unix()))
	//if err != nil {
	//	log.Errorf("Aggregator data storage error: %v", err)
	//}
	return nil
}

func NewAggregator(pool *engine.LStatePool, c *config.PluginConfig) (interface{}, error) {
	p := LuaAggregator{
		aggregatorConfig: aggregatorConfig{},
		LuaPlugin: LuaPlugin{
			pool: pool,
			luaString: c.SourceCode,
			Plugin: c.Plugin,
		},
		executeCount: 0,
	}
	p.curIns = p.pool.Get()
	err := p.parseConfig(c)
	if err != nil {
		return nil, err
	}

	err = p.Init()
	if err != nil {
		return nil, err
	}

	return &p, nil
}

//func parseItem(item string) []string {
//	return strings.Split(item, "|")
//}
