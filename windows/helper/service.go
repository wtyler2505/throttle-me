package main

import (
	"context"
	"log"

	"golang.org/x/sys/windows/svc"
)

type handler struct{}

func (h *handler) Execute(args []string, r <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	const accepted = svc.AcceptStop | svc.AcceptShutdown

	status <- svc.Status{State: svc.StartPending}

	cfg, err := loadConfig()
	if err != nil {
		log.Printf("loadConfig: %v", err)
		return false, 1
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	errCh := make(chan error, 1)
	go func() { errCh <- runFilters(ctx, cfg) }()

	status <- svc.Status{State: svc.Running, Accepts: accepted}

loop:
	for {
		select {
		case req := <-r:
			switch req.Cmd {
			case svc.Interrogate:
				status <- req.CurrentStatus
			case svc.Stop, svc.Shutdown:
				break loop
			default:
				log.Printf("unexpected control: %v", req.Cmd)
			}
		case err := <-errCh:
			if err != nil {
				log.Printf("runFilters: %v", err)
			}
			break loop
		}
	}

	status <- svc.Status{State: svc.StopPending}
	cancel()
	<-errCh
	status <- svc.Status{State: svc.Stopped}
	return false, 0
}
