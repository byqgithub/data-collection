package storage

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/pkg/util"
	log "github.com/sirupsen/logrus"
)

type dbOperator interface {
	AddBucket(bucket string) error
	HasBucket(bucket string) error
	AddMetadata(bucket string, m metadata) error
	ModifyMetadata(bucket string, m metadata) error
	GetMetadata(bucket string) (metadata, error)
	AddData(bucket string, key time.Duration, value string) error
	DelData(bucket string, key time.Duration) error
	SearchData(bucket string, start, end time.Duration) ([]string, error)
	HasData(bucket string, key time.Duration) error
	AllDataInBucket(bucket, prefix string) (map[string]string, error)
	closeDB()
}

type metadata struct {
	Indicator string `json:"indicator"` // 采集指标: cpu, memory
	Tag       string `json:"tag"`       // 为采集指标设置特殊标记
}

type dbMessenger struct {
	//channel chan map[string]interface{}
	db DBStore
}

func (db *dbMessenger) AddBucket(bucket string) error {
	err := db.db.Create(bucket)
	if err != nil {
		log.Errorf("Can not create bucket %v in DB", bucket)
		return err
	}
	log.Debugf("Create bucket %v in DB", bucket)
	return nil
}

func (db *dbMessenger) HasBucket(bucket string) error {
	err := db.db.HasBucket(bucket)
	if err != nil {
		log.Errorf("Can not find bucket %v in DB", bucket)
		return err
	}
	return nil
}

func (db *dbMessenger) AddMetadata(bucket string, m metadata) error {
	mStr, err := encodingMetadata(m)
	if err != nil {
		return err
	}
	err = db.db.Put(bucket, "metadata", mStr)
	if err != nil {
		return err
	}
	return nil
}

func (db *dbMessenger) ModifyMetadata(bucket string, m metadata) error {
	return db.AddMetadata(bucket, m)
}

func (db *dbMessenger) GetMetadata(bucket string) (metadata, error) {
	mStr, err := db.db.Get(bucket, "metadata")
	if err != nil {
		log.Errorf("Can not get metadata in buckt %v from DB", bucket)
		return metadata{}, err
	}
	data, err := decodeMetadata(mStr)
	if err != nil {
		return metadata{}, err
	}
	return data, nil
}

func (db *dbMessenger) AddData(bucket string, key time.Duration, value string) error {
	//fStr, err := encodingToString(value)
	//if err != nil {
	//	return err
	//}
	err := db.db.Put(bucket, fmt.Sprintf("%v", int64(key)), value)
	if err != nil {
		log.Errorf("Add data to DB failed, error: %v", err)
		return err
	}
	return nil
}

func (db *dbMessenger) DelData(bucket string, key time.Duration) error {
	err := db.db.Del(bucket, fmt.Sprintf("%v", int64(key)))
	if err != nil {
		log.Errorf("Del data from buckt %v error: %v", bucket, err)
		return err
	}
	return nil
}

func (db *dbMessenger) SearchData(bucket string, start, end time.Duration) ([]string, error) {
	searchKeys := make([]int64, 0, 100)
	allKeys, err := db.db.Keys(bucket, "")
	if err != nil {
		log.Errorf("Get bucket all keys error: %v", err)
		return nil, err
	}

	for _, k := range allKeys {
		temp, err := strconv.ParseInt(k, 10, 64)
		if err != nil {
			log.Errorf("%v convert to int64 failed, error: %v", k, err)
			continue
		}
		if temp > int64(start) && temp < int64(end) {
			searchKeys = append(searchKeys, temp)
		}
	}

	searchKeys = util.SortInt64(searchKeys)
	result := make([]string, len(searchKeys))
	//result := NewFieldList(len(searchKeys))
	for _, k := range searchKeys {
		data, err := db.db.Get(bucket, string(k))
		if err != nil {
			log.Errorf("From bucket %v get key %v value failed, error: %v", bucket, k, err)
			continue
		}
		//field, err := decodeToField(data)
		//if err != nil {
		//	continue
		//}
		//result.Append(field)
		result = append(result, data)
	}
	//if result.Len() == 0 {
	//	return result, fmt.Errorf("can not find data")
	//}
	if len(result) == 0 {
		return result, fmt.Errorf("can not find data")
	}
	return result, nil
}

func (db *dbMessenger) HasData(bucket string, key time.Duration) error {
	_, err := db.db.Has(bucket, fmt.Sprintf("%v", int64(key)))
	if err != nil {
		log.Errorf("Can not find key %v from bucket", key, bucket)
		return err
	}
	return nil
}

