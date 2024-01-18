package storage

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"github.com/PPIO/pi-collect/config"
	log "github.com/sirupsen/logrus"
)

//type HTTPReport struct {
//	Timestamp int64             `json:"timestamp,omitempty"`
//	SliceCnt  int64             `json:"slicecnt,omitempty"`
//	SliceIdx  int64             `json:"sliceidx,omitempty"`
//	Interval  int64             `json:"interval,omitempty"`
//	Version   int64             `json:"version,omitempty"`
//	Category  string            `json:"category,omitempty"`
//	Tags      map[string]string `json:"tags,omitempty"`
//	Fields    map[string][]map[string]interface{} `json:"fields,omitempty"`
//}

// Operator data operator
type Operator interface {
	AddField(category, pluginName, version, indicator, tag string,
		key string, value interface{}, tm time.Duration) error
	AddTag(category, pluginName, version, indicator, tag string) error
	GetField(category, pluginName, version, indicator string,
		start, end time.Duration) (*FieldList, error)
	GetTag(category, pluginName, version, indicator string) (string, error)
	//History(category, pluginName, version, indicator string) ([]time.Duration, error)
	//AddItem(category, pluginName, version string)

	CacheHasItem(category, pluginName, version string) error
	CacheItemList() []string

	CloseDataBox()
}

// DataBox data storage
type DataBox struct {
	*memorizer
}

var (
	once     sync.Once
	instance *DataBox
)

func (box *DataBox) combine(category, pluginName, version string) string {
	return category + "_" + pluginName + "_" + version
}

func (box *DataBox) AddField(
	category, pluginName, version, indicator, tag string,
	value string, tm time.Duration) error {
	itemName := box.combine(category, pluginName, version)
	return box.addField(itemName, indicator, tag, value, tm)
}

func (box *DataBox) AddTag(category, pluginName, version, indicator, tag string) error {
	itemName := box.combine(category, pluginName, version)
	return box.addTag(itemName, indicator, tag)
}

func (box *DataBox) GetFields(
	category, pluginName, version, indicator string,
	start, end time.Duration) (string, error) {
	itemName := box.combine(category, pluginName, version)
	strArray, err := box.getFields(itemName, indicator, start, end)
	if err != nil {
		return "", err
	}

	byteArray, err := json.Marshal(strArray)
	if err != nil {
		log.Errorf("String array encode to json error: %v", err)
		return "", err
	}

	log.Debugf("Get Fields: %v, %v, %v, %v, %v ~ %v, content: %+v",
		category, pluginName, version, indicator, time.Unix(int64(start), 0),
		time.Unix(int64(end), 0), string(byteArray))
	return string(byteArray), err
}

func (box *DataBox) GetFieldsMap(
	category, pluginName, version, indicator string,
	start, end time.Duration) (string, string, error) {
	itemName := box.combine(category, pluginName, version)
	keys, valueMap, err := box.getFieldsMap(itemName, indicator, start, end)
	if err != nil {
		return "", "", err
	}

	keysJson, err := json.Marshal(keys)
	if err != nil {
		log.Errorf("[]int64 encode to json error: %v", err)
		return "", "", err
	}

	valueJson, err := json.Marshal(valueMap)
	if err != nil {
		log.Errorf("map[int64]string encode to json error: %v", err)
		return "", "", err
	}

	log.Debugf("Get Fields: %v, %v, %v, %v, %v ~ %v, content: %+v",
		category, pluginName, version, indicator, time.Unix(int64(start), 0),
		time.Unix(int64(end), 0), string(valueJson))
	return string(keysJson), string(valueJson), err
}

func (box *DataBox) GetTag(category, pluginName, version, indicator string) (string, error) {
	itemName := box.combine(category, pluginName, version)
	return box.getTag(itemName, indicator)
}

//func (b *DataBox) History(category, pluginName, version, indicator string) ([]time.Duration, error) {
//	b.lock.Lock()
//	defer b.lock.Unlock()
//
//	itemName := b.combine(category, pluginName, version)
//	if _, ok := b.bucket[itemName]; ok {
//		if indicator == b.bucket[itemName].GetIndicator() {
//			return b.bucket[itemName].History(), nil
//		}
//	}
//
//	return nil, fmt.Errorf("can not find item")
//}

//func (b *DataBox) AddItem(category, pluginName, version string) {
//	itemName := b.combine(category, pluginName, version)
//
//	b.lock.Lock()
//	defer b.lock.Unlock()
//
//	if _, ok := b.bucket[itemName]; !ok {
//		b.bucket[itemName] = NewMetric("")
//	}
//}

func (box *DataBox) CacheHasItem(category, pluginName, version string) error {
	itemName := box.combine(category, pluginName, version)
	return box.cacheHasItem(itemName)
}

func (box *DataBox) CacheItemList() []string {
	return box.cacheItemList()
}

func (box *DataBox) CloseDataBox() {
	box.close()
}

func NewDataBox(
	ctx context.Context,
	period int64,
	cacheExpiration int64,
	dbConf config.DBConfig) *DataBox {
	once.Do(func() {
		instance = &DataBox{
			newMemorizer(ctx, period, cacheExpiration, dbConf),
		}
	})
	return instance
}
