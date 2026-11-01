//go:build windows

package gui

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/windows/registry"
)

var (
	instanceMu       sync.Mutex
	instanceLn       net.Listener
	instanceLockPath string
	instanceCookie   string
	instanceApp      *App
	instanceBootURI  string
)

func HandleLaunchURI(args []string, configDir string) bool {
	uri := ""
	for _, arg := range args {
		if isLaunchURI(arg) {
			uri = arg
			break
		}
	}
	if uri == "" {
		return false
	}
	if _, _, ok := parseOpenURI(uri); !ok {
		return false
	}
	if forwardOpenURI(configDir, uri) {
		return true
	}
	instanceMu.Lock()
	instanceBootURI = uri
	instanceMu.Unlock()
	return false
}

func (a *App) ServeInstanceCommands(configDir string) {
	instanceMu.Lock()
	instanceApp = a
	instanceMu.Unlock()

	if exe, err := os.Executable(); err == nil {
		if err := registerProtocolHandler(exe); err != nil {
			log.Printf("gui: instance: protocol register: %v", err)
		}
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Printf("gui: instance: listen: %v", err)
		return
	}
	cookie := make([]byte, 8)
	if _, err := rand.Read(cookie); err != nil {
		ln.Close()
		log.Printf("gui: instance: cookie: %v", err)
		return
	}
	lockPath := filepath.Join(configDir, "instance.lock")
	line := fmt.Sprintf("%d %s\n", ln.Addr().(*net.TCPAddr).Port, hex.EncodeToString(cookie))
	tmp := lockPath + ".tmp"
	if err := os.WriteFile(tmp, []byte(line), 0o600); err != nil {
		ln.Close()
		log.Printf("gui: instance: lockfile: %v", err)
		return
	}
	if err := os.Rename(tmp, lockPath); err != nil {
		ln.Close()
		log.Printf("gui: instance: lockfile: %v", err)
		return
	}
	instanceMu.Lock()
	instanceLn = ln
	instanceLockPath = lockPath
	instanceCookie = hex.EncodeToString(cookie)
	instanceMu.Unlock()
	go instanceAcceptLoop(ln)

	if uri := instanceBootURI; uri != "" {
		go routeBootURI(a, uri)
	}
}

func stopInstanceServer() {
	instanceMu.Lock()
	defer instanceMu.Unlock()
	if instanceLn != nil {
		instanceLn.Close()
		instanceLn = nil
	}
	if instanceLockPath != "" {
		os.Remove(instanceLockPath)
		instanceLockPath = ""
	}
	instanceApp = nil
}

func instanceAcceptLoop(ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go instanceServeConn(conn)
	}
}

func instanceServeConn(conn net.Conn) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil && line == "" {
		return
	}
	fields := strings.Fields(strings.TrimSpace(line))
	if len(fields) != 3 || fields[0] != "open" {
		return
	}
	instanceMu.Lock()
	cookie, app := instanceCookie, instanceApp
	instanceMu.Unlock()
	if cookie == "" || app == nil || fields[1] != cookie {
		return
	}
	acc, chat, ok := parseOpenURI(fields[2])
	if !ok {
		return
	}
	notifyOpenAction(app, chatKey{AccountID: acc, ChatID: chat}, "")("")
	conn.Write([]byte("ok\n"))
}

func routeBootURI(a *App, uri string) {
	deadline := time.Now().Add(2 * time.Minute)
	for time.Now().Before(deadline) {
		a.mu.Lock()
		n := len(a.accounts)
		a.mu.Unlock()
		if n > 0 {
			if acc, chat, ok := parseOpenURI(uri); ok {
				notifyOpenAction(a, chatKey{AccountID: acc, ChatID: chat}, "")("")
			}
			return
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func forwardOpenURI(configDir, uri string) bool {
	data, err := os.ReadFile(filepath.Join(configDir, "instance.lock"))
	if err != nil {
		return false
	}
	fields := strings.Fields(string(data))
	if len(fields) != 2 {
		return false
	}
	if _, err := strconv.Atoi(fields[0]); err != nil {
		return false
	}
	conn, err := net.DialTimeout("tcp", "127.0.0.1:"+fields[0], 700*time.Millisecond)
	if err != nil {
		return false
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(2 * time.Second))
	if _, err := fmt.Fprintf(conn, "open %s %s\n", fields[1], uri); err != nil {
		return false
	}
	buf := make([]byte, 64)
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	conn.Read(buf)
	return true
}

func registerProtocolHandler(exe string) error {
	const root = `Software\Classes\` + openURIScheme
	k, _, err := registry.CreateKey(registry.CURRENT_USER, root, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if err := k.SetStringValue("", "URL: Uniclient"); err != nil {
		return err
	}
	if err := k.SetStringValue("URL Protocol", ""); err != nil {
		return err
	}
	icon, _, err := registry.CreateKey(registry.CURRENT_USER, root+`\DefaultIcon`, registry.SET_VALUE)
	if err != nil {
		return err
	}
	if err := icon.SetStringValue("", exe+",0"); err != nil {
		icon.Close()
		return err
	}
	icon.Close()
	cmd, _, err := registry.CreateKey(registry.CURRENT_USER, root+`\shell\open\command`, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer cmd.Close()
	return cmd.SetStringValue("", `"`+exe+`" "%1"`)
}
