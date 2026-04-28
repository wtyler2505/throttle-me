package main

import (
	"fmt"
	"net"

	"golang.org/x/sys/windows/registry"
)

const configKey = `SOFTWARE\throttle-me`

type config struct {
	TTL       uint8
	HopLimit  uint8
	DNS       net.IP
	Interface string // adapter alias; empty = auto-detect
}

func loadConfig() (config, error) {
	cfg := config{
		TTL:      65,
		HopLimit: 65,
		DNS:      net.IPv4(1, 1, 1, 1),
	}

	k, err := registry.OpenKey(registry.LOCAL_MACHINE, configKey, registry.QUERY_VALUE)
	if err != nil {
		// Missing key is fine — fall back to defaults.
		if err == registry.ErrNotExist {
			return cfg, nil
		}
		return cfg, fmt.Errorf("open %s: %w", configKey, err)
	}
	defer k.Close()

	if v, _, err := k.GetIntegerValue("TTL"); err == nil && v > 0 && v < 256 {
		cfg.TTL = uint8(v)
	}
	if v, _, err := k.GetIntegerValue("HL"); err == nil && v > 0 && v < 256 {
		cfg.HopLimit = uint8(v)
	}
	if s, _, err := k.GetStringValue("DNS"); err == nil && s != "" {
		if ip := net.ParseIP(s); ip != nil {
			cfg.DNS = ip
		}
	}
	if s, _, err := k.GetStringValue("Interface"); err == nil {
		cfg.Interface = s
	}

	return cfg, nil
}
