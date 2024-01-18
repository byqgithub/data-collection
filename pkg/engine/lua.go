package engine

import (
	"sync"

	lua "github.com/yuin/gopher-lua"
)

var (
	instance *LStatePool
	once sync.Once
)

type LStatePool struct {
	m     sync.Mutex
	saved []*lua.LState
}

func (pl *LStatePool) Get() *lua.LState {
	pl.m.Lock()
	defer pl.m.Unlock()
	n := len(pl.saved)
	if n == 0 {
		return pl.New()
	}
	x := pl.saved[n-1]
	pl.saved = pl.saved[0 : n-1]
	return x
}

func (pl *LStatePool) New() *lua.LState {
	L := lua.NewState()
	// setting the L up here.
	// load scripts, set global variables, share channels, etc...
	return L
}

func (pl *LStatePool) Put(L *lua.LState) {
	pl.m.Lock()
	defer pl.m.Unlock()
	pl.saved = append(pl.saved, L)
}

func (pl *LStatePool) Shutdown() {
	for _, L := range pl.saved {
		L.Close()
	}
}

func InitLStatePool(num int) *LStatePool {
	once.Do(func() {
		instance = &LStatePool{
			saved: make([]*lua.LState, 0, num),
		}
	})
	return instance
}

//func CompileLua(filePath string) (*lua.FunctionProto, error) {
//	file, err := os.Open(filePath)
//	if err != nil {
//		return nil, err
//	}
//	defer func() { _ = file.Close() }()
//
//	reader := bufio.NewReader(file)
//	chunk, err := parse.Parse(reader, filePath)
//	if err != nil {
//		return nil, err
//	}
//	proto, err := lua.Compile(chunk, filePath)
//	if err != nil {
//		return nil, err
//	}
//	return proto, nil
//}
