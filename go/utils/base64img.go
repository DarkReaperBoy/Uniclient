package utils

import (
	"bytes"
	"encoding/base64"
	"errors"
)

// EncodeImageBase64 encodes raw image bytes to a standard Base64 string.
func EncodeImageBase64(data []byte) string {
	return base64.StdEncoding.EncodeToString(data)
}

// DecodeImageBase64 decodes a Base64 string back to raw bytes.
func DecodeImageBase64(b64 string) ([]byte, error) {
	if b64 == "" {
		return []byte{}, nil
	}
	return base64.StdEncoding.DecodeString(b64)
}

// DetectImageFormat returns "png", "jpeg", "gif", "webp", or "unknown"
// based on magic bytes at the start of data.
func DetectImageFormat(data []byte) string {
	switch {
	case len(data) >= 4 && bytes.Equal(data[:4], []byte{0x89, 0x50, 0x4E, 0x47}):
		return "png"
	case len(data) >= 3 && bytes.Equal(data[:3], []byte{0xFF, 0xD8, 0xFF}):
		return "jpeg"
	case len(data) >= 6 && (bytes.Equal(data[:6], []byte("GIF87a")) || bytes.Equal(data[:6], []byte("GIF89a"))):
		return "gif"
	case len(data) >= 12 && bytes.Equal(data[:4], []byte("RIFF")) && bytes.Equal(data[8:12], []byte("WEBP")):
		return "webp"
	default:
		return "unknown"
	}
}

// ValidateImageBase64 decodes a Base64 string and validates that the result
// is a known image format. Returns the detected format and any error.
func ValidateImageBase64(b64 string) (string, error) {
	data, err := DecodeImageBase64(b64)
	if err != nil {
		return "", err
	}
	format := DetectImageFormat(data)
	if format == "unknown" {
		return "", errors.New("unrecognized image format")
	}
	return format, nil
}
