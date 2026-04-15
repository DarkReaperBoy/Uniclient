package utils

import (
	"sync"

	"github.com/klauspost/compress/zstd"
)

var (
	encoder     *zstd.Encoder
	decoder     *zstd.Decoder
	encoderOnce sync.Once
	decoderOnce sync.Once
	encoderErr  error
	decoderErr  error
	compressMu  sync.Mutex
	decompressMu sync.Mutex
)

func getEncoder() (*zstd.Encoder, error) {
	encoderOnce.Do(func() {
		encoder, encoderErr = zstd.NewWriter(nil, zstd.WithEncoderLevel(zstd.SpeedBestCompression))
	})
	return encoder, encoderErr
}

func getDecoder() (*zstd.Decoder, error) {
	decoderOnce.Do(func() {
		decoder, decoderErr = zstd.NewReader(nil)
	})
	return decoder, decoderErr
}

// Compress compresses data using Zstd at the maximum compression level.
func Compress(data []byte) ([]byte, error) {
	enc, err := getEncoder()
	if err != nil {
		return nil, err
	}
	compressMu.Lock()
	result := enc.EncodeAll(data, nil)
	compressMu.Unlock()
	return result, nil
}

// Decompress decompresses Zstd-compressed data.
func Decompress(data []byte) ([]byte, error) {
	dec, err := getDecoder()
	if err != nil {
		return nil, err
	}
	decompressMu.Lock()
	result, err := dec.DecodeAll(data, nil)
	decompressMu.Unlock()
	return result, err
}
