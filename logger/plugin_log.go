package logger

import (
	"fmt"
	"os"
	"path"
	"reflect"
	"sync"
	"time"
	
	"github.com/PPIO/pi-collect/config"
	lua "github.com/yuin/gopher-lua"
	
	rotateLogs "github.com/lestrrat-go/file-rotatelogs"
	log "github.com/sirupsen/logrus"
)

// PluginLoggerPool plugin logger pool instance
var PluginLoggerPool *loggersPool

// LogHandler defines an plugin-related interface for logging.
type LogHandler interface {
	// Errorf logs an error message, patterned after log.Printf.
	Errorf(format string, args ...interface{})
	// Error logs an error message, patterned after log.Print.
	Error(args ...interface{})
	// Debugf logs a debug message, patterned after log.Printf.
	Debugf(format string, args ...interface{})
	// Debug logs a debug message, patterned after log.Print.
	Debug(args ...interface{})
	// Warnf logs a warning message, patterned after log.Printf.
	Warnf(format string, args ...interface{})
	// Warn logs a warning message, patterned after log.Print.
	Warn(args ...interface{})
	// Infof logs an information message, patterned after log.Printf.
	Infof(format string, args ...interface{})
	// Info logs an information message, patterned after log.Print.
	Info(args ...interface{})
}

type converter interface {
	convert(args ...interface{}) []interface{}
	modifyFormat(format string) string
}

// output raw data struct
type raw struct {}

func (r *raw) convert(args ...interface{}) []interface{} {
	return args
}

func (r *raw) modifyFormat(format string) string {
	return format
}

// lua data struct converter
type luaConverter struct {
	fileName   string      // plugin name
	state *lua.LState
}

func (c *luaConverter) setState(state *lua.LState)  {
	c.state = state
}

func (c *luaConverter) setFileName(name string)  {
	c.fileName = name
}

func (c *luaConverter) checkList(value interface{}) bool {
	switch value.(type) {
	case map[interface {}]interface {}:
		for key := range value.(map[interface {}]interface {}) {
			if reflect.ValueOf(key).Kind().String() == "float64" {
				return true
			}
		}
	default:
	}
	return false
}

// marshal  lua data struct convert to go data struct
func (c *luaConverter) marshal(data interface{}) interface{} {
	switch data.(type) {
	case map[interface {}]interface {}:
		if c.checkList(data) {
			list := make([]interface{}, 0)
			for _, value := range data.(map[interface {}]interface {}){
				list = append(list, c.marshal(value))
			}
			return list
		} else {
			dict := make(map[interface{}]interface{})
			for key, value := range data.(map[interface {}]interface {}) {
				dict[c.marshal(key)] = c.marshal(value)
			}
			return dict
		}
	case string:
		return data.(string)
	case float64:
		return data.(float64)
	case bool:
		return data.(bool)
	default:
		if data == nil {
			//log.Warningf("Data is %v", data)
		} else {
			log.Warningf("type \"%T\" unsupported", data)
		}
	}
	return nil
}

func (c *luaConverter) convert(args ...interface{}) []interface{} {
	converted := make([]interface{}, 0, len(args))
	for _, arg := range args {
		//log.Debugf("Lua converter arg: %v, type: \"%T\"", arg, arg)
		converted = append(converted, c.marshal(arg))
	}
	return converted
}

func (c *luaConverter) getDebugInfo() string {
	debugString := fmt.Sprintf("[%s:0 <function>]", c.fileName)
	if reflect.ValueOf(c.state).IsZero() {
		return debugString
	}

	what := "Slunf"
	dbg, ok := c.state.GetStack(1)
	if ok {
		_, err := c.state.GetInfo(what, dbg, lua.LNil)
		if err != nil {
			log.Errorf("Failed to get lua debug info, error: %v", err)
		} else {
			if dbg == nil {
				log.Errorf("Get lua debug info is nil")
			} else {
				debugString = fmt.Sprintf("[%s:%d %s]",
					c.fileName, dbg.CurrentLine, dbg.Name)
			}
		}
	} else {
		log.Error("Failed to get lua stack, debug info is %+v", dbg)
	}
	return debugString
}

func (c *luaConverter) modifyFormat(format string) string {
	debugString := c.getDebugInfo()
	output := fmt.Sprintf("%s %s", format, debugString)
	return output
}

// PluginLogger plugin logger handler and data struct converter
type PluginLogger struct {
	handler   LogHandler  // logger handler
	converter converter   // data struct converter
}

func (logger *PluginLogger) setConverter(converter converter) {
	logger.converter = converter
}

// Errorf logs an error message, patterned after log.Printf.
func (logger *PluginLogger) Errorf(format string, args ...interface{}) {
	modified := logger.converter.modifyFormat(format)
	converted := logger.converter.convert(args...)
	logger.handler.Errorf(modified, converted...)
}

