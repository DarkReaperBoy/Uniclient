package main

import (
	"context"
	"embed"
	"io"
	"io/fs"
	"net/http"
	"strings"
	"time"

	"rsc.io/qr"
)

// webFS holds the embedded UI: plain HTML/CSS/JS, no build toolchain.
//
//go:embed web
var webFS embed.FS

// handleStatic serves the embedded web UI.
func handleStatic(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/")
	if name == "" {
		name = "index.html"
	}
	data, err := webFS.ReadFile("web/" + name)
	if err != nil {
		// SPA-style fallback: unknown paths get the app shell.
		if data, err = webFS.ReadFile("web/index.html"); err != nil {
			http.NotFound(w, r)
			return
		}
		name = "index.html"
	}

	switch {
	case strings.HasSuffix(name, ".html"):
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
	case strings.HasSuffix(name, ".js"):
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	case strings.HasSuffix(name, ".css"):
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	case strings.HasSuffix(name, ".svg"):
		w.Header().Set("Content-Type", "image/svg+xml")
	default:
		w.Header().Set("Content-Type", "application/octet-stream")
	}
	w.Header().Set("Cache-Control", "no-cache")
	_, _ = w.Write(data)
}

// writePNGWithMargin renders the QR code as PNG (the library adds the quiet
// zone required by scanners).
func writePNGWithMargin(w io.Writer, code *qr.Code) error {
	_, err := w.Write(code.PNG())
	return err
}

// ensure embed.FS satisfies fs.FS (compile-time check).
var _ fs.FS = webFS

// writeTimeout bounds each WS frame write.
func writeTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, 10*time.Second)
}

// readTimeout bounds idle WS reads; the browser reconnects automatically.
func readTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, 24*time.Hour)
}
