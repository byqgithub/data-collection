package util

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"time"

	"github.com/denisbrodbeck/machineid"
	log "github.com/sirupsen/logrus"
)

var (
	DeviceId         string
	SpecialMachineId string
	DefaultMachineId string
)

func GetMachineId() string {
	var machineId string
	var err error
	if SpecialMachineId != "" {
		machineId = SpecialMachineId
		log.Debugf("Special machine id %v", machineId)
	} else {
		machineId, err = machineid.ID()
		if err != nil {
			log.Errorf("Get machineId failed, use default id %v", DefaultMachineId)
			machineId = DefaultMachineId
		}
		log.Debugf("Local machine id %v", machineId)
	}
	return machineId
}

func IsExists(path string) bool {
	_, err := os.Stat(path)
	if err != nil {
		if os.IsExist(err) {
			log.Debugf("File or directory already exists")
			return true
		} else {
			return false
		}
	} else {
		return true
	}
}

func FetchFiles(absolutePath string) []string {
	var files []string
	_ = filepath.Walk(absolutePath, func(path string, info os.FileInfo, err error) error {
		fileInfo, err := os.Stat(path)
		if err != nil {
			log.Debugf("Fetch file info error: %v", err)
		} else {
			if !fileInfo.IsDir() {
				files = append(files, path)
			}
		}
		return nil
	})
	return files
}

func SortInt64(raw []int64) []int64 {
	sort.SliceStable(raw, func(i, j int) bool {
		return raw[i] < raw[j]
	})
	return raw
}

func BitLeftShift(a, b int64) int64 {
	return a << b
}

func BitRightShift(a, b int64) int64 {
	return a >> b
}

func BitAND(a, b int64) int64 {
	return a & b
}

func BitOR(a, b int64) int64 {
	return a | b
}

func ToString(value interface{}) (string, error) {
	switch v := value.(type) {
	case string:
		return v, nil
	case []byte:
		return string(v), nil
	case int:
		return strconv.FormatInt(int64(v), 10), nil
	case int8:
		return strconv.FormatInt(int64(v), 10), nil
	case int16:
		return strconv.FormatInt(int64(v), 10), nil
	case int32:
		return strconv.FormatInt(int64(v), 10), nil
	case int64:
		return strconv.FormatInt(v, 10), nil
	case uint:
		return strconv.FormatUint(uint64(v), 10), nil
	case uint8:
		return strconv.FormatUint(uint64(v), 10), nil
	case uint16:
		return strconv.FormatUint(uint64(v), 10), nil
	case uint32:
		return strconv.FormatUint(uint64(v), 10), nil
	case uint64:
		return strconv.FormatUint(v, 10), nil
	case float32:
		return strconv.FormatFloat(float64(v), 'f', -1, 32), nil
	case float64:
		return strconv.FormatFloat(v, 'f', -1, 64), nil
	case bool:
		return strconv.FormatBool(v), nil
	case fmt.Stringer:
		return v.String(), nil
	case nil:
		return "", nil
	}
	return "", fmt.Errorf("type \"%T\" unsupported", value)
}

func DownloadUrl(url string) (string, error) {
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	c := http.Client{
		Timeout: 5 * time.Second,
	}
	var i int
	var resBody string
	for i = 0; i < 3; i++ {
		resp, err := c.Do(req)
		if err != nil {
			log.Errorf("%T: %+v", err, err)
			return "", err
		}

		body, _ := ioutil.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 {
			log.Errorln("rsp.StatusCode != 200, retry in 1s ")
			time.Sleep(1 * time.Second)
			continue
		}
		log.Println(string(body))
		resBody = string(body)
		break
	}
	return resBody, nil
}

func GetMd5Hash(text string) string {
	hash := md5.Sum([]byte(text))
	return hex.EncodeToString(hash[:])
}

func RemoveKeyFromSlice(slice1 []string) []string {
	var newSlice []string
	for _, key := range slice1 {
		if key != "" {
			newSlice = append(newSlice, key)
		}
	}
	return newSlice
}

func DifferenceSlice(slice1, slice2 []string) ([]string, []string) {
	m1 := make(map[string]struct{}, len(slice2))
	m2 := make(map[string]struct{}, len(slice1))
	add := make([]string, 0)
	del := make([]string, 0)

	for _, v := range slice2 {
		m1[v] = struct{}{}
	}
	for _, v := range slice1 {
		if _, ok := m1[v]; !ok {
			add = append(add, v)
		}
	}

	for _, v := range slice1 {
		m2[v] = struct{}{}
	}
	for _, v := range slice2 {
		if _, ok := m2[v]; !ok {
			del = append(del, v)
		}
	}
	return add, del
}
