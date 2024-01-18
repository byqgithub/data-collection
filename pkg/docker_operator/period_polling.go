package docker_operator

import (
	"context"
	"sync"
	"time"

	"github.com/docker/docker/api/types"
	//"github.com/docker/docker/api/types/events"
	//"github.com/docker/docker/api/types/filters"
	//"github.com/docker/docker/client"
	//log "github.com/sirupsen/logrus"
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

type pollingOperator interface {
	poll(ctx context.Context, wg *sync.WaitGroup)
}

type pollingStorage struct {
	base storage
}

func (ps *pollingStorage) poll(ctx context.Context, wg *sync.WaitGroup) {
	defer wg.Done()

	ticker := time.NewTicker(ps.base.duration)
	defer ticker.Stop()

Loop:
	for {
		select {
		case <-ctx.Done():
			break Loop
		case <-ticker.C:
			_ = ps.base.allContainersInfo(ctx)
		}
	}
}

func (ps *pollingStorage) create(ctx context.Context) {
	ps.base.create(ctx)
}

func (ps *pollingStorage) close() error {
	var err error
	err = ps.base.close()
	return err
}

func (ps *pollingStorage) run(ctx context.Context, wg *sync.WaitGroup) {
	wg.Add(1)
	go ps.poll(ctx, wg)
}

func (ps *pollingStorage) acquireInspect() map[string]types.ContainerJSON {
	return ps.base.acquireInspect()
}

func (ps *pollingStorage) acquireStats() map[string]types.Stats {
	return ps.base.acquireStats()
}

func newPollingStorage(duration time.Duration) *pollingStorage {
	return &pollingStorage{
		base: storage{
			inspects: make(map[string]types.ContainerJSON),
			stats:    make(map[string]types.Stats),
			duration: duration},
	}
}
