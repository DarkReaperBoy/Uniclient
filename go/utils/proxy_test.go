package utils

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestProxyManager_ResolveHost(t *testing.T) {
	pm := NewProxyManager(ProxySettings{
		DNSOverrides: map[string]string{
			"api.telegram.org": "1.2.3.4",
			"example.com":      "5.6.7.8",
		},
	})

	tests := []struct {
		host     string
		expected string
	}{
		{"api.telegram.org", "1.2.3.4"},
		{"example.com", "5.6.7.8"},
		{"unknown.com", "unknown.com"},
	}

	for _, tt := range tests {
		got := pm.ResolveHost(tt.host)
		if got != tt.expected {
			t.Errorf("ResolveHost(%q) = %q, want %q", tt.host, got, tt.expected)
		}
	}
}

func TestProxyManager_UpdateSettings(t *testing.T) {
	pm := NewProxyManager(ProxySettings{Type: ProxyHTTP, Host: "old.proxy"})
	pm.UpdateSettings(ProxySettings{Type: ProxySOCKS5, Host: "new.proxy", Port: "1080"})

	s := pm.Settings()
	if s.Type != ProxySOCKS5 {
		t.Errorf("expected SOCKS5, got %s", s.Type)
	}
	if s.Host != "new.proxy" {
		t.Errorf("expected new.proxy, got %s", s.Host)
	}
}

func TestProxyManager_DirectDial(t *testing.T) {
	// Start a simple TCP echo server
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			conn.Write([]byte("hello"))
			conn.Close()
		}
	}()

	pm := NewProxyManager(ProxySettings{}) // no proxy
	dial := pm.DialContext()
	conn, err := dial(context.Background(), "tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()

	buf := make([]byte, 10)
	n, _ := conn.Read(buf)
	if string(buf[:n]) != "hello" {
		t.Fatalf("expected hello, got %q", string(buf[:n]))
	}
}

func TestProxyManager_DNSOverride_Success(t *testing.T) {
	// Start a server on localhost
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	_, port, _ := net.SplitHostPort(ln.Addr().String())

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			conn.Write([]byte("overridden"))
			conn.Close()
		}
	}()

	pm := NewProxyManager(ProxySettings{
		DNSOverrides: map[string]string{
			"fake.host.invalid": "127.0.0.1",
		},
		DNSFallback: false,
	})

	dial := pm.DialContext()
	conn, err := dial(context.Background(), "tcp", net.JoinHostPort("fake.host.invalid", port))
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()

	buf := make([]byte, 20)
	n, _ := conn.Read(buf)
	if string(buf[:n]) != "overridden" {
		t.Fatalf("expected overridden, got %q", string(buf[:n]))
	}
}

func TestProxyManager_DNSOverride_FailWithFallback(t *testing.T) {
	// Override to a dead IP, but enable fallback
	pm := NewProxyManager(ProxySettings{
		DNSOverrides: map[string]string{
			"localhost": "192.0.2.1", // TEST-NET, won't connect
		},
		DNSFallback: true,
	})

	// Start a server on the real localhost
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	_, port, _ := net.SplitHostPort(ln.Addr().String())

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			conn.Write([]byte("fallback-worked"))
			conn.Close()
		}
	}()

	dial := pm.DialContext()
	// This should fail on 192.0.2.1, then fallback to real DNS for "localhost" → 127.0.0.1
	conn, err := dial(context.Background(), "tcp", net.JoinHostPort("localhost", port))
	if err != nil {
		t.Fatalf("expected fallback to succeed: %v", err)
	}
	defer conn.Close()

	buf := make([]byte, 20)
	n, _ := conn.Read(buf)
	if string(buf[:n]) != "fallback-worked" {
		t.Fatalf("expected fallback-worked, got %q", string(buf[:n]))
	}
}

func TestProxyManager_DNSOverride_FailNoFallback(t *testing.T) {
	pm := NewProxyManager(ProxySettings{
		DNSOverrides: map[string]string{
			"localhost": "192.0.2.1",
		},
		DNSFallback: false,
	})

	dial := pm.DialContext()
	_, err := dial(context.Background(), "tcp", "localhost:99999")
	if err == nil {
		t.Fatal("expected error when override fails and fallback is disabled")
	}
}

func TestProxyManager_HTTPTransport(t *testing.T) {
	// Create a test HTTP server
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	}))
	defer ts.Close()

	pm := NewProxyManager(ProxySettings{}) // no proxy
	client := pm.HTTPClient()
	resp, err := client.Get(ts.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "ok\n" {
		t.Fatalf("expected ok, got %q", string(body))
	}
}

func TestProxyManager_NilDNSOverrides(t *testing.T) {
	// Ensure nil map doesn't panic
	pm := NewProxyManager(ProxySettings{})
	host := pm.ResolveHost("anything.com")
	if host != "anything.com" {
		t.Fatalf("expected anything.com, got %s", host)
	}
}
