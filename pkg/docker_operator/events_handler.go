package docker_operator

import (
	"context"
	"sync"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/events"
	"github.com/docker/docker/api/types/filters"
	log "github.com/sirupsen/logrus"
)

// 辨别容器运行状态,仅需要关注如下状态
//Status:die
//Status:pause
//Status:start
//Status:stop
//Status:unpause

//type status interface {
//
//}

//var storage *detailStorage

type eventsOperator interface {
	filter(meg events.Message)
	update(ctx context.Context)
	containerInspect(ctx context.Context, containerID string) (types.ContainerJSON, error)
	receiveEvents(ctx context.Context, wg *sync.WaitGroup)
	eventsDispatcher(ctx context.Context, wg *sync.WaitGroup, d time.Duration)
}

type eventsStorage struct {
	base storage
	pausing  map[string]types.ContainerJSON

	cacheLock  sync.Mutex
	cache      map[string][]events.Message

	msgChannel  chan events.Message
}

func (es *eventsStorage) filter(msg events.Message) {
	es.cacheLock.Lock()
	defer es.cacheLock.Unlock()

	if msg.Status == "die" ||
		msg.Status == "stop" ||
		msg.Status == "pause" ||
		msg.Status == "unpause" ||
		msg.Status == "start" {
		if _, ok := es.cache[msg.ID]; !ok {
			es.cache[msg.ID] = make([]events.Message, 0, 10)
		}
		es.cache[msg.ID] = append(es.cache[msg.ID], msg)
		for _, m := range es.cache[msg.ID] {
			log.Debugf("Cache container %v status: %v", msg.ID, m.Status)
		}
	}
}

func (es *eventsStorage) updateStatus(ctx context.Context, dockerId, status string) {
	es.base.lock.Lock()
	defer es.base.lock.Unlock()

	if status == "die" || status == "stop" {
		if _, ok := es.base.inspects[dockerId]; ok {
			log.Debugf("Delete running container %v", dockerId)
			delete(es.base.inspects, dockerId)
		}
		if _, ok := es.pausing[dockerId]; ok {
			log.Debugf("Delete pausing container %v", dockerId)
			delete(es.pausing, dockerId)
		}
	}

	if status == "pause" {
		if _, ok := es.base.inspects[dockerId]; ok {
			if _, in := es.pausing[dockerId]; !in {
				es.pausing[dockerId] = es.base.inspects[dockerId]
			}
			delete(es.base.inspects, dockerId)
		}
		log.Debugf("Move container %v from running to pausing", dockerId)
	}

	if status == "unpause" {
		if _, ok := es.pausing[dockerId]; ok {
			if _, in := es.base.inspects[dockerId]; !in {
				es.base.inspects[dockerId] = es.pausing[dockerId]
			}
			delete(es.pausing, dockerId)
			info, err := es.base.containerInspect(ctx, dockerId)
			if err == nil {
				es.base.inspects[dockerId] = info
			}
		}
		log.Debugf("Move container %v from pausing to running", dockerId)
	}

	if status == "start" {
		info, err := es.base.containerInspect(ctx, dockerId)
		if err == nil {
			es.base.inspects[dockerId] = info
			log.Debugf("Add running container %v info %v", dockerId, info)
		}
		if _, ok := es.pausing[dockerId]; ok {
			log.Debugf("Delete pausing container %v", dockerId)
			delete(es.pausing, dockerId)
		}
	}
}

func (es *eventsStorage) update(ctx context.Context) {
	es.cacheLock.Lock()
	defer es.cacheLock.Unlock()

	for dockerId, eventMsgs := range es.cache {
		var maxTime int64 = 0
		var lastStatus string
		for _, msg := range eventMsgs {
			if msg.TimeNano > maxTime {
				maxTime = msg.TimeNano
				lastStatus = msg.Status
			}
		}
		es.updateStatus(ctx, dockerId, lastStatus)
	}
	es.cache = make(map[string][]events.Message)
}

func (es *eventsStorage) receiveEvents(ctx context.Context, wg *sync.WaitGroup) {
	defer wg.Done()

	option := types.EventsOptions{
		Filters: filters.NewArgs(),
	}
	option.Filters.Add("type", events.ContainerEventType)
	msgs, errs := es.base.cli.Events(ctx, option)
	Loop:
		for {
			select {
			case msg := <- msgs:
				//log.Debugf("receive container event: %v", msg)
				select {
				case es.msgChannel <- msg:
					log.Debugf("Send container event to operator coroutines: %+v", msg)
				default:
					log.Debugf("Can not write any to operator coroutines")
				}
			case err := <- errs:
				log.Errorf("receive error event: %v", err)
				if err == context.Canceled || err == nil {
					log.Debugln("docker error event: context.Canceled, exit loop")
					break Loop
				}
			}
		}
}

func (es *eventsStorage) eventsDispatcher(ctx context.Context, wg *sync.WaitGroup) {
	defer wg.Done()

	ticker := time.NewTicker(es.base.duration)
	defer ticker.Stop()

	Loop:
		for {
			select {
			case <- ctx.Done():
				break Loop
			case msg, ok := <- es.msgChannel:
				if ok {
					es.filter(msg)
				}
			case <- ticker.C:
				es.update(ctx)
			}
		}
}

func (es *eventsStorage) create(ctx context.Context)  {
	es.base.create(ctx)
}

func (es *eventsStorage) close() error {
	var err error
	err = es.base.close()
	close(es.msgChannel)
	return err
}

func (es *eventsStorage) run(ctx context.Context, wg *sync.WaitGroup) {
	wg.Add(2)
	go es.receiveEvents(ctx, wg)
	go es.eventsDispatcher(ctx, wg)
}

func (es *eventsStorage) acquireInspect() map[string]types.ContainerJSON {
	return es.base.acquireInspect()
}

func (es *eventsStorage) acquireStats() map[string]types.Stats {
	return es.base.acquireStats()
}

func newEventsStorage(duration time.Duration) *eventsStorage {
	tmp := eventsStorage{}
	tmp.base.duration = duration
	tmp.cache = make(map[string][]events.Message)
	tmp.base.inspects = make(map[string]types.ContainerJSON)
	tmp.base.stats = make(map[string]types.Stats)
	tmp.pausing = make(map[string]types.ContainerJSON)
	tmp.msgChannel = make(chan events.Message, 10)
	return &tmp
}

//func startDockerOperator(ctx context.Context, wg *sync.WaitGroup) {
//	defer wg.Done()
//
//	for i := 0; i < 10; i++ {
//		cli, err := client.NewClientWithOpts(client.WithAPIVersionNegotiation())
//		if err != nil {
//			log.Errorf("New docker client error: %v, times %v", err, i)
//		} else {
//			storage = newStorage(cli)
//			for j := 0; j <= 10; j++ {
//				err = storage.allInspect(ctx, cli)
//				if err == nil {
//					break
//				} else if j == 10 {
//					log.Errorln("Failed to fetch all containers info, exit operator")
//					return
//				} else {
//					log.Errorf("Retry to fetch all containers info again, times %v", j)
//				}
//			}
//
//			wg.Add(2)
//			go storage.receiveEvents(ctx, wg)
//			go storage.eventsDispatcher(ctx, wg)
//			break
//		}
//	}
//}
