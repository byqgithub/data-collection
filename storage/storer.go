package storage

import (
	"context"
	"fmt"

	//"reflect"
	"sync"
	"time"

	"github.com/PPIO/pi-collect/config"
	log "github.com/sirupsen/logrus"
)

// Storer data storage interface
type Storer interface {
	addField(item, indicator, tag string, key string, value interface{}, tm time.Duration) error
	addTag(item, indicator, tag string) error
	getField(item, indicator string, start, end time.Duration) (*FieldList, error)
	getTag(item, indicator string) (string, error)
	//history(item string) ([]time.Duration, error)

	//addItem(item string)
	cacheHasItem(item string) error
	cacheItemList() []string
}

type cleaner interface {
	clean(delKeys []string, start, end time.Duration) error
}

type memorizer struct {
	lock  sync.Mutex
	cache map[string]*Metric // key: category+pluginName+version; value: plugin data
	DB    *dbMessenger
}

func (m *memorizer) showCache(item string) {
	log.Debugf("Memorizer cache: item: %v, indicator: %v, tag: %v",
		item, m.cache[item].indicator, m.cache[item].tag)
	for tm, data := range m.cache[item].fields {
		if time.Now().Unix()-120 > int64(tm) {
			continue
		}
		log.Debugf("Memorizer cache: item: %v, time: %v, Field: %+v",
			item, time.Unix(int64(tm), 0), data)
		//for k, v := range (*data).set {
		//	log.Debugf("Memorizer cache: item: %v, Unit set: index: %v, key: %v, value: %v",
		//		item, k, (*v).Key, (*v).Value)
		//}
	}
}

func (m *memorizer) addField(item, indicator, tag string,
	value string, tm time.Duration) error {
	m.lock.Lock()
	defer m.lock.Unlock()

	if _, ok := m.cache[item]; !ok {
		m.cache[item] = NewMetric(indicator)
	} else {
		m.cache[item].SetIndicator(indicator)
	}
	m.cache[item].AddTag(tag)
	if err := m.cache[item].AddField(value, tm); err != nil {
		log.Errorf("From cache add Field error: %v", err)
		return err
	}
	//m.showCache(item) // TODO For debug
	log.Debugf("Cache: item: %v, indicator: %v, tag: %v, time: %v, field: %+v",
		item, m.cache[item].indicator, m.cache[item].tag,
		time.Unix(int64(tm), 0), m.cache[item].fields[tm])

	err := m.DB.HasBucket(item)
	if err != nil {
		err = m.DB.AddBucket(item)
		if err != nil {
			log.Errorf("Add bucket to DB error: %v", err)
			return err
		}
	}
	_, err = m.DB.GetMetadata(item)
	if err == nil {
		log.Debug("Find storage item from DB, and try to cover raw metadata")
		err = m.DB.ModifyMetadata(item, metadata{Indicator: indicator, Tag: tag})
		if err != nil {
			log.Errorf("Modify metadata to DB error: %v", err)
			return err
		}
	} else {
		err = m.DB.AddMetadata(item, metadata{Indicator: indicator, Tag: tag})
		if err != nil {
			log.Errorf("Add metadata to DB error: %v", err)
			return err
		}
	}
	//log.Debugf("param type: key: %v, value: %v", reflect.TypeOf(key), reflect.TypeOf(value))
	err = m.DB.AddData(item, tm, value)
	if err != nil {
		log.Errorf("Add Field to DB error: %v", err)
	}

	return nil
}

func (m *memorizer) addTag(item, indicator, tag string) error {
	m.lock.Lock()
	defer m.lock.Unlock()

	if _, ok := m.cache[item]; ok {
		if indicator == m.cache[item].GetIndicator() {
			m.cache[item].AddTag(tag)
			return nil
		}
	}

	meta, err := m.DB.GetMetadata(item)
	if err == nil {
		if meta.Indicator == indicator && meta.Tag == tag {
			return nil
		} else if meta.Indicator == indicator && meta.Tag != tag {
			log.Debugln("Find storage item from DB, and try to cover raw tag")
			return m.DB.ModifyMetadata(item, metadata{Indicator: indicator, Tag: tag})
		} else {
			return fmt.Errorf("find storage item from DB, but has different indicator")
		}
	}

	return fmt.Errorf("can not add tag")
}

func (m *memorizer) getFields(item, indicator string,
	start, end time.Duration) ([]string, error) {
	m.lock.Lock()
	defer m.lock.Unlock()

	if _, ok := m.cache[item]; ok {
		if indicator == m.cache[item].GetIndicator() {
			keys, valueMap, err := m.cache[item].Search(start, end)
			if err != nil {
				log.Errorf("Can not get fields, %v, %v, %v ~ %v", item, indicator,
					time.Unix(int64(start), 0), time.Unix(int64(end), 0))
				return make([]string, 0), err
			}

			cache := make([]string, 0, len(keys))
			for _, key := range keys {
				cache = append(cache, valueMap[key])
			}
			log.Infof("Get fields, %v, %v, %v ~ %v, content: %+v", item, indicator,
				time.Unix(int64(start), 0), time.Unix(int64(end), 0), cache)
			return cache, err
		}
	}

	//fields, err := m.db.SearchData(item, start, end)
	//if err != nil {
	//	log.Errorf("From db search data error: %v", err)
	//} else {
	//	return fields, nil
	//}

	log.Errorf("Can not get fields, %v, %v, %v ~ %v",
		item, indicator, time.Unix(int64(start), 0), time.Unix(int64(end), 0))
	return make([]string, 0), fmt.Errorf("can not get Field")
}

