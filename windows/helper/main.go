// throttle-me-helper — Windows service that mirrors the Linux iptables bypass.
//
// Runs as the ThrottleMeHelper Windows service. While running it:
//   - Rewrites outbound IPv4 TTL / IPv6 hop-limit to a configured value (default 65)
//   - DNATs outbound DNS (port 53, UDP+TCP) to a configured server (default 1.1.1.1)
//   - Sets the active adapter's DNS to the configured server, restoring on stop.
//
// The companion PowerShell CLI (throttle-me.ps1) drives this via Start-Service /
// Stop-Service. All configuration is read from HKLM\SOFTWARE\throttle-me at start.
//
// Build: see build.ps1.
package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"golang.org/x/sys/windows/svc"
)

const serviceName = "ThrottleMeHelper"

func main() {
	debug := flag.Bool("debug", false, "run in foreground (for development)")
	flag.Parse()

	if *debug {
		runDebug()
		return
	}

	isService, err := svc.IsWindowsService()
	if err != nil {
		log.Fatalf("svc.IsWindowsService: %v", err)
	}
	if !isService {
		log.Fatalf("not running as a service; pass -debug for foreground mode")
	}

	if err := svc.Run(serviceName, &handler{}); err != nil {
		log.Fatalf("svc.Run: %v", err)
	}
}

func runDebug() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigCh
		log.Printf("shutdown signal received")
		cancel()
	}()

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("loadConfig: %v", err)
	}
	log.Printf("config: %+v", cfg)
	if err := runFilters(ctx, cfg); err != nil {
		log.Fatalf("runFilters: %v", err)
	}
}
