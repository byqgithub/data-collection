package docker_operator

import (
	"bytes"
	"context"
	"encoding/json"
	"sync"
	"time"

	log "github.com/sirupsen/logrus"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"

	"github.com/docker/docker/client"
)

var cs *Containers
var sts types.Stats

type DockerState struct {
	Id           string  `json:"id"`
	Idx          int64   `json:"idx"`
	Pid          int64   `json:"pid"`
	RunningState string  `json:"running_state"`
	StartedAt    int64   `json:"started_at"`
	CpuUsage     float64 `json:"cpu_usage"`
	MemorySize   int64   `json:"memory_size"`
	MemUsage     float64 `json:"mem_usage"`
}

type Containers struct {
	lock     sync.Mutex
	stats    map[string]types.Stats
	inspects map[string]types.ContainerJSON
	client   *client.Client
}

func (c *Containers) ListContainers(ctx context.Context) error {
	c.lock.Lock()
	defer c.lock.Unlock()
	option := types.ContainerListOptions{Filters: filters.NewArgs()}
	option.Filters.Add("status", "running")

	containers, err := c.client.ContainerList(ctx, option)
	if err != nil {
		return err
	}
	for _, container := range containers {
		info, err := c.Inspect(ctx, container.ID)
		if err != nil {
			log.Errorf("%v", err)
		} else {
			//log.Infof("%s inspects, %v", container.ID, info)
			c.inspects[container.ID] = info
		}
		stats, err := c.Stats(ctx, container.ID)

		if err != nil {
			log.Errorf("%v", err)
		} else {
			//log.Infof("%s stats, %v", container.ID, stats)
			c.stats[container.ID] = stats
		}
	}
	//log.Printf("all container stats %v", c.stats)
	//log.Printf("all container inspect %v", c.inspects)
	return nil
}

func (c *Containers) Inspect(
	ctx context.Context,
	containerID string) (types.ContainerJSON, error) {
	info, err := c.client.ContainerInspect(ctx, containerID)
	if err != nil {
		log.Errorf("inspect container %v info error: %v", containerID, err)
		return types.ContainerJSON{}, err
	} else {
		//log.Debugf("inspect container %v info %+v", containerID, info)
		return info, nil
	}
}

func (c *Containers) Stats(
	ctx context.Context,
	containerID string) (types.Stats, error) {
	stats, err := c.client.ContainerStats(ctx, containerID, false)
	if err != nil {
		log.Errorf("container %v stats error: %v", containerID, err)
		return types.Stats{}, err
	} else {
		buf := new(bytes.Buffer)
		buf.ReadFrom(stats.Body)
		err = json.Unmarshal(buf.Bytes(), &sts)
		if err != nil {
			return types.Stats{}, err
		}
		//log.Debugf("container %v stats %+v", containerID, sts)
		return sts, nil
	}
}

func NewContainers(cli *client.Client) *Containers {
	return &Containers{
		client:   cli,
		stats:    make(map[string]types.Stats, 0),
		inspects: make(map[string]types.ContainerJSON, 0),
	}
}

func NewCient(ctx context.Context) {
	for i := 0; i < 3; i++ {
		cli, err := client.NewClientWithOpts(client.WithAPIVersionNegotiation())
		if err != nil {
			log.Errorf("connect docker client error: %v, times %v", err, i)
		} else {
			cs = NewContainers(cli)
			for j := 0; j <= 3; j++ {
				err = cs.ListContainers(ctx)
				if err == nil {
					break
				} else if j == 3 {
					log.Errorln("fetch all containers info failed, exit collect")
					return
				} else {
					log.Errorf("fetch all containers info again, times %v", j)
				}
			}

			break
		}
	}
}

func startDockerCollect(ctx context.Context, wg *sync.WaitGroup) {
	defer wg.Done()
	ticker := time.NewTicker(time.Second * 10)

	for {
		select {
		case <-ticker.C:
			NewCient(ctx)
		case <-ctx.Done():
			return
		}
	}

}

func NewDockerCollect(ctx context.Context, wg *sync.WaitGroup) {
	wg.Add(1)
	go startDockerCollect(ctx, wg)
}

//func CollectDockerStats() string {
//	cs.lock.Lock()
//	defer cs.lock.Unlock()
//
//	tmp, err := json.Marshal(cs.stats)
//	if err != nil {
//		log.Errorf("Collect docker statts error: %v", err)
//		return ""
//	} else {
//		return string(tmp)
//	}
//}
//
//func CollectDockerInspects() string {
//	cs.lock.Lock()
//	defer cs.lock.Unlock()
//
//	tmp, err := json.Marshal(cs.inspects)
//	if err != nil {
//		log.Errorf("Collect docker inspects error: %v", err)
//		return ""
//	} else {
//		return string(tmp)
//	}
//}
