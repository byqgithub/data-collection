package manager

import (
	"github.com/PPIO/pi-collect/config"
)

type manager interface {
	Load(src config.PluginConfig) error                           // 通过配置加载插件
	Remove(src config.Plugin) error                               // 关闭插件
	Update(pluginConfig config.Config, hashMap map[string]string) // 更新插件
	GetVersion(category string, name string) (string, string)     //获取指定插件版本和hash
	Notify(m chan bool) error                                     // 通知有插件需要更新
	Receive(pluginConfig config.Config)                           // 接收插件配置更新信号,准备插件更新
	ParsePluginMarking(pluginConfig config.Config)
}

// func main() {
// 	l := lua.NewState()
// 	defer l.Close()
// 	if err := l.DoString(`print("Hello World")`); err != nil {
// 		panic(err)
// 	}
// 	luar.New(nil, nil)
// }

// type timeRange struct {
// 	syncLock sync.Mutex
// 	cache    []int64 // 缓存中数据时间范围
// 	local    []int64 // 磁盘中数据时间范围
// }

// type metric struct {
// 	plugin  string
// 	version string
// 	item    string
// 	field   map[int64]interface{} // key: timestamp, value: data
// }

// var dataCache []metric // 插件数据缓存

// type storage interface {
// 	add(src metric)
// 	get() metric
// 	del()
// 	timestamps() []int64
// }

// type Transmission interface {
// 	AddFields(plugin string, version int, item string, tm int64, value interface{})
// 	GetFields(plugin string, version int, item string, tm []int64) metric
// }

// type interaction interface {
// 	convert(src metric) lua.LTable
// 	get(plugin string, version int, item string, tm []int64) lua.LTable
// 	add(plugin string, version int, item string, tm int64, value lua.LTable)
// }

// type instance struct {
// 	cur     *lua.LState
// 	renewal *lua.LState
// }

// type plugin struct {
// 	category string // input, processor, aggregator, output
// 	name     string // cpu, memory, task
// 	version  int
// 	ins      instance
// }

// var pluginInstance []plugin

// type pluginManager interface {
// 	load(src string)
// 	upload(*lua.LState)
// 	update(raw *lua.LState, new *lua.LState)
// 	getVersion() int
// }

// type Input interface {
// 	Description() string
// 	convert(src metric) lua.LTable                                           // 不同类型数据转换
// 	get(plugin string, version int, item string, tm []int64) lua.LTable      // 获取数据
// 	add(plugin string, version int, item string, tm int64, value lua.LTable) // 添加数据
// 	Collect() (*lua.LTable, error)                                           // 采集数据
// }

// type Processor interface {
// 	Description() string
// 	filter(src metric) bool                                                  // 判断是否处理该数据
// 	convert(src metric) lua.LTable                                           // 不同类型数据转换
// 	get(plugin string, version int, item string, tm []int64) lua.LTable      // 获取数据
// 	add(plugin string, version int, item string, tm int64, value lua.LTable) // 添加数据
// 	Dispose(pre *lua.LTable, now *lua.LTable) (*lua.LTable, error)           // 数据处理
// }

// type Aggregator interface {
// 	Description() string
// 	filter(src metric) bool                                                  // 判断是否处理该数据
// 	convert(src metric) lua.LTable                                           // 不同类型数据转换
// 	get(plugin string, version int, item string, tm []int64) lua.LTable      // 获取数据
// 	add(plugin string, version int, item string, tm int64, value lua.LTable) // 添加数据
// 	Add(m *lua.LTable) error                                                 // 收集采集项
// }

// type Output interface {
// 	Description() string
// 	filter(src metric) bool                                                  // 判断是否处理该数据
// 	convert(src metric) lua.LTable                                           // 不同类型数据转换
// 	get(plugin string, version int, item string, tm []int64) lua.LTable      // 获取数据
// 	add(plugin string, version int, item string, tm int64, value lua.LTable) // 添加数据
// 	Connect() error                                                          // 连接到目的地址
// 	Close() error                                                            // 连接断开
// 	Write(m *lua.LTable) error                                               // 写输出数据
// }
