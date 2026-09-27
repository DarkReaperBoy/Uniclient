package engine

import (
	"path/filepath"
	"strings"
)

// safePathSegment reduces a server-origin ID to ONE path element that
// cannot escape its directory (F-71). Media message IDs are matrix
// event IDs — opaque strings a hostile homeserver fully controls —
// profile-music DocIDs and (at login) the accountID itself are the
// same class; joined RAW into filepath.Join they escape the media dir
// (`Join(dir, "../../x")` → attacker-chosen relative path, then the
// download writes attacker bytes there — §1.10).
//
// Contract: BOTH separators are treated as dividers and only the final
// element is kept; empty / "." / ".." results fall back to "file"
// (the same tri-state sanitizeDownloadName applies to download names).
// Everything else — matrix `$id:domain`, negative telegram IDs, dots
// inside names — is passed through unchanged.
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
