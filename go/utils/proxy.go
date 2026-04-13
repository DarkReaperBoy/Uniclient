package utils

import (
	"context"
	"encoding/base64"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"sync"
	"time"

	"golang.org/x/net/proxy"
)

// ProxyType represents the type of proxy.
type ProxyType string

const (
	ProxyNone   ProxyType = ""
	ProxyHTTP   ProxyType = "http"
	ProxySOCKS5 ProxyType = "socks5"
)

// ProxySettings holds proxy and DNS override configuration.
type ProxySettings struct {
	Type     ProxyType         `json:"type"`
	Host     string            `json:"host"`
	Port     string            `json:"port"`
	Username string            `json:"username,omitempty"`
	Password string            `json:"password,omitempty"`
	DNSOverrides map[string]string `json:"dns_overrides,omitempty"` // domain �� IP
	DNSFallback  bool              `json:"dns_fallback"`            // fallback to real DNS on override failure
}

// ProxyManager manages proxy connections and DNS overrides.
type ProxyManager struct {
	mu       sync.RWMutex
	settings ProxySettings
}

// NewProxyManager creates a new ProxyManager with the given settings.
func NewProxyManager(settings ProxySettings) *ProxyManager {
	if settings.DNSOverrides == nil {
		settings.DNSOverrides = make(map[string]string)
	}
	return &ProxyManager{settings: settings}
}

// UpdateSettings updates the proxy settings.
func (pm *ProxyManager) UpdateSettings(settings ProxySettings) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	if settings.DNSOverrides == nil {
		settings.DNSOverrides = make(map[string]string)
	}
	pm.settings = settings
}

// Settings returns a copy of the current settings.
func (pm *ProxyManager) Settings() ProxySettings {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	return pm.settings
}

// ResolveHost resolves a hostname using DNS overrides if configured.
// Returns the original host if no override exists.
func (pm *ProxyManager) ResolveHost(host string) string {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	if ip, ok := pm.settings.DNSOverrides[host]; ok {
		return ip
	}
	return host
}

// DialContext returns a dial function that routes through proxy and DNS overrides.
func (pm *ProxyManager) DialContext() func(ctx context.Context, network, addr string) (net.Conn, error) {
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		host, port, err := net.SplitHostPort(addr)
		if err != nil {
			return nil, err
		}

		pm.mu.RLock()
		settings := pm.settings
		pm.mu.RUnlock()

		// Try DNS override first
		if overrideIP, ok := settings.DNSOverrides[host]; ok {
			overrideAddr := net.JoinHostPort(overrideIP, port)
			conn, err := pm.dialWithProxy(ctx, network, overrideAddr, settings)
			if err == nil {
				return conn, nil
			}
			// Fallback to real DNS if enabled
			if !settings.DNSFallback {
				return nil, fmt.Errorf("dns override for %s failed (fallback disabled): %w", host, err)
			}
			// Fall through to try real DNS
		}

		return pm.dialWithProxy(ctx, network, addr, settings)
	}
}

func (pm *ProxyManager) dialWithProxy(ctx context.Context, network, addr string, settings ProxySettings) (net.Conn, error) {
	dialer := &net.Dialer{Timeout: 15 * time.Second}

	switch settings.Type {
	case ProxySOCKS5:
		proxyAddr := net.JoinHostPort(settings.Host, settings.Port)
		var auth *proxy.Auth
		if settings.Username != "" {
			auth = &proxy.Auth{
				User:     settings.Username,
				Password: settings.Password,
			}
		}
		socksDialer, err := proxy.SOCKS5(network, proxyAddr, auth, dialer)
		if err != nil {
			return nil, fmt.Errorf("socks5 proxy: %w", err)
		}
		return socksDialer.Dial(network, addr)

	case ProxyHTTP:
		// For HTTP proxy, we connect to the proxy and issue CONNECT
		proxyAddr := net.JoinHostPort(settings.Host, settings.Port)
		conn, err := dialer.DialContext(ctx, "tcp", proxyAddr)
		if err != nil {
			return nil, fmt.Errorf("http proxy connect: %w", err)
		}
		// Send CONNECT request
		connectReq := fmt.Sprintf("CONNECT %s HTTP/1.1\r\nHost: %s\r\n", addr, addr)
		if settings.Username != "" {
			// Basic auth for proxy
			credentials := proxyBase64(settings.Username + ":" + settings.Password)
			connectReq += fmt.Sprintf("Proxy-Authorization: Basic %s\r\n", credentials)
		}
		connectReq += "\r\n"
		if _, err := conn.Write([]byte(connectReq)); err != nil {
			conn.Close()
			return nil, fmt.Errorf("http proxy write: %w", err)
		}
		// Read response (simplified — look for 200)
		buf := make([]byte, 1024)
		n, err := conn.Read(buf)
		if err != nil {
			conn.Close()
			return nil, fmt.Errorf("http proxy read: %w", err)
		}
		response := string(buf[:n])
		if len(response) < 12 || response[9:12] != "200" {
			conn.Close()
			return nil, fmt.Errorf("http proxy rejected: %s", response)
		}
		return conn, nil

	default:
		return dialer.DialContext(ctx, network, addr)
	}
}

// HTTPTransport returns an http.Transport configured with proxy and DNS overrides.
func (pm *ProxyManager) HTTPTransport() *http.Transport {
	transport := &http.Transport{
		DialContext:         pm.DialContext(),
		MaxIdleConns:        100,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 10 * time.Second,
	}

	pm.mu.RLock()
	settings := pm.settings
	pm.mu.RUnlock()

	// For HTTP proxy, also set the Proxy field for non-CONNECT requests
	if settings.Type == ProxyHTTP && settings.Host != "" {
		proxyURL := &url.URL{
			Scheme: "http",
			Host:   net.JoinHostPort(settings.Host, settings.Port),
		}
		if settings.Username != "" {
			proxyURL.User = url.UserPassword(settings.Username, settings.Password)
		}
		transport.Proxy = http.ProxyURL(proxyURL)
	}

	return transport
}

// HTTPClient returns an http.Client configured with proxy and DNS overrides.
func (pm *ProxyManager) HTTPClient() *http.Client {
	return &http.Client{
		Transport: pm.HTTPTransport(),
		Timeout:   30 * time.Second,
	}
}

func proxyBase64(s string) string {
	return base64.StdEncoding.EncodeToString([]byte(s))
}
