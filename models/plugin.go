package models

import (
	"time"

	"github.com/PPIO/pi-collect/storage"
)

//type Plugin struct {
//	Pattern  string // lua
//	Category string // input, processor, aggregator, output
//	Name     string // cpu, memory, task
//	Version  int
//	CurHash  string
//	Path     string
//}

type PluginDescriber interface {
	GetDescription() Description
	CheckDescription(des Description) bool
	PluginHash() string
}

type PluginInitializer interface {
	Init() error
}

type PluginCloser interface {
	Close()
}

type Input interface {
	Collect(timeout time.Duration, out *storage.DataBox) error // 采集数据
}

type Processor interface {
	//filter() bool  // 判断是否处理该数据
	Dispose(timeout time.Duration,
		timeRange []time.Duration,
		pre *storage.DataBox,
		now *storage.DataBox) error // 数据处理
}

type Aggregator interface {
	//filter() bool   // 判断是否处理该数据
	Converge(timeout time.Duration,
		timeRange []time.Duration,
		pre *storage.DataBox,
		now *storage.DataBox) error // 聚合采集项
}

type Output interface {
	//filter() bool   // 判断是否处理该数据
	//Connect() error // 连接到目的地址
	//Close() error   // 连接断开
	Write(timeout time.Duration, timeRange []time.Duration, in *storage.DataBox) error // 写输出数据
}

type Description struct {
	Pattern  string // lua
	Category string // input, processor, aggregator, output
	Name     string // cpu, memory, task
	Version  string
}

func (d *Description) Set(patter, category, name, version string) {
	d.Pattern = patter
	d.Category = category
	d.Name = name
	d.Version = version
}

//type LuaPlugin struct {
//	Plugin
//	curIns *lua.LState
//}
//
//// get lua plugin property
//func (p *LuaPlugin) property() description {
//	if err := p.curIns.CallByParam(lua.P{
//		Fn:      p.curIns.GetGlobal("property"),
//		NRet:    1,
//		Protect: true,
//	},
//	); err != nil {
//		p.curIns.Close()
//		return description{}
//	}
//	result := p.curIns.CheckAny(-1) // fetch result
//	p.curIns.Pop(1)                 // clear result
//
//	// convert LUserData to description
//	if result == lua.LNil {
//		return description{}
//	} else {
//		if v, ok := result.(*lua.LUserData); ok {
//			if info, ok := v.Value.(description); ok {
//				return info
//			} else {
//				return description{}
//			}
//		} else {
//			return description{}
//		}
//	}
//}
//
//func (p *LuaPlugin) checkProperty(info description) bool {
//	if info.pattern == p.pattern && info.category == p.category && info.name == p.name && info.version == p.version {
//		return true
//	} else {
//		return false
//	}
//}
//
//func (p *LuaPlugin) close() {
//	p.curIns.Close()
//}
//
//func (p *LuaPlugin) pluginHash() string {
//	return p.curHash
//}
