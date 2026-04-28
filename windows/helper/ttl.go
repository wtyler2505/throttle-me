package main

import (
	"context"
	"errors"
	"io"

	"github.com/imgk/divert-go"
)

const mtu = 0xFFFF

// runTTLLoop reads outbound packets, rewrites IPv4.TTL or IPv6.HopLimit to the
// configured value, recomputes checksums, and reinjects.
func runTTLLoop(ctx context.Context, h *divert.Handle, cfg config) error {
	buf := make([]byte, mtu)
	addr := new(divert.Address)

	for {
		if ctx.Err() != nil {
			return nil
		}
		n, err := h.Recv(buf, addr)
		if err != nil {
			if errors.Is(err, io.EOF) || ctx.Err() != nil {
				return nil
			}
			return err
		}

		pkt := buf[:n]
		// rewriteTTL returns false for non-IP packets; we still pass them
		// through unchanged below.
		_ = rewriteTTL(pkt, cfg.TTL, cfg.HopLimit)

		// CalcChecksums returns bool; failure is non-fatal — reinject anyway.
		_ = divert.CalcChecksums(pkt, addr, 0)
		if _, err := h.Send(pkt, addr); err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
	}
}

// rewriteTTL detects IP version from the first nibble and rewrites the
// appropriate field. Returns true if a rewrite happened.
func rewriteTTL(pkt []byte, ttl, hopLimit uint8) bool {
	if len(pkt) < 1 {
		return false
	}
	switch pkt[0] >> 4 {
	case 4:
		if len(pkt) < 20 {
			return false
		}
		pkt[8] = ttl
		return true
	case 6:
		if len(pkt) < 40 {
			return false
		}
		pkt[7] = hopLimit
		return true
	}
	return false
}
