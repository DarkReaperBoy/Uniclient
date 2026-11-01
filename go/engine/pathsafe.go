package engine

import (
	"path/filepath"
	"strings"
)

func safePathSegment(s string) string {
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, `\`, "/")
	s = strings.Trim(s, "/")
	s = filepath.Base(s)
	if s == "" || s == "." || s == ".." {
		return "file"
	}
	return s
}
