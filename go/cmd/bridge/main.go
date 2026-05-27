// Entry point for c-shared library build.
// Minimal CGo: a 2-line C trampoline invokes Dart's event callback function
// pointer. All exported function signatures use pure Go types. Memory is
// managed by Go's runtime with Pinner to satisfy cgo pointer rules.
package main

/*
#include <stdint.h>
typedef void (*event_callback_t)(void* data, int32_t len);
static void invoke_callback(event_callback_t cb, void* data, int32_t len) { cb(data, len); }
*/
import "C"
import (
	"runtime"
	"sync"
	"unsafe"

	"uniclient/bridge"
)

func main() {}

type pinnedEntry struct {
	data   []byte
	pinner *runtime.Pinner
}

var (
	pinnedMu   sync.Mutex
	pinnedRefs = make(map[uintptr]pinnedEntry)
)

func pinBytes(data []byte) *byte {
	buf := make([]byte, len(data))
	copy(buf, data)
	ptr := &buf[0]

	p := new(runtime.Pinner)
	p.Pin(ptr)

	pinnedMu.Lock()
	pinnedRefs[uintptr(unsafe.Pointer(ptr))] = pinnedEntry{data: buf, pinner: p}
	pinnedMu.Unlock()
	return ptr
}

func unpinBytes(ptr *byte) {
	pinnedMu.Lock()
	entry, ok := pinnedRefs[uintptr(unsafe.Pointer(ptr))]
	if ok {
		entry.pinner.Unpin()
		delete(pinnedRefs, uintptr(unsafe.Pointer(ptr)))
	}
	pinnedMu.Unlock()
}

//export BridgeCallWithLen
func BridgeCallWithLen(data *byte, dataLen int32, outLen *int32) *byte {
	goData := make([]byte, int(dataLen))
	copy(goData, unsafe.Slice(data, int(dataLen)))

	result := bridge.Call(goData)
	*outLen = int32(len(result))
	if len(result) == 0 {
		return nil
	}
	return pinBytes(result)
}

//export BridgeFree
func BridgeFree(ptr *byte) {
	if ptr != nil {
		unpinBytes(ptr)
	}
}

//export BridgeSetEventCallback
func BridgeSetEventCallback(cb unsafe.Pointer) {
	if cb == nil {
		bridge.SetEventCallback(nil)
		return
	}
	ccb := C.event_callback_t(cb)
	bridge.SetEventCallback(func(data []byte) {
		if len(data) == 0 {
			return
		}
		ptr := pinBytes(data)
		C.invoke_callback(ccb, unsafe.Pointer(ptr), C.int32_t(len(data)))
	})
}