// Error logs an error message, patterned after log.Print.
func (logger *PluginLogger) Error(args ...interface{}) {
	modified := logger.converter.modifyFormat("%s")
	converted := logger.converter.convert(args...)
	logger.handler.Errorf(modified, converted...)
}

// Debugf logs a debug message, patterned after log.Printf.
func (logger *PluginLogger) Debugf(format string, args ...interface{}) {
	modified := logger.converter.modifyFormat(format)
	converted := logger.converter.convert(args...)
	logger.handler.Debugf(modified, converted...)
}

// Debug logs a debug message, patterned after log.Print.
func (logger *PluginLogger) Debug(args ...interface{}) {
	modified := logger.converter.modifyFormat("%s")
	converted := logger.converter.convert(args...)
	logger.handler.Debugf(modified, converted...)
}

// Warnf logs a warning message, patterned after log.Printf.
func (logger *PluginLogger) Warnf(format string, args ...interface{}) {
	modified := logger.converter.modifyFormat(format)
	converted := logger.converter.convert(args...)
	logger.handler.Warnf(modified, converted...)
}

// Warn logs a warning message, patterned after log.Print.
func (logger *PluginLogger) Warn(args ...interface{}) {
	modified := logger.converter.modifyFormat("%s")
	converted := logger.converter.convert(args...)
	logger.handler.Warnf(modified, converted...)
}

// Infof logs an information message, patterned after log.Printf.
func (logger *PluginLogger) Infof(format string, args ...interface{}) {
	modified := logger.converter.modifyFormat(format)
	converted := logger.converter.convert(args...)
	logger.handler.Infof(modified, converted...)
}

// Info logs an information message, patterned after log.Print.
func (logger *PluginLogger) Info(args ...interface{}) {
	modified := logger.converter.modifyFormat("%s")
	converted := logger.converter.convert(args...)
	logger.handler.Infof(modified, converted...)
}

func newPluginLogger(handler LogHandler, converter converter) *PluginLogger {
	return &PluginLogger{
		handler: handler,
		converter: converter,
	}
}

// loggersPool lua plugin log
type loggersPool struct {
	logConfig   config.LogConfig
	pool        map[string]*PluginLogger
	lock        sync.Mutex
}

func (logger *loggersPool) createLogger(
	logPath string,
	logFileName string,
	maxAge int64,
	rotationTime int64,
	level int) (LogHandler, error) {
	var instance = log.New()

	info, err := os.Stat(logPath)
	if err != nil {
		err = os.MkdirAll(logPath, 777)
		if err != nil {
			log.Errorf("Create %s error: %v", logPath, err)
			return nil, err
		}
	} else {
		if info.IsDir() {
			//fmt.Println("Log path is existed")
		} else {
			log.Errorf("%s is not directory", logPath)
			return nil, err
		}
	}

	instance.SetLevel(log.Level(level))
	instance.SetReportCaller(true)
	formatter := &customFormatter{nil}
	formatter.setCreator(&pluginLogTemplate{})
	instance.SetFormatter(formatter)

	baseLogPath := path.Join(logPath, logFileName)
	writer, err := rotateLogs.New(
		baseLogPath+".%Y%m%d%H%M",
		rotateLogs.WithLinkName(baseLogPath),
		rotateLogs.WithMaxAge(time.Duration(maxAge)),
		rotateLogs.WithRotationTime(time.Duration(rotationTime)))
	if err != nil {
		log.Errorf("Config rotation plugin log error: %+v\n", err)
		return nil, err
	}
	instance.SetOutput(writer)

	return instance, nil
}

// Init init loggers pool
func (logger *loggersPool) Init(
	pattern,
	category,
	name string,
	state *lua.LState) *PluginLogger {
	key := fmt.Sprintf("%s_%s_%s", pattern, category, name)
	if _, ok := logger.pool[key]; !ok {
		logBasePath := path.Join(logger.logConfig.LogPath, category, name)
		handler, err := logger.createLogger(
			logBasePath,
			"plugin.log",
			logger.logConfig.LogMaxAge,
			logger.logConfig.LogRotationTime,
			logger.logConfig.LogLevel)
		if err != nil {
			log.Errorf("Can not create %s logger, use default logger", key)
			handler = log.StandardLogger()
		}

		logger.pool[key] = newPluginLogger(handler, &raw{})
		switch pattern {
		case "lua":
			fileName := fmt.Sprintf("%s", name)
			pluginConverter := &luaConverter{}
			pluginConverter.setFileName(fileName)
			pluginConverter.setState(state)
			logger.pool[key].setConverter(pluginConverter)
		default:
			log.Errorf("Plugin type %v unsupported, disable converter")
		}
	}
	return logger.pool[key]
}

// CreatePluginLoggerPool create plugin logger pool
func CreatePluginLoggerPool(logConfig config.LogConfig) {
	//log.Debugf("Log config: %v", logConfig)
	PluginLoggerPool = &loggersPool{
		pool: make(map[string]*PluginLogger, 0),
		logConfig: logConfig,
	}
}
