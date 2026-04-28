package main

import (
	"context"
	"errors"
	"io"
	"net"

	"github.com/imgk/divert-go"
)

// runDNSLoop intercepts outbound port-53 traffic and rewrites the destination
// IP to cfg.DNS. WinDivert recomputes checksums via CalcChecksums.
//
// Note: this is a unidirectional rewrite. Replies come back from the new DNS
// server's IP, not the original. Most stub resolvers accept this because the
// transaction ID matches; the few that don't (some hardened DoH-fallback
// stacks) won't be helped by a Linux iptables-style port-53 DNAT either.
func runDNSLoop(ctx context.Context, h *divert.Handle, cfg config) error {
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
		rewriteDNSDest(pkt, cfg.DNS)

		// CalcChecksums returns bool; failure is non-fatal.
		_ = divert.CalcChecksums(pkt, addr, 0)
		if _, err := h.Send(pkt, addr); err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
	}
}

// rewriteDNSDest replaces the destination IP of an IPv4 or IPv6 packet that
// targets port 53. Checksum recalculation is delegated to WinDivert.
func rewriteDNSDest(pkt []byte, dst net.IP) {
	if len(pkt) < 1 {
		return
	}
	switch pkt[0] >> 4 {
	case 4:
		ipv4 := dst.To4()
		if ipv4 == nil {
			return
		}
		if len(pkt) < 20 {
			return
		}
		copy(pkt[16:20], ipv4)
	case 6:
		ipv6 := dst.To16()
		if ipv6 == nil || dst.To4() != nil {
			return
		}
		if len(pkt) < 40 {
			return
		}
		copy(pkt[24:40], ipv6)
	}
}
