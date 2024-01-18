package converter

import (
	"encoding/json"

	log "github.com/sirupsen/logrus"
	lua "github.com/yuin/gopher-lua"
)

// 检查Table是否为List
func checkList(value lua.LValue) (b bool) {
	if value.Type().String() == "table" {
		b = true
		value.(*lua.LTable).ForEach(func(k, v lua.LValue) {
			if k.Type().String() != "number" {
				b = false
				return
			}
		})
	}
	return
}

// 检查Table类型
//func checkType(value lua.LValue) string {
//	valueType := ""
//	if value.Type().String() == "table" {
//		value.(*lua.LTable).ForEach(func(k, v lua.LValue) {
//			if k.Type().String() == "number" {
//				valueType = "array"
//				return
//			} else if k.Type().String() == "string" {
//				valueType = "map[string]interface{}"
//				return
//			}
//		})
//	}
//	return valueType
//}

// Marshal  lua data struct convert to go data struct
func Marshal(data lua.LValue) interface{} {
	switch data.Type() {
	case lua.LTTable:
		if checkList(data) {
			list := make([]interface{}, 0)
			data.(*lua.LTable).ForEach(func(key, value lua.LValue) {
				list = append(list, Marshal(value))
			})
			return list
		} else {
			dict := map[string]interface{}{}
			data.(*lua.LTable).ForEach(func(key, value lua.LValue) {
				dict[key.String()] = Marshal(value)
			})
			return dict
		}
	case lua.LTNumber:
		return float64(data.(lua.LNumber))
	case lua.LTString:
		return string(data.(lua.LString))
	case lua.LTBool:
		return bool(data.(lua.LBool))
	}
	return nil
}

func JsonMarshal(L *lua.LState) int {
	data := L.ToTable(1)
	str, err := json.Marshal(Marshal(data))
	if err != nil {
		log.Error(err)
	}
	L.Push(lua.LString(str))
	return 1
}

func unmarshal(L *lua.LState, data interface{}) lua.LValue {
	switch data.(type) {
	case map[string]interface{}:
		tb := L.NewTable()
		for k, v := range data.(map[string]interface{}) {
			tb.RawSet(lua.LString(k), unmarshal(L, v))
		}
		return tb
	case []map[string]interface{}:
		tb := L.NewTable()
		for i, v := range data.([]map[string]interface{}) {
			tb.Insert(i+1, unmarshal(L, v))
		}
		return tb
	case []interface{}:
		tb := L.NewTable()
		for i, v := range data.([]interface{}) {
			tb.Insert(i+1, unmarshal(L, v))
		}
		return tb
	case []string:
		tb := L.NewTable()
		for i, v := range data.([]string) {
			tb.Insert(i+1, unmarshal(L, v))
		}
		return tb
	case float64:
		return lua.LNumber(data.(float64))
	case string:
		return lua.LString(data.(string))
	case bool:
		return lua.LBool(data.(bool))
	default:
		if data == nil {
			//log.Warningf("Data is %v", data)
		} else {
			log.Warningf("type \"%T\" unsupported", data)
		}
	}
	return lua.LNil
}

func marshalStringArray(rawStr string) ([]string, error) {
	array := make([]string, 0)
	err := json.Unmarshal([]byte(rawStr), &array)
	return array, err
}

func marshalMapArray(rawStr string) ([]map[string]interface{}, error) {
	obj := make([]map[string]interface{}, 0)
	err := json.Unmarshal([]byte(rawStr), &obj)
	return obj, err
}

func marshalMap(rawStr string) (map[string]interface{}, error) {
	obj := make(map[string]interface{}, 0)
	err := json.Unmarshal([]byte(rawStr), &obj)
	return obj, err
}

func JsonUnMarshal(L *lua.LState) int {
	str := L.ToString(1)
	var err error
	var stringArray []string
	var mapObj map[string]interface{}
	var mapArray []map[string]interface{}

	stringArray, err = marshalStringArray(str)
	if err == nil {
		//log.Debugf("Convert to []string: %+v", stringArray)
		L.Push(unmarshal(L, stringArray))
	}

	if err != nil {
		mapObj, err = marshalMap(str)
		if err == nil {
			//log.Debugf("Convert to map[string]interface: %+v", mapObj)
			L.Push(unmarshal(L, mapObj))
		}
	}

	if err != nil {
		mapArray, err = marshalMapArray(str)
		if err == nil {
			//log.Debugf("Convert to []map[string]interface: %+v", mapArray)
			L.Push(unmarshal(L, mapArray))
		}
	}

	if err != nil {
		log.Errorf("%s type unsupported", str)
	}

	return 1
}

func ArrayUnMarshal(L *lua.LState) int {
	str := L.ToString(1)
	array := make([]string, 0)
	err := json.Unmarshal([]byte(str), &array)
	if err != nil {
		log.Warningf("Convert to []string error: %v, try to other structure", err)
		obj := make([]map[string]interface{}, 0)
		err = json.Unmarshal([]byte(str), &obj)
		if err != nil {
			log.Errorf("Convert to []map[string]interface error: %v", err)
		}
		log.Debugf("ArrayUnMarshal []map[string]interface: %v", obj)
		L.Push(unmarshal(L, obj))
	} else {
		log.Debugf("ArrayUnMarshal []string: %v", array)
		L.Push(unmarshal(L, array))
	}

	return 1
}
