//go:build js

package cores

import (
	"context"

	"github.com/coder/websocket"
)

func baleWSDial(ctx context.Context, url, _ string) (*websocket.Conn, error) {
	conn, _, err := websocket.Dial(ctx, url, nil)
	return conn, err
}
