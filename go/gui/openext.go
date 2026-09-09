package gui

// OS handoff for media and links (AyuGram slice 86, rows 134/135/136/267
// + 159 + link opening). In-app streaming playback waits on the engine
// core; until it lands, downloaded media plays through the platform: the
// OS default player for voice/audio/video/documents, the browser for
// tapped links, the file manager for "Show in folder". The decision
// helpers are pure (locked by openext_test.go); the platform layer is
// injected through openExternalAsync/revealAsync so tests never spawn
// processes.

import (
	"errors"
	"path/filepath"
	"strings"
)

// errNoOpener is returned by platforms without an opener (android).
var errNoOpener = errors.New("no system opener on this platform")

// openExternalAsync launches the platform opener for a file or URL and
// reports the outcome through done. Platform files override it in init();
// the shared default fails every call (kept for platforms with no tagged
// file). done must be safe to call from any goroutine — every current
// callback only touches toast helpers, which lock.
var openExternalAsync = func(target string, done func(error)) {
	if done != nil {
		done(errNoOpener)
	}
}

// revealAsync reveals a downloaded file in the platform file manager.
var revealAsync = func(path string, done func(error)) {
	if done != nil {
		done(errNoOpener)
	}
}

// openOnDone marks a media download so its completion auto-opens the
// saved file (the tap expressed play/view intent).
func (a *App) setOpenOnDone(acct, chat, msg string, seq int) {
	a.mu.Lock()
	if a.openOnDone == nil {
		a.openOnDone = make(map[string]bool)
	}
	a.openOnDone[dlKey(acct, chat, msg, seq)] = true
	a.mu.Unlock()
}

// consumeOpenOnDone reports and clears the auto-open mark for a download.
func (a *App) consumeOpenOnDone(acct, chat, msg string, seq int) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.consumeOpenOnDoneLocked(acct, chat, msg, seq)
}

// consumeOpenOnDoneLocked is consumeOpenOnDone for callers holding a.mu.
func (a *App) consumeOpenOnDoneLocked(acct, chat, msg string, seq int) bool {
	if a.openOnDone == nil {
		return false
	}
	k := dlKey(acct, chat, msg, seq)
	v := a.openOnDone[k]
	delete(a.openOnDone, k)
	return v
}

// sanitizeURL admits only http/https/tg links for browser opening —
// anything else (javascript:, file:, bare hosts) falls back to copy.
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

// openArgsFor maps a target (path or URL) to the platform opener command.
// A "" program means the platform has no opener.
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

// revealArgsFor maps a downloaded file to a file-manager reveal command
// (select the file where the platform supports it, open the folder
// otherwise — xdg-open has no select flag).
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

// openMedia hands a completed media file to the system (player/viewer)
// and toasts the outcome honestly.
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

// revealMedia shows a downloaded file in the file manager.
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

// openLinkExternal opens a tapped link — deep links the app can act on
// (invite joins, username resolves, slice 95) route inside; everything
// else opens in the platform browser (AyuGram behavior); platforms or
// schemes without an opener fall back to the slice-34 clipboard copy.
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
