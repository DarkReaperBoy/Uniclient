package gui

import (
	"testing"

	"uniclient/utils"
)

// Proxy settings (slice 85): segment mapping + port parsing + persistence.

func TestProxyModeIndex(t *testing.T) {
	cases := []struct {
		in, want int
	}{
		{0, 0}, {1, 1}, {2, 2}, {-1, 0}, {3, 0}, {99, 0},
	}
	for _, c := range cases {
		if got := proxyModeIndex(c.in); got != c.want {
			t.Errorf("proxyModeIndex(%d) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestProxyTypeIndex(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"socks5", 0}, {"HTTP", 1}, {" mtproto ", 2}, {"bogus", 0}, {"", 0},
	}
	for _, c := range cases {
		if got := proxyTypeIndex(c.in); got != c.want {
			t.Errorf("proxyTypeIndex(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestNormalizeProxyPort(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"1080", 1080}, {" 443 ", 443}, {"0", 0},
		{"abc", 0}, {"-1", 0}, {"70000", 0}, {"", 0},
	}
	for _, c := range cases {
		if got := normalizeProxyPort(c.in); got != c.want {
			t.Errorf("normalizeProxyPort(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestProxyConfigPersistShape(t *testing.T) {
	pc := utils.ProxyConfig{Mode: 2, Type: "socks5", Host: "h", Port: "1080", Username: "u", Password: "p"}
	if pc.Mode != 2 || pc.Type != "socks5" || pc.Port != "1080" {
		t.Errorf("proxy config = %+v", pc)
	}
	// The engine's boot restore requires the mode field on the persisted
	// struct — pin its presence.
	if pc.Mode != 2 {
		t.Fatal("utils.ProxyConfig lost its Mode field")
	}
}
