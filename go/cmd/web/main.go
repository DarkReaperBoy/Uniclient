// Command uniclient-web is the desktop host for the Uniclient engine.
//
// It links the bridge in-process (the same code path the c-shared and wasm
// builds expose), wraps the engine in a local HTTP + WebSocket API, and serves
// an embedded web UI. Run it and your browser opens a full chat client — no
// frontend toolchain, no compilation, no install.
//
//	uniclient-web                 # serve UI at http://127.0.0.1:8199
//	uniclient-web -port 9000      # pick a port
//	uniclient-web -dir ~/.config/uniclient
//	uniclient-web -no-browser     # don't auto-open the browser
//
// The server binds 127.0.0.1 only — the chat data never leaves the machine.
// A second launch detects the running instance and just opens the browser.
package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"uniclient/bridge"
)

const defaultPort = 8199

func main() {
	home := defaultHome()
	port := flag.Int("port", defaultPort, "HTTP port (0 = pick a free one)")
	dir := flag.String("dir", home, "config directory (vault + cache + downloads)")
	password := flag.String("password", defaultVaultPassword(), "vault password")
	noBrowser := flag.Bool("no-browser", false, "don't open the browser automatically")
	flag.Parse()

	// Resolve the listen address before touching the engine: if something
	// already serves on this port and it's us, this launch is a duplicate —
	// just open the browser and exit.
	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		if *port == defaultPort && isUniclientRunning(addr) {
			openBrowser("http://" + addr)
			fmt.Printf("Uniclient is already running at http://%s — opened it in your browser.\n", addr)
			return
		}
		// Port busy with something else: fall back to a free port.
		listener, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			log.Fatalf("listen: %v", err)
		}
	}
	url := "http://" + listener.Addr().String()

	// Initialize the engine through the bridge — identical wiring to the
	// FFI hosts (core factory, event pump, session migration).
	if err := bridge.InitEngine(
		*dir,
		filepath.Join(*dir, "cache"),
		filepath.Join(*dir, "downloads"),
		*password,
	); err != nil {
		log.Fatalf("engine init: %v", err)
	}
	eng := bridge.Engine()
	if eng == nil {
		log.Fatal("engine unavailable after init")
	}

	// Reconnect saved accounts (staggered, non-fatal on failure).
	go eng.ConnectAllAccounts()

	srv := newServer(eng, listener)
	httpServer := &http.Server{
		Handler:           srv.routes(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		if err := httpServer.Serve(listener); err != nil && err != http.ErrServerClosed {
			log.Fatalf("http: %v", err)
		}
	}()

	fmt.Printf("Uniclient running at %s\n", url)
	fmt.Printf("Config directory: %s\n", *dir)
	if !*noBrowser {
		openBrowser(url)
	}

	// Wait for Ctrl-C / termination, then save state cleanly.
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig
	fmt.Println("shutting down…")
	_ = eng.Shutdown()
}

// defaultHome mirrors the CLI host: $UNICLIENT_HOME or ~/.uniclient.
func defaultHome() string {
	if v := os.Getenv("UNICLIENT_HOME"); v != "" {
		return v
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

// isUniclientRunning reports whether the address answers our health check.
func isUniclientRunning(addr string) bool {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://" + addr + "/api/health")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// openBrowser launches the default browser cross-platform.
func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", "", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	if err := cmd.Start(); err != nil {
		fmt.Printf("open your browser at %s (couldn't auto-open: %v)\n", url, err)
	}
}
