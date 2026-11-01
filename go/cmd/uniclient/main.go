package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"

	"uniclient/bootstrap"
)

func main() {
	home := defaultHome()
	dir := flag.String("dir", home, "config directory (vault + cache + downloads)")
	password := flag.String("password", defaultVaultPassword(), "vault password")
	events := flag.Bool("events", false, "print engine events as JSON lines on stdout")
	flag.Parse()

	eng, err := bootstrap.Init(
		*dir,
		filepath.Join(*dir, "cache"),
		filepath.Join(*dir, "downloads"),
		*password,
		nil,
	)
	if err != nil {
		log.Fatalf("engine init: %v", err)
	}
	defer func() {
		if err := bootstrap.Shutdown(); err != nil {
			log.Printf("engine shutdown: %v", err)
		}
	}()

	if *events {
		sub := eng.Subscribe(func(data []byte) {
			os.Stdout.Write(append(data, '\n'))
		})
		defer sub.Unsubscribe()
	}

	log.Printf("uniclient engine ready (dir %s)", *dir)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig
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
