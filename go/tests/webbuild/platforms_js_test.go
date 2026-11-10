//go:build js

package tests

import (
	"reflect"
	"testing"

	. "uniclient/bootstrap"
)

func TestWebPlatformsAreTheConnectableTrio(t *testing.T) {
	got := SupportedPlatforms()
	want := []string{"github", "matrix", "bale"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("the web build offers exactly the browser-connectable platforms (AGENTS.md §7 web truth): got %v, want %v", got, want)
	}
}
