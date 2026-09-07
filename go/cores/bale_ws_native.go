//go:build !js

package cores

import (
	"context"
	"net/http"
	"time"

	"github.com/coder/websocket"
)

// baleWSDial connects to the Bale WebSocket endpoint with browser-impersonation
// headers (cookie auth, UA, Origin). Native only — browsers cannot set
// Cookie/User-Agent/Origin headers on a WebSocket handshake.
func baleWSDial(ctx context.Context, url, token string) (*websocket.Conn, error) {
	headers := http.Header{}
	headers.Set("Cookie", "access_token="+token)
	headers.Set("User-Agent", baleUserAgent)
	headers.Set("Origin", "https://web.bale.ai")

	conn, _, err := websocket.Dial(ctx, url, &websocket.DialOptions{
		HTTPClient: newBaleHTTPClient(30 * time.Second),
		HTTPHeader: headers,
	})
	return conn, err
}
