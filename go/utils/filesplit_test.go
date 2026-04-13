package utils

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"testing"
)

const (
	mb19_5 = 19*1024*1024 + 512*1024 // 19.5 MB = 20447232 bytes
)

func TestFileSplitTiny(t *testing.T) {
	data := make([]byte, 100)
	rand.Read(data)

	parts, err := SplitFile(bytes.NewReader(data), 1024*1024)
	if err != nil {
		t.Fatal(err)
	}
	if len(parts) != 1 {
		t.Fatalf("expected 1 part, got %d", len(parts))
	}
	reassembled := ReassembleFile(parts)
	if !bytes.Equal(reassembled, data) {
		t.Fatal("reassembled data does not match original")
	}
}

func TestFileSplitExactBoundary(t *testing.T) {
	data := make([]byte, mb19_5)
	rand.Read(data)

	parts, err := SplitFile(bytes.NewReader(data), int64(mb19_5))
	if err != nil {
		t.Fatal(err)
	}
	if len(parts) != 1 {
		t.Fatalf("expected 1 part for exact boundary, got %d", len(parts))
	}
	reassembled := ReassembleFile(parts)
	if !bytes.Equal(reassembled, data) {
		t.Fatal("reassembled data does not match original")
	}
}

func TestFileSplitOneByteOver(t *testing.T) {
	data := make([]byte, mb19_5+1)
	rand.Read(data)

	parts, err := SplitFile(bytes.NewReader(data), int64(mb19_5))
	if err != nil {
		t.Fatal(err)
	}
	if len(parts) != 2 {
		t.Fatalf("expected 2 parts, got %d", len(parts))
	}
	if len(parts[0]) != mb19_5 {
		t.Fatalf("first part should be %d bytes, got %d", mb19_5, len(parts[0]))
	}
	if len(parts[1]) != 1 {
		t.Fatalf("second part should be 1 byte, got %d", len(parts[1]))
	}
	reassembled := ReassembleFile(parts)
	if !bytes.Equal(reassembled, data) {
		t.Fatal("reassembled data does not match original")
	}
}

func TestFileSplitLarge(t *testing.T) {
	size := 50 * 1024 * 1024 // 50 MB
	data := make([]byte, size)
	rand.Read(data)

	parts, err := SplitFile(bytes.NewReader(data), int64(mb19_5))
	if err != nil {
		t.Fatal(err)
	}
	if len(parts) != 3 {
		t.Fatalf("expected 3 parts, got %d", len(parts))
	}
	// First two parts should be full-size, third is the remainder.
	if len(parts[0]) != mb19_5 {
		t.Fatalf("part 0: expected %d bytes, got %d", mb19_5, len(parts[0]))
	}
	if len(parts[1]) != mb19_5 {
		t.Fatalf("part 1: expected %d bytes, got %d", mb19_5, len(parts[1]))
	}
	expectedRemainder := size - 2*mb19_5
	if len(parts[2]) != expectedRemainder {
		t.Fatalf("part 2: expected %d bytes, got %d", expectedRemainder, len(parts[2]))
	}
	reassembled := ReassembleFile(parts)
	if !bytes.Equal(reassembled, data) {
		t.Fatal("reassembled data does not match original")
	}
}

func TestFileSplitEmpty(t *testing.T) {
	parts, err := SplitFile(bytes.NewReader(nil), 1024)
	if err != nil {
		t.Fatal(err)
	}
	if len(parts) != 1 {
		t.Fatalf("expected 1 part for empty input, got %d", len(parts))
	}
	if len(parts[0]) != 0 {
		t.Fatalf("expected empty part, got %d bytes", len(parts[0]))
	}
	reassembled := ReassembleFile(parts)
	if len(reassembled) != 0 {
		t.Fatal("reassembled empty file should be empty")
	}
}

func TestFilePartNameRoundTrip(t *testing.T) {
	cases := []struct {
		filename   string
		partNum    int
		totalParts int
		want       string
	}{
		{"document.zip", 1, 3, "document.zip.part01"},
		{"document.zip", 2, 3, "document.zip.part02"},
		{"document.zip", 3, 3, "document.zip.part03"},
		{"photo.png", 10, 12, "photo.png.part10"},
	}
	for _, tc := range cases {
		t.Run(fmt.Sprintf("%s_part%d", tc.filename, tc.partNum), func(t *testing.T) {
			got := PartName(tc.filename, tc.partNum, tc.totalParts)
			if got != tc.want {
				t.Fatalf("PartName(%q, %d, %d) = %q, want %q",
					tc.filename, tc.partNum, tc.totalParts, got, tc.want)
			}
			baseName, num, ok := ParsePartName(got)
			if !ok {
				t.Fatalf("ParsePartName(%q) returned ok=false", got)
			}
			if baseName != tc.filename {
				t.Fatalf("ParsePartName base = %q, want %q", baseName, tc.filename)
			}
			if num != tc.partNum {
				t.Fatalf("ParsePartName num = %d, want %d", num, tc.partNum)
			}
		})
	}
}

func TestFileParsePartNameInvalid(t *testing.T) {
	invalids := []string{"nopart", "file.txt", "file.partition01", "file.part", "file.partXX"}
	for _, name := range invalids {
		_, _, ok := ParsePartName(name)
		if ok {
			t.Errorf("ParsePartName(%q) should return ok=false", name)
		}
	}
}
