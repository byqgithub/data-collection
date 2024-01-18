package storage

import (
	"bytes"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"time"

	"github.com/PPIO/pi-collect/config"
	"github.com/PPIO/pi-collect/pkg/util"

	log "github.com/sirupsen/logrus"
	bolt "go.etcd.io/bbolt"
)

type DBStore interface {
	Create(bucket string) error
	HasBucket(bucket string) error
	Get(bucket, key string) (value string, err error)
	Put(bucket, key string, value string) error
	Keys(bucket, prefix string) (keys []string, err error)
	Del(bucket, key string) error
	Has(bucket, key string) (bool, error)
	Close()
}

var (
	//Db             *bolt.DB
	ErrKeyNotFound = fmt.Errorf("key does not exist")
)

type BoltStore struct {
	db *bolt.DB
	//channel chan map[string]interface{}
}

func DbInit(conf config.DBConfig) (*bolt.DB, error) {
	storagePath := path.Dir(conf.Path)
	if !util.IsExists(storagePath) {
		if err := os.MkdirAll(storagePath, 777); err != nil {
			log.Errorf("Can not create dir %v, error: %v", storagePath, err)
		}
	}

	db, err := bolt.Open(conf.Path, 0600, nil)
	if err != nil {
		log.Errorf("could not open db, %v", err)
		return nil, err
	}
	return db, nil
}

func setupDb(conf config.DBConfig) *bolt.DB {
	defer func() {
		if err := recover(); err != nil {
			// TODO
			exceptionHandler(conf.Path)
			log.Errorf("open db panic %v", err)
		}
	}()

	db, err := DbInit(conf)
	if err != nil {
		log.Errorf("db init error")
		return nil
	}

	return db
}

func (b *BoltStore) Create(bucket string) error {
	if b.db == nil {
		return fmt.Errorf("DB is null")
	}

	err := b.db.Update(func(tx *bolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists([]byte(bucket))
		if err != nil {
			log.Errorln("bolt db create bucket error, ", err)
			return err
		}
		return nil
	})
	if err != nil {
		return err
	}
	return nil
}

func (b *BoltStore) HasBucket(bucket string) error {
	if b.db == nil {
		return fmt.Errorf("DB is null")
	}

	err := b.db.Update(func(tx *bolt.Tx) error {
		ins := tx.Bucket([]byte(bucket))
		if ins == nil {
			//log.Errorf("Can not find bucket %v", bucket)
			return fmt.Errorf("can not find bucket %v", bucket)
		}
		return nil
	})
	if err != nil {
		return err
	}
	return nil
}

func (b *BoltStore) Get(bucket, key string) (string, error) {
	if b.db == nil {
		return "", fmt.Errorf("DB is null")
	}

	var value string
	err := b.db.View(func(tx *bolt.Tx) error {
		c := tx.Bucket([]byte(bucket))
		v := c.Get([]byte(key))
		if v != nil {
			value = string(v)
		} else {
			log.Errorln(ErrKeyNotFound)
			return ErrKeyNotFound
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	return value, nil
}

func (b *BoltStore) Put(bucket, key string, value string) error {
	if b.db == nil {
		return fmt.Errorf("DB is null")
	}

	err := b.db.Update(func(tx *bolt.Tx) error {
		c, err := tx.CreateBucketIfNotExists([]byte(bucket))
		if err != nil {
			log.Errorln("bolt db create bucket error, ", err)
			return err
		}
		err = c.Put([]byte(key), []byte(value))
		if err != nil {
			log.Errorln("bolt db put key error:", err)
			return err
		}
		return nil
	})
	if err != nil {
		return err
	}
	return nil
}

func (b *BoltStore) Keys(bucket, prefix string) ([]string, error) {
	if b.db == nil {
		return nil, fmt.Errorf("DB is null")
	}

	values := make([]string, 0)
	err := b.db.View(func(tx *bolt.Tx) error {
		c := tx.Bucket([]byte(bucket)).Cursor()

		for k, _ := c.Seek([]byte(prefix)); k != nil && bytes.HasPrefix(k, []byte(prefix)); k, _ = c.Next() {
			//log.Printf("key=%s, value=%s\n", k, v)
			values = append(values, string(k))
		}
		return nil
	})

	if err != nil {
		return nil, err
	}
	return values, nil
}

func (b *BoltStore) Del(bucket, key string) error {
	if b.db == nil {
		return fmt.Errorf("DB is null")
	}

	err := b.db.Update(func(tx *bolt.Tx) error {
		c, err := tx.CreateBucketIfNotExists([]byte(bucket))
		if err != nil {
			log.Errorln("bolt db create bucket error, ", err)
			return err
		}
		err = c.Delete([]byte(key))
		if err != nil {
			log.Errorln("bolt db delete key error:", err)
			return err
		}
		return nil
	})
	if err != nil {
		return err
	}
	return nil
}

func (b *BoltStore) Has(bucket, key string) (bool, error) {
	if b.db == nil {
		return false, fmt.Errorf("DB is null")
	}

	err := b.db.View(func(tx *bolt.Tx) error {
		c := tx.Bucket([]byte(bucket))
		v := c.Get([]byte(key))
		if v != nil {
			log.Errorln(ErrKeyNotFound)
			return ErrKeyNotFound
		}
		return nil
	})
	if err != nil {
		return false, err
	}
	return true, nil
}

func (b *BoltStore) Close() {
	if b.db == nil {
		log.Errorln("DB is null")
		return
	}

	err := b.db.Close()
	if err != nil {
		log.Errorf("Close DB error: %v", err)
	} else {
		log.Infoln("Close DB successfully")
	}
}

func exceptionHandler(db string) {
	dbpath, fname := path.Split(db)
	ext := filepath.Ext(fname)
	name := fname[:len(fname)-len(ext)]
	newDb := fmt.Sprintf("%s/%s_%s%s", dbpath, name,
		time.Now().Format("2006-01-02_15-04-05"), ext)
	_ = os.Rename(db, newDb)
	log.Errorf("rename boltdb: old db: %v, new db %v", db, newDb)
}

func NewBoltStore(conf config.DBConfig) DBStore {
	return &BoltStore{
		db: setupDb(conf),
	}
}
