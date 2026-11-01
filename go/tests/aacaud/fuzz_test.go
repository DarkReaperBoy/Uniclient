package tests

import (
	"bytes"
	"testing"
	. "uniclient/aacaud"
)

func FuzzParse(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{0, 0, 0, 16, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm', 0, 0, 2, 0})
	f.Add([]byte{0, 0, 0, 8, 'm', 'o', 'o', 'v'})
	f.Add([]byte{0, 0, 0, 24, 'f', 't', 'y', 'p', 'M', 'P', '4', 'A', 0, 0, 0, 0, 'i', 's', 'o', 'm', 0, 0, 0, 0})
	f.Add([]byte("short"))
	f.Fuzz(func(t *testing.T, data []byte) {
		track, err := Parse(bytes.NewReader(data))
		if err == nil && track == nil {
			t.Fatal("Parse returned no track and no error — fabricated outcome (§1.10)")
		}
	})
}
