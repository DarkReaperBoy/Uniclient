// Entry point for c-shared library build.
// Build: CGO_ENABLED=1 go build -tags goolm -buildmode=c-shared -o libcores.so ./cmd/bridge/
package main

// #include <stdlib.h>
// #include <stdint.h>
//
// typedef void (*event_callback_t)(void* data, int32_t len);
//
// static void invoke_event_callback(event_callback_t cb, void* data, int32_t len) {
//     cb(data, len);
// }
import "C"
import (
	"unsafe"

	"uniclient/bridge"
)

func main() {}

// BridgeCallWithLen is the single FFI entry point.
// Takes a serialized BridgeRequest proto as (pointer, length).
// Returns a serialized BridgeResponse proto and sets outLen.
// Caller must free the returned pointer with BridgeFree.
//
//export BridgeCallWithLen
func BridgeCallWithLen(data *C.uint8_t, dataLen C.int32_t, outLen *C.int32_t) *C.uint8_t {
	goData := C.GoBytes(unsafe.Pointer(data), C.int(dataLen))
	result := bridge.Call(goData)
	*outLen = C.int32_t(len(result))
	if len(result) == 0 {
		return nil
	}
	cResult := (*C.uint8_t)(C.malloc(C.size_t(len(result))))
	copy(unsafe.Slice((*byte)(unsafe.Pointer(cResult)), len(result)), result)
	return cResult
}

// BridgeFree frees memory allocated by BridgeCallWithLen.
//
//export BridgeFree
func BridgeFree(ptr *C.uint8_t) {
	if ptr != nil {
		C.free(unsafe.Pointer(ptr))
	}
}

// BridgeSetEventCallback sets a C callback for async events (Go → Dart).
// The callback receives (data pointer, length) for a serialized BridgeEvent proto.
//
//export BridgeSetEventCallback
func BridgeSetEventCallback(cb C.event_callback_t) {
	if cb == nil {
		bridge.SetEventCallback(nil)
		return
	}
	bridge.SetEventCallback(func(data []byte) {
		if len(data) == 0 {
			return
		}
		cData := C.CBytes(data)
		C.invoke_event_callback(cb, cData, C.int32_t(len(data)))
		C.free(cData)
	})
}
