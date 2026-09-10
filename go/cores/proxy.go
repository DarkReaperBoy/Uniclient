package cores

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/gotd/td/telegram/dcs"
	xproxy "golang.org/x/net/proxy"
)

// ProxyConfig describes a connection proxy used to dial Telegram DCs. It mirrors
// AyuGram's MTP::ProxyData (core/core_settings_proxy.h): when Enabled, every DC
// connection is routed through the proxy. The app's mode maps as 0=disabled,
// 1=system, 2=custom — only "custom" (Enabled with a Type+Host+Port) installs a
// resolver; disabled/system fall back to the OS-default direct dialer.
type ProxyConfig struct {
	Enabled  bool
	Type     string // "socks5", "http", "mtproto"
	Host     string
	Port     int
	Username string
	Password string
	Secret   string // MTProto secret, hex-encoded
	IPv6     bool
}

// active reports whether this config should install a custom resolver.
func (p ProxyConfig) active() bool {
	return p.Enabled && p.Host != "" && p.Port > 0 &&
		(p.Type == "socks5" || p.Type == "http" || p.Type == "mtproto")
}

// resolver builds the gotd DC resolver for this proxy, or (nil, nil) when no
// custom routing is needed (disabled/system → default dialer). SOCKS5 and HTTP
// tunnel raw TCP via dcs.Plain+DialFunc; MTProto uses gotd's obfuscated
// dcs.MTProxy transport.
func (p ProxyConfig) resolver() (dcs.Resolver, error) {
	if !p.active() {
		return nil, nil
	}
	addr := net.JoinHostPort(p.Host, strconv.Itoa(p.Port))
	if p.Type == "mtproto" {
		secret, err := hex.DecodeString(strings.TrimSpace(p.Secret))
		if err != nil {
			return nil, fmt.Errorf("mtproto secret: %w", err)
		}
		return dcs.MTProxy(addr, secret, dcs.MTProxyOptions{})
	}
	df, err := p.dialFunc()
	if err != nil {
		return nil, err
	}
	return dcs.Plain(dcs.PlainOptions{Dial: df, PreferIPv6: p.IPv6}), nil
}

// dialFunc builds a dcs.DialFunc that tunnels TCP through a SOCKS5 or HTTP
// CONNECT proxy. MTProto is handled separately (see resolver).
func (p ProxyConfig) dialFunc() (dcs.DialFunc, error) {
	addr := net.JoinHostPort(p.Host, strconv.Itoa(p.Port))
	switch p.Type {
	case "socks5":
		var auth *xproxy.Auth
		if p.Username != "" || p.Password != "" {
			auth = &xproxy.Auth{User: p.Username, Password: p.Password}
		}
		d, err := xproxy.SOCKS5("tcp", addr, auth, xproxy.Direct)
		if err != nil {
			return nil, err
		}
		return func(ctx context.Context, network, target string) (net.Conn, error) {
			if cd, ok := d.(xproxy.ContextDialer); ok {
				return cd.DialContext(ctx, network, target)
			}
			return d.Dial(network, target)
		}, nil
	case "http":
		return httpConnectDialFunc(addr, p.Username, p.Password), nil
	default:
		return nil, fmt.Errorf("unsupported proxy type %q", p.Type)
	}
}

// httpConnectDialFunc returns a DialFunc that opens a tunnel to target through
// an HTTP proxy using the CONNECT method (with optional Basic auth).
func httpConnectDialFunc(proxyAddr, user, pass string) dcs.DialFunc {
	return func(ctx context.Context, network, target string) (net.Conn, error) {
		var d net.Dialer
		conn, err := d.DialContext(ctx, "tcp", proxyAddr)
		if err != nil {
			return nil, err
		}
		req := &http.Request{
			Method: http.MethodConnect,
			URL:    &url.URL{Opaque: target},
			Host:   target,
			Header: make(http.Header),
		}
		if user != "" || pass != "" {
			creds := base64.StdEncoding.EncodeToString([]byte(user + ":" + pass))
			req.Header.Set("Proxy-Authorization", "Basic "+creds)
		}
		if err := req.Write(conn); err != nil {
			conn.Close()
			return nil, err
		}
		br := bufio.NewReader(conn)
		resp, err := http.ReadResponse(br, req)
		if err != nil {
			conn.Close()
			return nil, err
		}
		if resp.StatusCode != http.StatusOK {
			conn.Close()
			return nil, fmt.Errorf("http proxy CONNECT %s: %s", target, resp.Status)
		}
		// The proxy may have pre-buffered tunnel bytes into br alongside the
		// response headers; wrap so they are not lost on subsequent reads.
		if br.Buffered() > 0 {
			return &bufferedConn{Conn: conn, r: br}, nil
		}
		return conn, nil
	}
}

// bufferedConn drains any bytes buffered during the HTTP CONNECT handshake
// before falling through to the raw connection.
type bufferedConn struct {
	net.Conn
	r *bufio.Reader
}

func (c *bufferedConn) Read(p []byte) (int, error) { return c.r.Read(p) }