func (m *memorizer) getFieldsMap(item, indicator string,
	start, end time.Duration) ([]int64, map[int64]string, error) {
	m.lock.Lock()
	defer m.lock.Unlock()

	if _, ok := m.cache[item]; ok {
		if indicator == m.cache[item].GetIndicator() {
			keys, valueMap, err := m.cache[item].Search(start, end)
			if err != nil {
				log.Errorf("Can not get fields, %v, %v, %v ~ %v", item, indicator,
					time.Unix(int64(start), 0), time.Unix(int64(end), 0))
				return make([]int64, 0), make(map[int64]string, 0), err
			}

			log.Infof("Get fields, %v, %v, %v ~ %v, content: %+v", item, indicator,
				time.Unix(int64(start), 0), time.Unix(int64(end), 0), valueMap)
			return keys, valueMap, err
		}
	}

	log.Errorf("Can not get fields, %v, %v, %v ~ %v",
		item, indicator, time.Unix(int64(start), 0), time.Unix(int64(end), 0))
	return make([]int64, 0), make(map[int64]string, 0), fmt.Errorf("can not get Fields map")
}

func (m *memorizer) getTag(item, indicator string) (string, error) {
	m.lock.Lock()
	defer m.lock.Unlock()

	if _, ok := m.cache[item]; ok {
		if indicator == m.cache[item].GetIndicator() {
			return m.cache[item].GetTag(), nil
		}
	}

	metadata, err := m.DB.GetMetadata(item)
	if err == nil {
		if metadata.Indicator == indicator {
			return metadata.Tag, nil
		}
	}

	return "", fmt.Errorf("can not get tag")
}

//func (mem *memorizer) history(item string) ([]time.Duration, error) {
//	mem.lock.Lock()
//	defer mem.lock.Unlock()
//
//	return nil, nil
//}

func (m *memorizer) cacheHasItem(item string) error {
	m.lock.Lock()
	defer m.lock.Unlock()

	if _, ok := m.cache[item]; ok {
		return nil
	} else {
		return fmt.Errorf("can not find item %v", item)
	}
}

func (m *memorizer) cacheItemList() []string {
	m.lock.Lock()
	defer m.lock.Unlock()

	tmp := make([]string, 0, len(m.cache))
	for itemName := range m.cache {
		tmp = append(tmp, itemName)
	}
	return tmp
}

func (m *memorizer) clean(delItems []string, start, end time.Duration) error {
	var err error
	m.lock.Lock()
	defer m.lock.Unlock()

	if len(delItems) == 0 {
		for item := range m.cache {
			err = m.cache[item].DelFields(start, end)
			if err != nil {
				log.Errorf("Delete fields from cache error %v", err)
			}
		}
	}

	//err = m.db.clean(start, end)
	//log.Errorf("Delete fields from DB error %v", err)
	return err
}

func (m *memorizer) close() {
	m.lock.Lock()
	m.cache = make(map[string]*Metric, 0)
	m.lock.Unlock()
	m.DB.closeDB()
}

func (m *memorizer) cleanPeriodically(
	ctx context.Context,
	period int64,
	cacheExpiration int64,
	dbExpiration int64) {
	log.Debugln("Start clean cache data and DB data periodically")
	ticker := time.NewTicker(time.Second * time.Duration(period))

cleanLoop:
	for {
		select {
		case <-ctx.Done():
			break cleanLoop
		case <-ticker.C:
			cacheDeadline := time.Duration(time.Now().Unix() - cacheExpiration)
			dbDeadline := time.Duration(time.Now().Unix() - dbExpiration)
			err := m.clean([]string{}, 0, cacheDeadline)
			if err != nil {
				log.Errorf("Delete fields from cache error %v", err)
			}
			log.Printf("db deadline %d", dbDeadline)
			err = m.DB.clean(m.cacheItemList(), 0, dbDeadline)
			if err != nil {
				log.Errorf("Delete fields from DB error %v", err)
			}

			report_bucket := []string{"report_save"}
			err = m.DB.clean(report_bucket, 0, dbDeadline)
			if err != nil {
				log.Errorf("Delete fields from DB error %v", err)
			}
		}
	}
}

func newMemorizer(
	ctx context.Context,
	period int64,
	cacheExpiration int64,
	dbConf config.DBConfig) *memorizer {
	instance := &memorizer{
		DB:    newDbMessenger(dbConf),
		cache: make(map[string]*Metric, 0),
	}
	go instance.cleanPeriodically(ctx, period, cacheExpiration, dbConf.Expiration)
	return instance
}
