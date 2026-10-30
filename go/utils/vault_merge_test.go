package utils

import (
	"encoding/json"
	"testing"
)

func raw(s string) json.RawMessage { return json.RawMessage(s) }

// TestMergeVaultDataAdoptsForeignKeys pins the two-tab merge used by the js
// vault flush (risk R1): bucket/keys another instance wrote are adopted, this
// instance's own entries win key-level conflicts, and foreign maps with
// foreign buckets the local image never saw survive intact.
func TestMergeVaultDataAdoptsForeignKeys(t *testing.T) {
	ours := map[string]map[string]json.RawMessage{
		"__accounts": {"tele_1": raw(`{"platform":"telegram"}`)},
		"config":     {"theme": raw(`{"dark":true}`)},
	}
	foreign := map[string]map[string]json.RawMessage{
		"__accounts": {
			"tele_1": raw(`{"platform":"FOREIGN-TELEGRAM"}`), // conflict: ours must win
			"tele_2": raw(`{"platform":"telegram"}`),         // theirs only: must adopt
		},
		"sessions": {"acc9": raw(`{"key":"x"}`)}, // bucket ours never had: must adopt
	}
	mergeVaultData(ours, foreign)

	if got := string(ours["__accounts"]["tele_1"]); got != `{"platform":"telegram"}` {
		t.Errorf("key-level conflict: ours must win, got %s", got)
	}
	if got := string(ours["__accounts"]["tele_2"]); got != `{"platform":"telegram"}` {
		t.Errorf("foreign-only key must be adopted, got %q", got)
	}
	if got := string(ours["sessions"]["acc9"]); got != `{"key":"x"}` {
		t.Errorf("foreign-only bucket must be adopted, got %q", got)
	}
	if got := string(ours["config"]["theme"]); got != `{"dark":true}` {
		t.Errorf("untouched local bucket must be intact, got %q", got)
	}
}

// TestMergeVaultDataEmptyAndNil: nil/empty foreign is a no-op, and ours is
// usable even when it is fresh/empty (CreateVault path merges too).
func TestMergeVaultDataEmptyAndNil(t *testing.T) {
	ours := map[string]map[string]json.RawMessage{"config": {"theme": raw(`1`)}}
	mergeVaultData(ours, nil)
	mergeVaultData(ours, map[string]map[string]json.RawMessage{})
	if len(ours) != 1 || string(ours["config"]["theme"]) != "1" {
		t.Errorf("nil/empty foreign must be a no-op, got %v", ours)
	}

	fresh := map[string]map[string]json.RawMessage{}
	mergeVaultData(fresh, map[string]map[string]json.RawMessage{"a": {"b": raw(`2`)}})
	if string(fresh["a"]["b"]) != "2" {
		t.Errorf("fresh vault must adopt foreign entries, got %v", fresh)
	}
}
