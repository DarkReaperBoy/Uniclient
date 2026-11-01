package gui

import (
	"net/url"
	"strings"
)

const openURIScheme = "uniclient"

func buildOpenURI(acc, chat string) string {
	return openURIScheme + "://open?acc=" + url.QueryEscape(acc) +
		"&chat=" + url.QueryEscape(chat)
}

func parseOpenURI(uri string) (acc, chat string, ok bool) {
	u := strings.TrimSpace(uri)
	low := strings.ToLower(u)
	if !strings.HasPrefix(low, openURIScheme+"://") {
		return "", "", false
	}
	rest := u[len(openURIScheme)+3:]
	path, query, _ := strings.Cut(rest, "?")
	if !strings.EqualFold(path, "open") {
		return "", "", false
	}
	params := parseQueryPairs(query)
	acc, chat = params["acc"], params["chat"]
	if acc == "" || chat == "" {
		return "", "", false
	}
	if a, err := url.QueryUnescape(acc); err == nil {
		acc = a
	}
	if c, err := url.QueryUnescape(chat); err == nil {
		chat = c
	}
	return acc, chat, true
}

func isLaunchURI(arg string) bool {
	_, _, ok := parseOpenURI(arg)
	return ok
}

func splitNotifyKey(key string) (acc, chat string, ok bool) {
	acc, chat, found := strings.Cut(key, "/")
	if !found || acc == "" || chat == "" {
		return "", "", false
	}
	return acc, chat, true
}
