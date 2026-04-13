package utils

import (
	"bytes"
	"crypto/rand"
	"testing"
)

func TestCompressEmpty(t *testing.T) {
	compressed, err := Compress([]byte{})
	if err != nil {
		t.Fatalf("Compress empty: %v", err)
	}
	decompressed, err := Decompress(compressed)
	if err != nil {
		t.Fatalf("Decompress empty: %v", err)
	}
	if len(decompressed) != 0 {
		t.Fatalf("expected empty output, got %d bytes", len(decompressed))
	}
}

func TestCompressSmallInput(t *testing.T) {
	input := []byte("hello world")
	compressed, err := Compress(input)
	if err != nil {
		t.Fatalf("Compress: %v", err)
	}
	decompressed, err := Decompress(compressed)
	if err != nil {
		t.Fatalf("Decompress: %v", err)
	}
	if !bytes.Equal(input, decompressed) {
		t.Fatalf("round-trip mismatch: got %q, want %q", decompressed, input)
	}
}

func TestCompressLargeInput(t *testing.T) {
	input := make([]byte, 1<<20) // 1 MB
	if _, err := rand.Read(input); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	compressed, err := Compress(input)
	if err != nil {
		t.Fatalf("Compress: %v", err)
	}
	decompressed, err := Decompress(compressed)
	if err != nil {
		t.Fatalf("Decompress: %v", err)
	}
	if !bytes.Equal(input, decompressed) {
		t.Fatal("round-trip mismatch for 1MB random data")
	}
}

func TestCompressAlreadyCompressed(t *testing.T) {
	input := []byte("some data to double compress")
	first, err := Compress(input)
	if err != nil {
		t.Fatalf("first Compress: %v", err)
	}
	second, err := Compress(first)
	if err != nil {
		t.Fatalf("second Compress: %v", err)
	}
	decompressed, err := Decompress(second)
	if err != nil {
		t.Fatalf("first Decompress: %v", err)
	}
	if !bytes.Equal(first, decompressed) {
		t.Fatal("outer round-trip mismatch")
	}
	original, err := Decompress(decompressed)
	if err != nil {
		t.Fatalf("second Decompress: %v", err)
	}
	if !bytes.Equal(input, original) {
		t.Fatal("inner round-trip mismatch")
	}
}

func TestCompressRoundTripByteIdentical(t *testing.T) {
	inputs := [][]byte{
		{},
		[]byte("hello world"),
		bytes.Repeat([]byte("abcdefgh"), 10000),
	}
	for i, input := range inputs {
		compressed, err := Compress(input)
		if err != nil {
			t.Fatalf("case %d Compress: %v", i, err)
		}
		decompressed, err := Decompress(compressed)
		if err != nil {
			t.Fatalf("case %d Decompress: %v", i, err)
		}
		if !bytes.Equal(input, decompressed) {
			t.Fatalf("case %d: round-trip not byte-identical", i)
		}
	}
}
