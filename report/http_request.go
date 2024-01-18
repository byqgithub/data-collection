package report

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/md5"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"net/url"
	"strconv"
	"sync"
	"time"

	"github.com/PPIO/pi-collect/pkg/util"
	"github.com/PPIO/pi-collect/storage"
	log "github.com/sirupsen/logrus"
)

var (
	dataChannel chan reportDetail
	client      *http.Client
)

var tokenMap = map[bool]string{
	false: "Bearer eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOjg3MiwidXNlcm5hbWUiOiJvcHMiLCJyb2xlIjoxNn0.E7-04n_bdl6_LtxoR0qecFEAxdkLG6ZaOR0n4DbwnOqe4SRgTOoyLcOiz6ZxRbjSO9PjyGvBxJ3tQCnO29dUiVn_HMaJvFLe0v-wuQrbjFaARjCxFaGqB93ViDwCNRcHINv4H7GX2PkMKYOfwFZ6033BOMMzbHIdYSrSwcVORpvfYVDcIBZHI7-zcf7qgkCyGJLF7X1z6NLKwlwuPyvgNyssJF_GZne0w1-nYYNgSIqlmcv4smEESz15ng9aQ5SdCaqlI4c7BvmSjb1OuzzGKDRGsu5TGYLV8U51KF3qNHyTfzZ_us0J0FY3QMmsTH6PNs09SVUHcp1Wt7EARttBQQ",
	true:  "Bearer eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOjMxMCwidXNlcm5hbWUiOiLmtL7kupHnrqHnkIYiLCJyb2xlIjoxfQ.llISTPP_23krINPF35VXQutU3eLH_m4K_XSqRECNRNLVZI8WyLyicloyOazM8Ojf4JpUL7yXvDxX8YBQygXRL7nLHgEykmb0l93MabFQvUtny0nMSBBdAdpCaGce_MUT_yuilLHaClK2m2hAjYsUyS3tQ-rKmgVCYeJi_XchLOws6ZGyR89HGFt3IyW7d_z5lRPSbcvH6iYtMr3aPEB9VltmBBX5apZNHAHPbxK5Bc_zq6t5diLHpE1S43avUX4knGWbJUjUeuzEDvFFcXFUgQ1aCJ72PJvHfpX4hTM_hvVBlwGvPPCaqMGWtvK0pMnUHKpVMIJDbHOndE35Zhh0Zw",
}

var manageURLMap = map[bool]string{
	false: "https://internal.api.paigod.work",
	true:  "http://api.test.paigod.work",
}

var bigDataURLMap = map[bool]string{
	false: "https://datachannel.painet.work",
	true:  "http://datachannel.test.painet.work",
}

var baseURLMap = map[string]interface{}{
	"bigData": bigDataURLMap, // 大数据平台
	"manage":  manageURLMap,  // 管理平台
}

var urlMap = map[string]string{
	"deviceInfo": "/internal/device_info",
	"dataReport": "/v5/data",
}

type manageHttpReasonJson struct {
	Code    int
	Message string `json:"msg"`
}

