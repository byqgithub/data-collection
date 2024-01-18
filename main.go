package main

import (
	"github.com/PPIO/pi-collect/cmd"
	log "github.com/sirupsen/logrus"
)

func main() {
	cmd.ParseOpt()

	defer func() {
		if err := recover(); err != nil {
			log.Errorf("Main panic %v", err)
		}
	}()

	if err := cmd.RootCmd.Execute(); err != nil {
		log.Fatalf("Collect running error: %v", err)
	}
}
