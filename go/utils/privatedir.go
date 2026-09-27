package utils

import (
	"os"
	"path/filepath"
)

// PrivateCacheDir resolves a PRIVATE, per-user directory for files that
// used to sit in the SHARED temp dir with predictable names (F-73):
// another local account could pre-create /tmp/uniclient_resend and we
// would write media into THEIR directory, or plant a symlink at a
// predicted path (`iv_photo_%d.jpg`, `dc-backup.json`) so our
// os.Create/WriteFile truncates an attacker-chosen target. The user's
// cache dir is home-owned — no other account can pre-plant there.
//
// Deterministic per name (the Stat-reuse cache sites depend on paths
// surviving across runs, exactly like the old /tmp paths did) and
// 0700. When no home cache exists (sandboxed/CI/js), falls back to an
// UNGUSSABLE per-call temp dir — random beats predictable even when it
// cannot persist.
func PrivateCacheDir(elem ...string) (string, error) {
	if base, err := os.UserCacheDir(); err == nil && base != "" {
		dir := filepath.Join(append([]string{base, "uniclient"}, elem...)...)
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return "", err
		}
		return dir, nil
	}
	root, err := os.MkdirTemp("", "uniclient-*")
	if err != nil {
		return "", err
	}
	dir := filepath.Join(append([]string{root}, elem...)...)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return dir, nil
}