type bigDataHttpReasonJson struct {
	TraceId string `json:"trace_id"`
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type reportDetail struct {
	Path     string            `json:"path"`
	Category string            `json:"category"`
	Query    map[string]string `json:"query"`
	Body     interface{}       `json:"body"`
	Debug    bool              `json:"debug"`
	IsZip    bool              `json:"is_zip"`
}

func urlSign(machineId string, timestamp int64, data []byte) string {
	buf := make([]byte, 0)
	buffer := bytes.NewBuffer(buf)
	buffer.WriteString(machineId)
	buffer.WriteString(strconv.FormatInt(timestamp, 10))
	size := len(data)
	if size > 16 {
		size = 16
	}
	buffer.Write(data[:size])
	md5Str := md5.Sum(buffer.Bytes())
	return fmt.Sprintf("%x", md5Str)
}

func jointUrl(path, category string, debug bool) string {
	rootURL := make(map[bool]string)
	switch category {
	case "bigData":
		rootURL = baseURLMap["bigData"].(map[bool]string)
	case "manage":
		rootURL = baseURLMap["manage"].(map[bool]string)
	default:
		rootURL = baseURLMap["manage"].(map[bool]string)
	}

	baseURL := ""
	if debug {
		baseURL = rootURL[true] + path
	} else {
		baseURL = rootURL[false] + path
	}
	log.Infof("HTTP Category %s, base url %s", category, baseURL)
	return baseURL
}

func configQuery(path, category string, query map[string]string, debug bool) (string, error) {
	baseURL := jointUrl(path, category, debug)
	parsedUrl, err := url.ParseRequestURI(baseURL)
	if err != nil {
		log.Errorf("Can not parse url(%s), error: %v", baseURL, err)
		return "", err
	}

	params := url.Values{}
	for i, v := range query {
		params.Set(i, v)
	}
	parsedUrl.RawQuery = params.Encode()
	baseURL = parsedUrl.String()
	log.Infof("HTTP full url: %s", baseURL)
	return baseURL, nil
}

func configHeader(request *http.Request, debug, isZip bool) {
	request.Header.Add("Content-Type", "application/json")
	if isZip {
		request.Header.Add("Content-Encoding", "gzip")
	}

	if debug {
		request.Header.Add("Authorization", tokenMap[true])
	} else {
		request.Header.Add("Authorization", tokenMap[false])
	}
}

func httpRequest(ctx context.Context, method, getUrl string,
	body io.Reader, debug, isZip bool) (*http.Response, error) {
	request, err := http.NewRequest(method, getUrl, body)
	if err != nil {
		log.Errorf("HTTP new request failed, url: %s, error: %v", getUrl, err)
		return nil, err
	}

	request = request.WithContext(ctx)
	configHeader(request, debug, isZip)

	response, err := client.Do(request)
	if err != nil {
		//log.Errorf("HTTP %s request failed, request: %v, error: %v", method, request, err)
		log.Errorf("HTTP %s request failed, request url: %v, error: %v", method, getUrl, err)
		return nil, err
	}
	return response, nil
}

func parseHttpReason(category string, response *http.Response) interface{} {
	var errReason interface{}
	switch category {
	case "bigData":
		errReason = bigDataHttpReasonJson{}
	case "manage":
		errReason = manageHttpReasonJson{}
	default:
		errReason = bigDataHttpReasonJson{}
	}
	bodyByte, _ := ioutil.ReadAll(response.Body)
	_ = json.Unmarshal(bodyByte, &errReason)
	return errReason
}

func encodingBody(body interface{}) ([]byte, error) {
	log.Debugf("HTTP report Body: %+v", body)
	switch body.(type) {
	case string:
		return []byte(body.(string)), nil
	default:
		bytesBody, err := json.Marshal(body)
		if err != nil {
			log.Errorf("HTTP POST Body json encoding error: %v", err)
			return nil, err
		}
		return bytesBody, nil
	}
}

func zipBody(bytesBody []byte, isZip bool) (*bytes.Buffer, error) {
	var reader bytes.Buffer
	if isZip {
		zw := gzip.NewWriter(&reader)

		defer func() {
			err := zw.Close()
			if err != nil {
				log.Errorf("gzip writer close error: %v", err)
			}
		}()

		if _, err := zw.Write(bytesBody); err != nil {
			log.Errorf("Failed to compress HTTP Body, error: %v", err)
			return nil, err
		}
	} else {
		_, err := reader.Write(bytesBody)
		if err != nil {
			log.Errorf("Failed to write HTTP Body to buffer, error: %v", err)
			return nil, err
		}
	}

	return &reader, nil
}

func reportData(
	ctx context.Context,
	path, category string,
	query map[string]string,
	body interface{},
	debug, isZip bool) error {
	bytesBody, err := encodingBody(body)
	if err != nil {
		return err
	}

	reader, err := zipBody(bytesBody, isZip)
	if err != nil {
		return err
	}

	if category == "bigData" {
		machineId := util.GetMachineId()
		timestamp := time.Now().Unix()
		query["machine_id"] = machineId
		query["t"] = strconv.FormatInt(timestamp, 10)
		query["sign"] = urlSign(machineId, timestamp, reader.Bytes())
	}

	fullUrl, err := configQuery(path, category, query, debug)
	if err != nil {
		return err
	}

	response, err := httpRequest(ctx, http.MethodPost, fullUrl, reader, debug, isZip)
	if err != nil {
		return err
	}
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode == 400 || response.StatusCode == 409 {
		errReason := parseHttpReason(category, response)
		log.Errorf("HTTP response status: %v, error: %v", response.Status, errReason)
		return nil
	} else if response.StatusCode <= 200 || response.StatusCode > 300 {
		errReason := parseHttpReason(category, response)
		log.Errorf("HTTP response status: %v, error: %v", response.Status, errReason)
		return fmt.Errorf("HTTP response status: %v, reason: %v", response.Status, errReason)
	} else {
		log.Infof("HTTP response result: %v", response.Status)
	}

	return nil
}

func saveData(detail reportDetail, dataBox *storage.DataBox, saveBucket string) {
	dataBytes, err := json.Marshal(detail)
	if err != nil {
		log.Errorf("Failed to convert report detail to json, err: %v", err)
		return
	}

	err = dataBox.DB.HasBucket(saveBucket)
	if err != nil {
		err = dataBox.DB.AddBucket(saveBucket)
		if err != nil {
			log.Errorf("Add bucket to DB error: %v", err)
			return
		}
	}

	err = dataBox.DB.AddData(saveBucket, time.Duration(time.Now().Unix()), string(dataBytes))
	if err != nil {
		log.Errorf("Add Field to DB error: %v", err)
	}
}

func receiveData(
	ctx context.Context,
	wg *sync.WaitGroup,
	dataBox *storage.DataBox,
	saveBucket string) {
	defer wg.Done()

Loop:
	for {
		select {
		case <-ctx.Done():
			break Loop
		case detail, ok := <-dataChannel:
			if ok {
				err := reportData(ctx, detail.Path, detail.Category,
					detail.Query, detail.Body, detail.Debug, detail.IsZip)
				if err != nil {
					log.Errorf("Failed to report data, error: %v", err)
					saveData(detail, dataBox, saveBucket)
				}
			} else {
				log.Warningf("Reception data channel is closed")
			}
		}
	}
}

func getData(dataBox *storage.DataBox, saveBucket string) (map[string]string, error) {
	dataMap, err := dataBox.DB.AllDataInBucket(saveBucket, "")
	if err != nil {
		//log.Errorf("Get bucket %v data, error: %v", saveBucket, err)
		return nil, err
	}

	if len(dataMap) <= 0 {
		return dataMap, fmt.Errorf("bucket %s is NULL", saveBucket)
	}

	log.Debugf("Bucket %s data: %+v", saveBucket, dataMap)
	return dataMap, nil
}

func retryReport(
	ctx context.Context,
	dataBox *storage.DataBox,
	saveBucket string,
	dataMap map[string]string) {
Loop:
	for tmStr, data := range dataMap {
		log.Debugf("Report data %v, len(data) %d", data, len(data))
		if len(data) == 2 {
			log.Errorf("Report %v is NULL", data)
			continue
		}
		detail := reportDetail{}
		err := json.Unmarshal([]byte(data), &detail)
		if err != nil {
			log.Errorf("Failed to convert json to reportDetail, error: %v", err)
			continue
		}

		err = reportData(ctx, detail.Path, detail.Category,
			detail.Query, detail.Body, detail.Debug, detail.IsZip)
		if err != nil {
			log.Errorf("Retry report data failed, error: %v", err)
		} else {
			tm, err := strconv.ParseInt(tmStr, 10, 64)
			if err != nil {
				log.Errorf("Failed to convert string to timestamp, error:", err)
			} else {
				_ = dataBox.DB.DelData(saveBucket, time.Duration(tm))
			}
		}

		select {
		case <-ctx.Done():
			log.Infof("Process exit, stop retry report data.")
			break Loop
		default:
		}
	}
}

func retryPeriodically(
	ctx context.Context,
	wg *sync.WaitGroup,
	dataBox *storage.DataBox,
	saveBucket string) {
	defer wg.Done()

	ticker := time.NewTicker(time.Minute * 1)
	defer ticker.Stop()

Loop:
	for {
		select {
		case <-ctx.Done():
			break Loop
		case <-ticker.C:
			dataMap, err := getData(dataBox, saveBucket)
			if err == nil {
				retryReport(ctx, dataBox, saveBucket, dataMap)
			}
		}
	}
}

func UploadData(dataJson string, debug bool) {
	var detail reportDetail
	detail.Path = urlMap["dataReport"]
	detail.Category = "bigData"
	detail.Query = make(map[string]string)
	detail.Body = dataJson
	detail.Debug = debug
	detail.IsZip = true
	dataChannel <- detail
}

func StartHTTPReport(
	ctx context.Context,
	wg *sync.WaitGroup,
	dataBox *storage.DataBox,
	saveBucket string) {
	dataChannel = make(chan reportDetail, 10)
	transport := &http.Transport{MaxConnsPerHost: 10}
	client = &http.Client{Transport: transport, Timeout: time.Second * 120}

	wg.Add(2)
	go receiveData(ctx, wg, dataBox, saveBucket)
	go retryPeriodically(ctx, wg, dataBox, saveBucket)
}
