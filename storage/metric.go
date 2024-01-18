package storage

import (
	"fmt"
	"github.com/PPIO/pi-collect/pkg/util"
	"time"

	log "github.com/sirupsen/logrus"
)

type DataHandler interface {
	SetIndicator(indicator string)
	AddTag(tag string)
	AddField(value string, tm time.Duration) error
	DelFields(start, end time.Duration) error
	Search(start, end time.Duration) ([]int64, map[int64]string, error)

	GetIndicator() string
	GetTag() string
	History() []time.Duration
	Has(tm time.Duration) bool
}

type Unit struct {
	Key   string      `json:"key"`
	Value interface{} `json:"value"`
}

func (c *Unit) GetKey() string {
	return c.Key
}

func (c *Unit) GetValue() interface{} {
	return c.Value
}

type Field struct {
	set []*Unit
}

func (c *Field) Len() int {
	return len(c.set)
}

func (c *Field) Append(u *Unit) {
	c.set = append(c.set, u)
}

func (c *Field) GetUnit(index int) *Unit {
	if index >= 0 && index < len(c.set) {
		return c.set[index]
	} else {
		return nil
	}
}

func NewField(num int) *Field {
	return &Field{make([]*Unit, 0, num)}
}

type FieldList struct {
	list []*Field
}

func (c *FieldList) Len() int {
	return len(c.list)
}

func (c *FieldList) Append(f *Field) {
	c.list = append(c.list, f)
}

func (c *FieldList) GetField(index int) *Field {
	if index >= 0 && index < len(c.list) {
		//log.Debugf("GetField return %v", c.list[index])
		return c.list[index]
	} else {
		return nil
	}
}

func NewFieldList(num int) *FieldList {
	return &FieldList{make([]*Field, 0, num)}
}

type Metric struct {
	indicator string                   // 采集指标: cpu, memory
	tag       string                   // 为采集指标设置特殊标记
	fields    map[time.Duration]string // key: timestamp; value: data
	//timeRange []time.Duration        // 数据时间范围
}

func (c *Metric) SetIndicator(indicator string) {
	c.indicator = indicator
}

func (c *Metric) AddTag(tag string) {
	c.tag = tag
}

//func (c *Metric) updateTimeRange(tm time.Duration) error {
//	if tm > c.timeRange[0] && tm > c.timeRange[1] {
//		c.timeRange[1] = tm
//		return nil
//	} else {
//		return fmt.Errorf("time range error: cur %v, range %v", tm, c.timeRange)
//	}
//}

func (c *Metric) AddField(value string, tm time.Duration) error {
	//var keyStr string
	//var err error
	//field := NewField(0)
	//switch value.(type) {
	//case map[interface {}]interface {}:
	//	for key, data := range value.(map[interface {}]interface {}) {
	//		keyStr, err = util.ToString(key)
	//		if err != nil {
	//			log.Errorf("Metric add Field, key %v encode error: %v", key, err)
	//		}
	//		//dataStr, err = util.ToString(data)
	//		//if err != nil {
	//		//	log.Errorf("Metric add Field, data %v encode error: %v", data, err)
	//		//}
	//		field.Append(&Unit{Key: keyStr, Value: data})
	//	}
	//default:
	//	log.Warningf("type \"%T\" be saved", value)
	//	field.Append(&Unit{Key: "", Value: value})
	//}

	if _, ok := c.fields[tm]; !ok {
		c.fields[tm] = value
	} else {
		return fmt.Errorf("timestamp %v already existed", tm)
	}
	//if err := c.updateTimeRange(tm); err != nil {
	//	return err
	//} else {
	//	if _, ok := c.fields[tm]; !ok {
	//		c.fields[tm] = &Field{key: key, value: v}
	//	} else {
	//		return fmt.Errorf("timestamp %v already existed", tm)
	//	}
	//	return nil
	//}
	return nil
}

func (c *Metric) DelFields(start, end time.Duration) error {
	if start > end {
		return fmt.Errorf("param error: start > end")
	}

	num := 1000
	if end - start < 1000 {
		num = int(end - start)
	}
	delKey := make([]time.Duration, 0, num)
	for key := range c.fields {
		if key >= start && key <= end {
			delKey = append(delKey, key)
		}
	}
	for _, key := range delKey {
		delete(c.fields, key)
	}
	return nil

	//if start > c.timeRange[0] && end < c.timeRange[1] {
	//	num := 1000
	//	if end - start < 1000 {
	//		num = int(end - start)
	//	}
	//	delKey := make([]time.Duration, 0, num)
	//	for key := range c.fields {
	//		if key >= start && key <= end {
	//			delKey = append(delKey, key)
	//		}
	//	}
	//	for _, key := range delKey {
	//		delete(c.fields, key)
	//	}
	//	return nil
	//} else {
	//	return fmt.Errorf("exceed time range")
	//}
}

func (c *Metric) Search(start, end time.Duration) ([]int64, map[int64]string, error) {
	if start > end {
		return nil, nil, fmt.Errorf("param error: start > end")
	}

	searchKeys := make([]int64, 0, 100)
	cache := make(map[int64]string, 0)
	for key := range c.fields {
		if key >= start && key < end {
			searchKeys = append(searchKeys, int64(key))
			cache[int64(key)] = c.fields[key]
		}
	}

	searchKeys = util.SortInt64(searchKeys)
	//log.Debugf("Search cache, keys: %v", searchKeys)
	//cache := make([]string, 0, len(searchKeys))
	//for _, key := range searchKeys {
	//	cache = append(cache, c.fields[time.Duration(key)])
	//	//tmpF := NewField(1)
	//	//tmpU := &Unit{Key: "xxx", Value: key}
	//	//tmpF.Append(tmpU)
	//	//cache.Append(tmpF)
	//}
	log.Debugf("Search cache time %v ~ %v, sorted keys: %+v, data: %+v",
		time.Unix(int64(start), 0), time.Unix(int64(end), 0),
		searchKeys, cache)
	return searchKeys, cache, nil
}

func (c *Metric) GetIndicator() string {
	return c.indicator
}

func (c *Metric) GetTag() string {
	return c.tag
}

func (c *Metric) History() []time.Duration {
	cache := make([]time.Duration, 0, len(c.fields))
	for key := range c.fields {
		cache = append(cache, key)
	}
	return cache
}

func (c *Metric) Has(tm time.Duration) bool {
	if _, ok := c.fields[tm]; ok {
		return true
	} else {
		return false
	}
	//if tm >= c.timeRange[0] && tm <= c.timeRange[1] {
	//	return true
	//} else {
	//	return false
	//}
}

func NewMetric(indicator string) *Metric {
	//return &Metric{indicator: indicator,
	//	timeRange: []time.Duration{tm, tm},
	//	fields: make(map[time.Duration]*Field, 0, 100),
	//}
	return &Metric{indicator: indicator,
		fields: make(map[time.Duration]string, 0),
	}
}
