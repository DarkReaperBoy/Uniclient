package gui

import (
	"errors"
	"path/filepath"
	"strings"

	"uniclient/engine"
)

var errNoOpener = errors.New("no system opener on this platform")

var openExternalAsync = func(target string, done func(error)) {
	if done != nil {
		done(errNoOpener)
	}
}

var revealAsync = func(path string, done func(error)) {
	if done != nil {
		done(errNoOpener)
	}
}

func (a *App) setOpenOnDone(acct, chat, msg string, seq int) {
	a.mu.Lock()
	if a.openOnDone == nil {
		a.openOnDone = make(map[string]bool)
	}
	a.openOnDone[dlKey(acct, chat, msg, seq)] = true
	a.mu.Unlock()
}

func (a *App) consumeOpenOnDone(acct, chat, msg string, seq int) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.consumeOpenOnDoneLocked(acct, chat, msg, seq)
}

func (a *App) consumeOpenOnDoneLocked(acct, chat, msg string, seq int) bool {
	if a.openOnDone == nil {
		return false
	}
	k := dlKey(acct, chat, msg, seq)
	v := a.openOnDone[k]
	delete(a.openOnDone, k)
	return v
}

func (a *App) setSaveOnDone(acct, chat, msg string, seq int) {
	a.mu.Lock()
	if a.saveOnDone == nil {
		a.saveOnDone = make(map[string]bool)
	}
	a.saveOnDone[dlKey(acct, chat, msg, seq)] = true
	a.mu.Unlock()
}

func (a *App) consumeSaveOnDoneLocked(acct, chat, msg string, seq int) bool {
	if a.saveOnDone == nil {
		return false
	}
	k := dlKey(acct, chat, msg, seq)
	v := a.saveOnDone[k]
	delete(a.saveOnDone, k)
	return v
}

func (a *App) saveMediaToDownloads(acct, chat, msg string, seq int) {
	go func() {
		dest, err := a.eng.SaveMessageMediaToDownloads(acct, chat, msg, seq)
		switch {
		case err == nil:
			a.setToast("Saved to " + dest)
			revealAsync(dest, func(rerr error) {
				if rerr != nil {
					return
				}
				a.setToast("Saved to Downloads")
			})
		case errors.Is(err, engine.ErrMediaNotDownloaded):
			a.setSaveOnDone(acct, chat, msg, seq)
			if derr := a.eng.RequestDownload(acct, chat, msg, seq, 0); derr != nil {
				a.setToast("Download failed: " + derr.Error())
				return
			}
			a.setToast("Downloading…")
		default:
			a.setToast("Save failed: " + err.Error())
		}
	}()
}

func saveToDownloadsMenuGate(m engine.CachedMessage) bool {
	return m.HasMedia && !m.IsService
}

func sanitizeURL(u string) (string, bool) {
	u = strings.TrimSpace(u)
	if u == "" {
		return "", false
	}
	low := strings.ToLower(u)
	if strings.HasPrefix(low, "http://") || strings.HasPrefix(low, "https://") || strings.HasPrefix(low, "tg://") {
		return u, true
	}
	return "", false
}

func openArgsFor(goos, target string) (string, []string) {
	switch goos {
	case "linux":
		return "xdg-open", []string{target}
	case "darwin":
		return "open", []string{target}
	case "windows":
		return "rundll32", []string{"url.dll,FileProtocolHandler", target}
	}
	return "", nil
}

func revealArgsFor(goos, path string) (string, []string) {
	switch goos {
	case "linux":
		return "xdg-open", []string{filepath.Dir(path)}
	case "darwin":
		return "open", []string{"-R", path}
	case "windows":
		return "explorer", []string{"/select," + path}
	}
	return "", nil
}

func (a *App) openMedia(path string, playing bool) {
	if path == "" {
		return
	}
	openExternalAsync(path, func(err error) {
		switch {
		case err != nil:
			a.setToast("Open failed: " + err.Error())
		case playing:
			a.setToast("Playing in system player")
		default:
			a.setToast("Opened in system viewer")
		}
	})
}

func (a *App) revealMedia(path string) {
	if path == "" {
		return
	}
	revealAsync(path, func(err error) {
		if err != nil {
			a.setToast("Reveal failed: " + err.Error())
			return
		}
		a.setToast("Revealed in file manager")
	})
}

func (a *App) openLinkExternal(url string) {
	if a.tryDeepLink(url) {
		return
	}
	if u, ok := sanitizeURL(url); ok {
		openExternalAsync(u, func(err error) {
			if err == nil {
				a.setToast("Opened in browser")
			} else {
				a.copyTextSoon(url)
			}
		})
		return
	}
	a.copyTextSoon(url)
}
