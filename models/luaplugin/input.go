package luaplugin

import (
	"context"
	"errors"
	"fmt"

	//"reflect"
	"time"

	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/logger"

	//"github.com/PPIO/pi-collect/models"
	"github.com/PPIO/pi-collect/pkg/converter"
	operator "github.com/PPIO/pi-collect/pkg/docker_operator"
	"github.com/PPIO/pi-collect/pkg/engine"
	"github.com/PPIO/pi-collect/pkg/util"
	"github.com/PPIO/pi-collect/storage"

	log "github.com/sirupsen/logrus"
	lua "github.com/yuin/gopher-lua"
	luar "layeh.com/gopher-luar"
)

type inputConfig struct {
	triggerInterval int64
}

type LuaInput struct {
	inputConfig  // input plugin config
	LuaPlugin    // input plugin instance
	executeCount int64
}

func (p *LuaInput) parseConfig(c *config.PluginConfig) error {
	if c.PluginInterval > 0 &&
		c.GlobalInterval > 0 &&
		c.PluginInterval > c.GlobalInterval {
		interval := c.PluginInterval / c.GlobalInterval
		if interval > 0 {
			p.triggerInterval = interval
		}
	}

	if p.triggerInterval < 1 {
		p.triggerInterval = 1
	}

	log.Debugf("Input plugin trigger interval %d", p.triggerInterval)
	log.Debugf("Input plugin name : %v, interval: %d, global interval %d", c.Plugin.Name, c.PluginInterval, c.GlobalInterval)
	return nil
}

func (p *LuaInput) Init() error {
	log.Debugf("Plugin detail: Pattern: %v, Category: %v, Name: %v, Version: %v, Hash: %v",
		p.Pattern, p.Category, p.Name, p.Version, p.CurHash)
	log.Debugf("Plugin config: %+v", p.inputConfig)
	p.executeCount = 0

	if err := p.curIns.DoString(p.luaString); err != nil {
		return fmt.Errorf("input plugin new error: %v", err)
	}

	//ctx, cancel := context.WithTimeout(context.Background(), time.Second*2)
	//defer cancel()

	pluginLogger := logger.PluginLoggerPool.Init(p.Pattern, p.Category, p.Name, p.curIns)
	//p.curIns.SetContext(ctx)
	p.curIns.SetGlobal("log", luar.New(p.curIns, pluginLogger))
	p.curIns.SetGlobal("NewError", luar.New(p.curIns, errors.New))
	p.curIns.SetGlobal("jsonMarshal", p.curIns.NewFunction(converter.JsonMarshal))
	p.curIns.SetGlobal("jsonUnMarshal", p.curIns.NewFunction(converter.JsonUnMarshal))
	p.curIns.SetGlobal("containersInfo", luar.New(p.curIns, operator.ContainersInfo))
	p.curIns.SetGlobal("containersStats", luar.New(p.curIns, operator.CollectDockerStats))
	p.curIns.SetGlobal("containersInspects", luar.New(p.curIns, operator.CollectDockerInspects))
	p.curIns.SetGlobal("bitLeftShift", luar.New(p.curIns, util.BitLeftShift))
	p.curIns.SetGlobal("bitRightShift", luar.New(p.curIns, util.BitRightShift))
	p.curIns.SetGlobal("bitAND", luar.New(p.curIns, util.BitAND))
	p.curIns.SetGlobal("bitOR", luar.New(p.curIns, util.BitOR))
	//p.GetDescription()
	//if ok := p.CheckDescription(*u); !ok {
	//	return fmt.Errorf("input plugin load error")
	//}
	return nil
}

func (p *LuaInput) Collect(
	timeout time.Duration,
	out *storage.DataBox,
	config *config.Config) error {
	p.executeCount++
	if p.executeCount < p.triggerInterval {
		return nil
	}
	p.executeCount = 0

	log.Debugf("collect plugin timeout : %d", timeout)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*timeout)

	go func(timeout time.Duration) {
		ticker := time.NewTicker(time.Second * timeout)
		select {
		case <-ticker.C:
			cancel()
		default:
		}

	}(timeout)

	p.curIns.SetContext(ctx)

	if err := p.curIns.CallByParam(lua.P{
		Fn:      p.curIns.GetGlobal("collect"),
		NRet:    1,
		Protect: true,
	},
		luar.New(p.curIns, out),
		luar.New(p.curIns, config),
	); err != nil {
		//p.Close()
		return fmt.Errorf("input plugin error: %v", err)
	}

	return nil
}

func NewInput(pool *engine.LStatePool, c *config.PluginConfig) (interface{}, error) {
	p := LuaInput{
		inputConfig: inputConfig{},
		LuaPlugin: LuaPlugin{
			pool:      pool,
			luaString: c.SourceCode,
			Plugin:    c.Plugin,
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
