package docker_operator

import (
	"context"
	"testing"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"

	"github.com/docker/docker/client"
)

func TestCollectDockerInspects(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cli, err := client.NewClientWithOpts(client.WithAPIVersionNegotiation())
	if err != nil {
		t.Fatal("new client error")
	}
	c := NewContainers(cli)
	option := types.ContainerListOptions{Filters: filters.NewArgs()}
	option.Filters.Add("status", "running")
	containers, err := cli.ContainerList(ctx, option)

	if err != nil {
		t.Fatalf("%+v", err)
	}
	for _, container := range containers {
		info, err := c.Inspect(ctx, container.ID)
		if err != nil {
			t.Errorf("%+v", err)
		}
		t.Log(info)
	}

}

func TestCollectDockerStats(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cli, err := client.NewClientWithOpts(client.WithAPIVersionNegotiation())
	if err != nil {
		t.Fatal("new client error")
	}
	c := NewContainers(cli)
	option := types.ContainerListOptions{Filters: filters.NewArgs()}
	option.Filters.Add("status", "running")
	containers, err := cli.ContainerList(ctx, option)

	if err != nil {
		t.Fatalf("%+v", err)
	}

	for _, container := range containers {
		stats, err := c.Stats(ctx, container.ID)
		if err != nil {
			t.Errorf("%+v", err)
		}
		t.Log(container.ID, stats)
	}
}
