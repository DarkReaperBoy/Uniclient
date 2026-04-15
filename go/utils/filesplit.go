package utils

import (
	"fmt"
	"io"
	"strconv"
	"strings"
)

// SplitFile reads from r and splits the data into chunks of at most maxBytes.
// Returns a slice of byte slices. An empty input yields a single empty part.
func SplitFile(r io.Reader, maxBytes int64) ([][]byte, error) {
	if maxBytes <= 0 {
		return nil, fmt.Errorf("maxBytes must be positive, got %d", maxBytes)
	}
	// Cap at 100MB to prevent accidental memory exhaustion.
	const maxAlloc int64 = 100 * 1024 * 1024
	if maxBytes > maxAlloc {
		maxBytes = maxAlloc
	}

	var parts [][]byte
	for {
		buf := make([]byte, maxBytes)
		n, err := io.ReadFull(r, buf)
		if n > 0 {
			parts = append(parts, buf[:n])
		}
		if err == io.EOF || err == io.ErrUnexpectedEOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("reading input: %w", err)
		}
	}

	if len(parts) == 0 {
		parts = append(parts, []byte{})
	}
	return parts, nil
}

// ReassembleFile concatenates parts back into the original data.
func ReassembleFile(parts [][]byte) []byte {
	var total int
	for _, p := range parts {
		total += len(p)
	}
	out := make([]byte, 0, total)
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}

// PartName generates a part name like "document.zip.part01".
// Part numbers are 1-based and zero-padded to 2 digits.
func PartName(filename string, partNum int, totalParts int) string {
	_ = totalParts // available for future use (e.g. wider padding)
	return fmt.Sprintf("%s.part%02d", filename, partNum)
}

// ParsePartName parses a part name back into the base name and part number.
// Returns ok=false if the name does not match the expected pattern.
func ParsePartName(partName string) (baseName string, partNum int, ok bool) {
	idx := strings.LastIndex(partName, ".part")
	if idx < 0 {
		return "", 0, false
	}
	numStr := partName[idx+len(".part"):]
	n, err := strconv.Atoi(numStr)
	if err != nil || n < 0 {
		return "", 0, false
	}
	return partName[:idx], n, true
}
