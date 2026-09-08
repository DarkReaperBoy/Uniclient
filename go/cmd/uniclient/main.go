// Command uniclient is the Uniclient app: one native Gio GUI, one binary,
// every platform (Linux, Windows, Android; the web build is the same code
// compiled to WASM).
//
// Usage:
//
//	uniclient              # normal launch
//	uniclient -dir PATH    # config directory (default ~/.uniclient)
//	uniclient -password P  # vault password (default UNICLIENT_PASSWORD env or "uniclient")
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"

	"gioui.org/app"
	"gioui.org/op"
	"gioui.org/unit"

	"uniclient/bootstrap"
	"uniclient/gui"
)

func main() {
	home := defaultHome()
	dir := flag.String("dir", home, "config directory (vault + cache + downloads)")
	password := flag.String("password", defaultVaultPassword(), "vault password")
	flag.Parse()

	w := new(app.Window)
	w.Option(
		app.Title("Uniclient"),
		app.Size(unit.Dp(1120), unit.Dp(760)),
		app.MinSize(unit.Dp(360), unit.Dp(480)),
	)

	go func() {
		if err := run(w, *dir, *password); err != nil {
			log.Fatal(err)
		}
	}()
	app.Main()
}

func run(w *app.Window, dir, password string) error {
	// Engine boots off the UI thread; vault+DB init is blocking I/O.
	eng, err := bootstrap.Init(
		dir,
		filepath.Join(dir, "cache"),
		filepath.Join(dir, "downloads"),
		password,
		nil, // events are subscribed by the GUI (it needs its own callback)
	)
	if err != nil {
		return fmt.Errorf("engine init: %w", err)
	}
	defer bootstrap.Shutdown()

	ui := gui.New(w, eng)
	ui.Start()

	var ops op.Ops
	for {
		e := w.Event()
		// The file explorer needs every window event (ViewEvent on mobile).
		ui.ListenEvents(e)
		switch e := e.(type) {
		case app.DestroyEvent:
			return e.Err
		case app.FrameEvent:
			gtx := app.NewContext(&ops, e)
			ui.Root(gtx)
			e.Frame(&ops)
		}
	}
}

func defaultHome() string {
	if v := os.Getenv("UNICLIENT_HOME"); v != "" {
		return v
	}
	if runtime.GOOS == "js" {
		return "/uniclient"
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ".uniclient"
	}
	return filepath.Join(home, ".uniclient")
}

func defaultVaultPassword() string {
	if p := os.Getenv("UNICLIENT_PASSWORD"); p != "" {
		return p
	}
	return "uniclient"
}
