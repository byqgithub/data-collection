package luaplugin

import (
	"errors"
	"fmt"
	"time"

	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/logger"
	"github.com/PPIO/pi-collect/pkg/converter"
	"github.com/PPIO/pi-collect/pkg/engine"
	"github.com/PPIO/pi-collect/report"
	"github.com/PPIO/pi-collect/storage"

	log "github.com/sirupsen/logrus"
	lua "github.com/yuin/gopher-lua"
	luar "layeh.com/gopher-luar"
)

type outputConfig struct {
	triggerInterval int64
}

type LuaOutput struct {
	outputConfig     // output plugin config
	LuaPlugin        // output plugin instance
	executeCount  int64
}

func (p *LuaOutput) parseConfig(c *config.PluginConfig) error {
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

func (p *LuaOutput) Init() error {
	log.Debugf("Plugin detail: Pattern: %v, Category: %v, Name: %v, Version: %v, Hash: %v",
		p.Pattern, p.Category, p.Name, p.Version, p.CurHash)
	log.Debugf("Plugin config: %+v", p.outputConfig)
	p.executeCount = 0

	if err := p.curIns.DoString(p.luaString); err != nil {
		return fmt.Errorf("output plugin new error: %v", err)
	}

	pluginLogger := logger.PluginLoggerPool.Init(p.Pattern, p.Category, p.Name, p.curIns)
	p.curIns.SetGlobal("log", luar.New(p.curIns, pluginLogger))
	p.curIns.SetGlobal("NewError", luar.New(p.curIns, errors.New))
	p.curIns.SetGlobal("uploadData", luar.New(p.curIns, report.UploadData))
	p.curIns.SetGlobal("jsonMarshal", p.curIns.NewFunction(converter.JsonMarshal))
	p.curIns.SetGlobal("jsonUnMarshal", p.curIns.NewFunction(converter.JsonUnMarshal))
	p.curIns.SetGlobal("arrayUnMarshal", p.curIns.NewFunction(converter.ArrayUnMarshal))
	//p.GetDescription()
	//if ok := p.CheckDescription(*u); !ok {
	//	return fmt.Errorf("output plugin load error")
	//}
	return nil
}

func (p *LuaOutput) Write(
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
		Fn:      p.curIns.GetGlobal("write"),
		NRet:    1,
		Protect: true,
	},
		luar.New(p.curIns, start),
		luar.New(p.curIns, end),
		luar.New(p.curIns, dataBox),
	); err != nil {
		//p.Close()
		return fmt.Errorf("output plugin error: %v", err)
	}

	return nil
}

func NewOutput(pool *engine.LStatePool, c *config.PluginConfig) (interface{}, error) {
	p := LuaOutput{
		outputConfig: outputConfig{},
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