func (db *dbMessenger) AllDataInBucket(bucket, prefix string) (map[string]string, error) {
	err := db.HasBucket(bucket)
	if err != nil {
		return nil, err
	}

	allKeys, err := db.db.Keys(bucket, prefix)
	if err != nil {
		log.Errorf("Get bucket all keys error: %v", err)
		return nil, err
	}

	result := make(map[string]string, len(allKeys))
	for _, k := range allKeys {
		data, err := db.db.Get(bucket, k)
		if err != nil {
			log.Errorf("Failed to get key %v value from bucket %v, error: %v", k, bucket, err)
			if strings.Contains(err.Error(), "database not open") {
				break
			} else {
				continue
			}
		}
		result[k] = data
	}

	//if len(result) == 0 {
	//	//log.Warningf("Bucket %v is NULL", bucket)
	//	return result, fmt.Errorf("can not find data")
	//}
	return result, nil
}

// start: 0 表示存储数据的最早时间
func (db *dbMessenger) clean(delBuckets []string, start, end time.Duration) error {
	for _, bucket := range delBuckets {
		if db.db.HasBucket(bucket) != nil {
			log.Errorf("Clean DB history data, can not find bucket %v", bucket)
			continue
		}
		searchKeys := make([]string, 0, 100)
		allKeys, err := db.db.Keys(bucket, "")
		if err != nil {
			log.Errorf("Get bucket all keys error: %v", err)
		}

		for _, k := range allKeys {
			temp, err := strconv.ParseInt(k, 10, 64)
			if err != nil {
				log.Errorf("%v convert to int64 failed, error: %v", k, err)
				continue
			}
			tm := time.Duration(temp)
			if tm > start && tm < end {
				searchKeys = append(searchKeys, k)
			}
		}

		for _, key := range searchKeys {
			log.Printf("Del bucket %v key %v", bucket, key)
			err := db.db.Del(bucket, key)
			if err != nil {
				log.Errorf("Del bucket %v key %v failed, error: %v", bucket, key, err)
			}
		}
	}

	return nil
}

func (db *dbMessenger) closeDB() {
	db.db.Close()
}

func newDbMessenger(dbConf config.DBConfig) *dbMessenger {
	log.Debugf("Database config: %+v", dbConf)
	return &dbMessenger{NewBoltStore(dbConf)}
}

func encodingMetadata(value metadata) (string, error) {
	byteArray, err := json.Marshal(value)
	if err != nil {
		log.Errorf("Metadata %v convert to string, error %v", value, err)
		return "", err
	}
	return fmt.Sprintf("%s", byteArray), nil
}

func decodeMetadata(value string) (metadata, error) {
	if len(value) <= 0 {
		return metadata{}, fmt.Errorf("metadata string length is 0")
	}

	var data metadata
	err := json.Unmarshal([]byte(value), &data)
	if err != nil {
		log.Errorf("string convert to metadata, error %v", err)
		return metadata{}, err
	}
	return data, nil
}

func encodingToString(value interface{}) (string, error) {
	var keyStr string
	var err error
	buf := make(map[string]interface{})
	switch value.(type) {
	case map[interface{}]interface{}:
		for key, data := range value.(map[interface{}]interface{}) {
			keyStr, err = util.ToString(key)
			if err != nil {
				log.Errorf("Encode Field to string, key %v encode error: %v", key, err)
			}
			//dataStr, err = util.ToString(data)
			//if err != nil {
			//	log.Errorf("Encode Field to string, data %v encode error: %v", data, err)
			//}
			buf[keyStr] = data
		}
	default:
		log.Warningf("type \"%T\" be saved", value)
		buf["default"] = value
	}

	byteArray, err := json.Marshal(buf)
	if err != nil {
		log.Errorf("Field %v convert to string, error %v", value, err)
		return "", err
	}
	return fmt.Sprintf("%s", byteArray), nil
}

func decodeToField(value string) (*Field, error) {
	if len(value) <= 0 {
		return &Field{}, fmt.Errorf("field string length is 0")
	}

	var mid map[string]interface{}
	err := json.Unmarshal([]byte(value), &mid)
	if err != nil {
		log.Errorf("Field convert to middle data, error %v", err)
		return &Field{}, err
	}

	data := NewField(len(mid))
	for k, v := range mid {
		data.Append(&Unit{k, v})
	}
	return data, nil
}
