package logger

import (
	"bytes"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"time"

	rotateLogs "github.com/lestrrat-go/file-rotatelogs"
	//lfShook "github.com/rifflock/lfshook"
	log "github.com/sirupsen/logrus"
)

type templateCreator interface {
	template(entry *log.Entry) string
}

type frameworkLogTemplate struct {}

func (f *frameworkLogTemplate) template(entry *log.Entry) string {
	timestamp := entry.Time.Format("2006-01-02 15:04:05")
	var newLog string
	if entry.HasCaller() {
		fileName := filepath.Base(entry.Caller.File)
		newLog = fmt.Sprintf("[%s] [%s] %s [%s:%d %s]\n",
			timestamp, entry.Level, entry.Message,
			fileName, entry.Caller.Line, entry.Caller.Function)
	} else {
		newLog = fmt.Sprintf("[%s] [%s] %s\n", timestamp, entry.Level, entry.Message)
	}

	return newLog
}

type pluginLogTemplate struct {}

func (p *pluginLogTemplate) template(entry *log.Entry) string {
	timestamp := entry.Time.Format("2006-01-02 15:04:05")
	newLog := fmt.Sprintf("[%s] [%s] %s\n", timestamp, entry.Level, entry.Message)
	return newLog
}

// customFormatter custom log format
type customFormatter struct {
	creator templateCreator
}

// SetCreator set log template creator
func (cf *customFormatter) setCreator(creator templateCreator) {
	cf.creator = creator
}

// Format log format
func (cf *customFormatter) Format(entry *log.Entry) ([]byte, error) {
	var b *bytes.Buffer
	if entry.Buffer != nil {
		b = entry.Buffer
	} else {
		b = &bytes.Buffer{}
	}

	//timestamp := entry.Time.Format("2006-01-02 15:04:05")
	//var newLog string
	//if entry.HasCaller() {
	//	fileName := filepath.Base(entry.Caller.File)
	//	newLog = fmt.Sprintf("[%s] [%s] %s [%s:%d %s]\n",
	//		timestamp, entry.Level, entry.Message,
	//		fileName, entry.Caller.Line, entry.Caller.Function)
	//} else {
	//	newLog = fmt.Sprintf("[%s] [%s] %s\n", timestamp, entry.Level, entry.Message)
	//}
	newLog := cf.creator.template(entry)
	b.WriteString(newLog)

	return b.Bytes(), nil
}

// InitLog init framework log
 func InitLog(
	logPath string,
	logFileName string,
	maxAge int64,
	rotationTime int64,
	level int) {
	//if Logger != nil {
	//	return
	//}

	info, err := os.Stat(logPath)
	if err != nil {
		err = os.MkdirAll(logPath, 777)
		if err != nil {
			panic(fmt.Errorf("make dir error: %v", err))
		}
	} else {
		if info.IsDir() {
			//fmt.Println("Log path is existed")
		} else {
			panic(fmt.Errorf("%s is not directory", logPath))
		}
	}

	baseLogPath := path.Join(logPath, logFileName)
	writer, err := rotateLogs.New(
		baseLogPath+".%Y%m%d%H%M",
		rotateLogs.WithLinkName(baseLogPath),
		rotateLogs.WithMaxAge(time.Duration(maxAge)),
		rotateLogs.WithRotationTime(time.Duration(rotationTime)))
	if err != nil {
		fmt.Printf("Config rotation log error: %+v\n", err)
	}

	log.SetLevel(log.Level(level))
	//log.SetReportCaller(true)
	//hookMap := lfShook.WriterMap{
	//	log.TraceLevel: writer,
	//	log.DebugLevel: writer,
	//	log.InfoLevel: writer,
	//	log.WarnLevel: writer,
	//	log.ErrorLevel: writer,
	//	log.FatalLevel: writer,
	//	log.PanicLevel: writer,
	//}
	//lfHook := lfShook.NewHook(hookMap, &log.TextFormatter{})
	//lfHook.SetFormatter(&log.TextFormatter{
	//	ForceColors: true,
	//	FullTimestamp: true,
	//	TimestampFormat: "2006-01-02 15:04:05"})
	//log.AddHook(lfHook)
	log.SetOutput(writer)
	log.SetReportCaller(true)
	formatter := &customFormatter{nil}
	formatter.setCreator(&frameworkLogTemplate{})
	log.SetFormatter(formatter)
	//Logger = log.StandardLogger()
}
