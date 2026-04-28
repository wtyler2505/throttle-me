package main

import (
	"context"
	"fmt"
	"log"
	"sync"

	"github.com/imgk/divert-go"
)

// runFilters opens the two WinDivert handles (TTL rewrite + DNS DNAT), spawns
// a goroutine per handle, and blocks until ctx is cancelled. On cancel it shuts
// the handles down and waits for the goroutines to exit, then restores DNS.
func runFilters(ctx context.Context, cfg config) error {
	dnsRestorer, err := applyDNSOverride(cfg)
	if err != nil {
		return fmt.Errorf("apply DNS override: %w", err)
	}
	defer func() {
		if err := dnsRestorer(); err != nil {
			log.Printf("restore DNS: %v", err)
		}
	}()

	ttlHandle, err := divert.Open(
		"outbound and (ip or ipv6) and not loopback",
		divert.LayerNetwork, 10, 0,
	)
	if err != nil {
		return fmt.Errorf("open TTL filter: %w", err)
	}
	defer ttlHandle.Close()

	dnsHandle, err := divert.Open(
		"outbound and (udp.DstPort == 53 or tcp.DstPort == 53) and not loopback",
		divert.LayerNetwork, 20, 0,
	)
	if err != nil {
		return fmt.Errorf("open DNS filter: %w", err)
	}
	defer dnsHandle.Close()

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		if err := runTTLLoop(ctx, ttlHandle, cfg); err != nil {
			log.Printf("TTL loop: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := runDNSLoop(ctx, dnsHandle, cfg); err != nil {
			log.Printf("DNS loop: %v", err)
		}
	}()

	<-ctx.Done()
	// Closing the handles unblocks the Recv calls.
	_ = ttlHandle.Shutdown(divert.ShutdownBoth)
	_ = dnsHandle.Shutdown(divert.ShutdownBoth)
	wg.Wait()
	return nil
}
