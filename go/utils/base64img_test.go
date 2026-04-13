package utils

import (
	"bytes"
	"encoding/base64"
	"math/rand"
	"testing"
)

func TestBase64RoundTrip(t *testing.T) {
	rng := rand.New(rand.NewSource(42))
	original := make([]byte, 1024)
	rng.Read(original)

	encoded := EncodeImageBase64(original)
	decoded, err := DecodeImageBase64(encoded)
	if err != nil {
		t.Fatalf("DecodeImageBase64 returned error: %v", err)
	}
	if !bytes.Equal(original, decoded) {
		t.Fatal("round-trip failed: decoded bytes differ from original")
	}
}

func TestBase64DecodeEmpty(t *testing.T) {
	decoded, err := DecodeImageBase64("")
	if err != nil {
		t.Fatalf("unexpected error for empty string: %v", err)
	}
	if len(decoded) != 0 {
		t.Fatalf("expected empty slice, got %d bytes", len(decoded))
	}
}

func TestBase64DecodeInvalid(t *testing.T) {
	_, err := DecodeImageBase64("!!!not-valid-base64!!!")
	if err == nil {
		t.Fatal("expected error for invalid base64, got nil")
	}
}

func TestDetectImageFormatPNG(t *testing.T) {
	data := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
	if f := DetectImageFormat(data); f != "png" {
		t.Fatalf("expected png, got %s", f)
	}
}

func TestDetectImageFormatJPEG(t *testing.T) {
	data := []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10}
	if f := DetectImageFormat(data); f != "jpeg" {
		t.Fatalf("expected jpeg, got %s", f)
	}
}

func TestDetectImageFormatGIF(t *testing.T) {
	data := []byte("GIF89a" + "\x00\x00\x00\x00")
	if f := DetectImageFormat(data); f != "gif" {
		t.Fatalf("expected gif, got %s", f)
	}
}

func TestDetectImageFormatWebP(t *testing.T) {
	// RIFF + 4 bytes size + WEBP
	data := []byte("RIFF\x00\x00\x00\x00WEBP")
	if f := DetectImageFormat(data); f != "webp" {
		t.Fatalf("expected webp, got %s", f)
	}
}

func TestDetectImageFormatUnknown(t *testing.T) {
	data := []byte{0x00, 0x01, 0x02, 0x03}
	if f := DetectImageFormat(data); f != "unknown" {
		t.Fatalf("expected unknown, got %s", f)
	}
}

func TestValidateImageBase64PNG(t *testing.T) {
	pngData := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
	b64 := base64.StdEncoding.EncodeToString(pngData)

	format, err := ValidateImageBase64(b64)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if format != "png" {
		t.Fatalf("expected png, got %s", format)
	}
}

func TestValidateImageBase64Corrupt(t *testing.T) {
	_, err := ValidateImageBase64("!!!corrupt!!!")
	if err == nil {
		t.Fatal("expected error for corrupt base64, got nil")
	}
}
