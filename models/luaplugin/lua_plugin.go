package luaplugin

import (
	"fmt"

	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/models"
	"github.com/PPIO/pi-collect/pkg/engine"
	log "github.com/sirupsen/logrus"
	lua "github.com/yuin/gopher-lua"
)

type PluginFactory func(*engine.LStatePool, *config.PluginConfig) (interface{}, error)

type LuaPlugin struct {
	config.Plugin
	pool      *engine.LStatePool
	curIns    *lua.LState
	luaString string
}

var pluginFactories = make(map[string]PluginFactory)

// GetDescription get lua plugin description
func (p *LuaPlugin) GetDescription() models.Description {
	if err := p.curIns.CallByParam(lua.P{
		Fn:      p.curIns.GetGlobal("description"),
		NRet:    1,
		Protect: true,
	},
	); err != nil {
		p.curIns.Close()
		return models.Description{}
	}
	result := p.curIns.CheckAny(-1) // fetch result
	p.curIns.Pop(1)                 // clear result

	// convert LUserData to description
	if result == lua.LNil {
		return models.Description{}
	} else {
		if v, ok := result.(*lua.LUserData); ok {
			if desc, ok := v.Value.(models.Description); ok {
				return desc
			} else {
				return models.Description{}
			}
		} else {
			return models.Description{}
		}
	}
}

func (p *LuaPlugin) CheckDescription(des models.Description) bool {
	var result bool
	if des.Pattern == p.Pattern &&
		des.Category == p.Category &&
		des.Name == p.Name {
		result = true
	} else {
		result = false
	}
	log.Debugf("Get plugin description: %+v, check result %v", des, result)
	return result
}

func (p *LuaPlugin) ClosePlugin() {
	if p.curIns != nil {
		p.curIns.Close()
	}
	log.Debugf("Close lua plugin %v %v %v", p.Category, p.Name, p.Version)
}

func (p *LuaPlugin) BackLState() {
	p.pool.Put(p.curIns)
	log.Debugln("Send back lua LState to lua pool")
}

func (p *LuaPlugin) Close() {
	p.ClosePlugin()
	p.BackLState()
}

func (p *LuaPlugin) PluginHash() string {
	return p.CurHash
}

func register(category string, factory PluginFactory) error {
	if factory == nil {
		return fmt.Errorf("lua pluagin factory do not exist")
	}

	if _, ok := pluginFactories[category]; ok {
		log.Errorf("Lua pluagin factory %v has been registered.\n", category)
	} else {
		pluginFactories[category] = factory
		log.Debugf("Register lua pluagin factory: %v\n", category)
	}
	return nil
}

func InitLuaPlugin() error {
	err := register("input", NewInput)
	if err != nil {
		return err
	}
	err = register("processor", NewProcessor)
	if err != nil {
		return err
	}
	err = register("aggregator", NewAggregator)
	if err != nil {
		return err
	}
	err = register("output", NewOutput)
	if err != nil {
		return err
	}
	return nil
}

func CreateLuaPlugin(pool *engine.LStatePool, c *config.PluginConfig) (interface{}, error) {
	if c.Category != "" {
		if factory, ok := pluginFactories[c.Category]; !ok {
			return nil, fmt.Errorf("invalid lua plugin type: %v", c.Category)
		} else {
			log.Debugf("Create lua plugin %v\n", c.Category)
			return factory(pool, c)
		}
	} else {
		return nil, fmt.Errorf("lua plugin config.Category is null")
	}
}
