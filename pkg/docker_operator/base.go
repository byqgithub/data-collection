package docker_operator

import (
	"bytes"
	"context"
	"encoding/json"
	"sync"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
	log "github.com/sirupsen/logrus"

	"github.com/PPIO/pi-collect/config"
)

var instance operator

type operator interface {
	create(ctx context.Context)
	close() error

	run(ctx context.Context, wg *sync.WaitGroup)    // events monitor or period polling
	acquireInspect() map[string]types.ContainerJSON // acquire container Inspect
	acquireStats()   map[string]types.Stats         // acquire container Stats
}

type storage struct {
	lock  sync.Mutex
	inspects  map[string]types.ContainerJSON
	stats     map[string]types.Stats

	cli         *client.Client

	duration    time.Duration
}

func (s *storage) containerInspect(
	ctx context.Context,
	containerID string) (types.ContainerJSON, error) {
	info, err := s.cli.ContainerInspect(ctx, containerID)
	if err != nil {
		log.Errorf("Fetch container %v info error: %v", containerID, err)
		return types.ContainerJSON{}, err
	} else {
		//log.Debugf("Fetch container %v info %+v", containerID, info)
		return info, nil
	}
}

func (s *storage) containerStats(
	ctx context.Context,
	containerID string) (types.Stats, error) {
	stats, err := s.cli.ContainerStats(ctx, containerID, false)
	if err != nil {
		log.Errorf("Fetch container %v stats error: %v", containerID, err)
		return types.Stats{}, err
	} else {
		buf := new(bytes.Buffer)
		_, err = buf.ReadFrom(stats.Body)
		if err != nil {
			log.Errorf("Fetch container %v read buffer error: %v", containerID, err)
			return types.Stats{}, err
		}

		var containerStats types.Stats
		err = json.Unmarshal(buf.Bytes(), &containerStats)
		if err != nil {
			log.Errorf("Fetch container %v json unmarshal error: %v", containerID, err)
			return types.Stats{}, err
		}
		//log.Debugf("container %v stats %+v", containerID, sts)
		return containerStats, nil
	}
}

func (s *storage) allContainersInfo(ctx context.Context) error {
	s.lock.Lock()
	defer s.lock.Unlock()

	option := types.ContainerListOptions{
		Filters: filters.NewArgs(),
	}
	option.Filters.Add("status", "running")
	containers, err := s.cli.ContainerList(ctx, option)
	if err != nil {
		log.Errorf("Can not fetch container list, error: %v", err)
		return err
	}

	for _, container := range containers {
		//log.Debugf("Container id %v, fetch inspect", container.ID)
		info, e := s.containerInspect(ctx, container.ID)
		if e == nil {
			s.inspects[container.ID] = info
		}

		stats, e := s.containerStats(ctx, container.ID)
		if e == nil {
			s.stats[container.ID] = stats
		}
	}

	return nil
}

func (s *storage) create(ctx context.Context) {
	var err error

	for i := 0; i < 10; i++ {
		s.cli, err = client.NewClientWithOpts(client.WithAPIVersionNegotiation())
		if err != nil {
			log.Errorf("New docker client error: %v, times %v", err, i)
		} else {
			for j := 0; j <= 10; j++ {
				err = s.allContainersInfo(ctx)
				if err == nil {
					break
				} else if j == 10 {
					log.Errorln("Failed to fetch all containers info, exit operator")
					return
				} else {
					log.Errorf("Retry to fetch all containers info again, times %v", j)
				}
			}

			//wg.Add(2)
			//go storage.receiveEvents(ctx, wg)
			//go storage.eventsDispatcher(ctx, wg)
			break
		}
	}
}

func (s *storage) close() error {
	var err error
	if s.cli != nil {
		err = s.cli.Close()
		if err != nil {
			log.Errorf("Close docker client error: %v", err)
		}
	}
	return err
}

func (s *storage) run(ctx context.Context, wg *sync.WaitGroup) {
}

func (s *storage) acquireInspect() map[string]types.ContainerJSON {
	s.lock.Lock()
	defer s.lock.Unlock()
	if s.inspects != nil {
		return s.inspects
	} else {
		return make(map[string]types.ContainerJSON, 0)
	}
}

func (s *storage) acquireStats() map[string]types.Stats {
	s.lock.Lock()
	defer s.lock.Unlock()
	if s.stats != nil {
		return s.stats
	} else {
		return make(map[string]types.Stats, 0)
	}
}

func selectMethod(method string, conf config.DockerConfig) operator {
	if method == "events" {
		return newEventsStorage(time.Second * time.Duration(conf.EventsUpdate))
	} else if method == "polling" {
		return newPollingStorage(time.Second * time.Duration(conf.PollingPeriod))
	} else {
		log.Errorf("")
		return nil
	}
}

func startDockerOperator(ctx context.Context, wg *sync.WaitGroup) {
	defer wg.Done()
	instance.create(ctx)
	instance.run(ctx, wg)
}

// NewDockerOperator new docker operator
func NewDockerOperator(
	ctx context.Context,
	wg *sync.WaitGroup,
	method string,
	conf config.DockerConfig) {
	instance = selectMethod(method, conf)
	wg.Add(1)
	go startDockerOperator(ctx, wg)
}

// Close close docker api
func Close() {
	_ = instance.close()
}

// ContainersInfo get all containers inspect
func ContainersInfo() string {
	tmp, err := json.Marshal(instance.acquireInspect())
	if err != nil {
		log.Errorf("")
		return ""
	} else {
		return string(tmp)
	}
}

// CollectDockerStats collect all containers stats
func CollectDockerStats() string {
	tmp, err := json.Marshal(instance.acquireStats())
	if err != nil {
		log.Errorf("")
		return ""
	} else {
		return string(tmp)
	}
}

// CollectDockerInspects collect all containers inspect
func CollectDockerInspects() string {
	tmp, err := json.Marshal(instance.acquireInspect())
	if err != nil {
		log.Errorf("")
		return ""
	} else {
		return string(tmp)
	}
}