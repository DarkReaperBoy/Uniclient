//go:build !js

package cores

import (
	"context"
	"net/http"

	"github.com/coder/websocket"
)

// rubikaWSDial connects to the Rubika WebSocket endpoint with
// browser-impersonation headers. Native only — browsers cannot set
// User-Agent/Origin headers on a WebSocket handshake.
func rubikaWSDial(ctx context.Context, url, userAgent string) (*websocket.Conn, error) {
	conn, _, err := websocket.Dial(ctx, url, &websocket.DialOptions{
		HTTPHeader: http.Header{
			"User-Agent": []string{userAgent},
			"Origin":     []string{"https://web.rubika.ir"},
		},
	})
	return conn, err
}
