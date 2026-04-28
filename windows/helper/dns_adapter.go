package main

import (
	"fmt"
	"os/exec"
	"strings"
)

// applyDNSOverride sets the configured DNS server on the active adapter via
// `netsh interface ipv4 set dnsservers`. Returns a closure that restores the
// previous DNS configuration to DHCP (or whatever was there before — we capture
// it best-effort with `netsh interface ipv4 show dnsservers`).
func applyDNSOverride(cfg config) (func() error, error) {
	iface := cfg.Interface
	if iface == "" {
		var err error
		iface, err = activeAdapterAlias()
		if err != nil {
			return nil, fmt.Errorf("detect active adapter: %w", err)
		}
	}

	prev, err := captureDNS(iface)
	if err != nil {
		// Non-fatal: still set new DNS, restore will revert to DHCP.
		prev = nil
	}

	if err := netsh("interface", "ipv4", "set", "dnsservers",
		fmt.Sprintf("name=%s", iface), "static", cfg.DNS.String(), "primary",
		"validate=no"); err != nil {
		return nil, fmt.Errorf("set DNS: %w", err)
	}

	return func() error {
		if len(prev) == 0 {
			return netsh("interface", "ipv4", "set", "dnsservers",
				fmt.Sprintf("name=%s", iface), "dhcp")
		}
		// Restore the first server as primary, the rest as secondaries.
		if err := netsh("interface", "ipv4", "set", "dnsservers",
			fmt.Sprintf("name=%s", iface), "static", prev[0], "primary",
			"validate=no"); err != nil {
			return err
		}
		for i, s := range prev[1:] {
			if err := netsh("interface", "ipv4", "add", "dnsservers",
				fmt.Sprintf("name=%s", iface), s,
				fmt.Sprintf("index=%d", i+2), "validate=no"); err != nil {
				return err
			}
		}
		return nil
	}, nil
}

// activeAdapterAlias picks the first connected adapter from
// `netsh interface show interface`.
func activeAdapterAlias() (string, error) {
	out, err := exec.Command("netsh", "interface", "show", "interface").Output()
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}
		if fields[0] == "Enabled" && fields[1] == "Connected" {
			return strings.Join(fields[3:], " "), nil
		}
	}
	return "", fmt.Errorf("no connected adapter found")
}

// captureDNS reads the current DNS servers for an adapter via
// `netsh interface ipv4 show dnsservers name=<iface>`.
func captureDNS(iface string) ([]string, error) {
	out, err := exec.Command("netsh", "interface", "ipv4", "show", "dnsservers",
		fmt.Sprintf("name=%s", iface)).Output()
	if err != nil {
		return nil, err
	}
	var servers []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		// Lines like "Statically Configured DNS Servers:  1.2.3.4" or
		// continuation lines that are bare IPs.
		if idx := strings.Index(line, ":"); idx >= 0 {
			line = strings.TrimSpace(line[idx+1:])
		}
		if isIPv4(line) {
			servers = append(servers, line)
		}
	}
	return servers, nil
}

func isIPv4(s string) bool {
	parts := strings.Split(s, ".")
	if len(parts) != 4 {
		return false
	}
	for _, p := range parts {
		if len(p) == 0 || len(p) > 3 {
			return false
		}
		for _, c := range p {
			if c < '0' || c > '9' {
				return false
			}
		}
	}
	return true
}

func netsh(args ...string) error {
	out, err := exec.Command("netsh", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("netsh %v: %w (%s)", args, err, strings.TrimSpace(string(out)))
	}
	return nil
}
