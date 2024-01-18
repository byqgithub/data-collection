package executor

import (
	"time"

	//log "github.com/sirupsen/logrus"
)

type Ticker struct {
	interval  int64
	ticker    *time.Ticker
	//timeRange []time.Duration
}

func (t *Ticker) generateTimeRange(interval int64) []time.Duration {
	now := time.Now().Truncate(time.Second * time.Duration(interval))
	lowerLimit := time.Duration(now.Add(-1 * time.Second * time.Duration(interval)).Unix())
	upperLimit := time.Duration(now.Add(time.Second * time.Duration(interval)).Unix())
	return []time.Duration{lowerLimit, upperLimit}
}

func (t *Ticker) Start()  {
	t.ticker = time.NewTicker(time.Second * time.Duration(t.interval))
}

func (t *Ticker) Close() {
	if t.ticker != nil {
		t.ticker.Stop()
	}
}

func NewTicker(interval int64) Ticker {
	return Ticker{
		interval: interval,
		//timeRange: make([]time.Duration, 0, 2),
	}
}
