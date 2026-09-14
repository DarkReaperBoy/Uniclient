// SPDX-License-Identifier: Unlicense OR MIT

package audio

import "unsafe"

// OpenSL ES ABI layout, transcribed from the official headers and pinned by
// opensl_layout_test.go. This file is platform-independent on purpose: the
// tests that guard it run on every platform (CI's linux gate), while the
// constants themselves are consumed only by opensl_android.go.
//
// Primary sources (fetched 2026-09-14 from AOSP frameworks/wilhelm,
// include/SLES/):
//   - OpenSLES.h           — SLObjectItf_/SLEngineItf_/SLPlayItf_/
//                            SLRecordItf_/SLBufferQueueItf_ vtables,
//                            SLDataFormat_PCM, locator macros, constants.
//   - OpenSLES_Android.h   — SLDataLocator_AndroidSimpleBufferQueue,
//                            SL_IID_ANDROIDSIMPLEBUFFERQUEUE.
//   - OpenSLES_AndroidConfiguration.h — recording presets.
//
// C types map to Go on 64-bit targets (android/amd64, android/arm64 — the
// only Android targets we ship):
//
//      SLuint32/SLresult/SLboolean → uint32
//      SLuint16                   → uint16
//      pointers, SLObjectItf, SLEngineItf, SLInterfaceID → unsafe.Pointer/uintptr (8 bytes)

// --- SLObjectItf_ vtable indices (OpenSLES.h struct order) ---
const (
	slObjectRealize  = 0 // Realize(self, async)
	slObjectResume   = 1
	slObjectGetState = 2
	slObjectGetItf   = 3 // GetInterface(self, iid, &itf)
	slObjectDestroy  = 6 // Destroy(self)
)

// --- SLEngineItf_ vtable indices ---
const (
	slEngineCreateAudioPlayer   = 2
	slEngineCreateAudioRecorder = 3
	slEngineCreateOutputMix     = 7
)

// --- SLPlayItf_ vtable indices ---
const (
	slPlaySetPlayState = 0
	slPlayGetPlayState = 1
)

// --- SLRecordItf_ vtable indices ---
const (
	slRecordSetRecordState = 0
	slRecordGetRecordState = 1
)

// --- SLBufferQueueItf_ / SLAndroidSimpleBufferQueueItf_ vtable indices ---
// (identical layout: the Android simple buffer queue is a superset)
const (
	slBQEnqueue  = 0
	slBQClear    = 1
	slBQGetState = 2
)

// --- SLAndroidConfigurationItf_ vtable indices ---
const (
	slConfigSetConfiguration = 0
)

// --- Constants (OpenSLES.h / OpenSLES_Android.h) ---
const (
	slResultSuccess          = 0x00000000
	slBooleanFalse           = 0
	slBooleanTrue            = 1
	slDatalocatorOutputMix   = 0x00000004
	slDatalocatorIODevice    = 0x00000003
	slIODeviceAudioInput     = 0x00000001
	slDataformatPCM          = 0x00000002
	slPCMSampleformatFixed16 = 0x0010
	slSpeakerFrontCenter     = 0x00000004
	slByteorderLittleEndian  = 0x00000002
	slSamplingrate48         = 48000000 // milli-Hz
	slDatalocatorAndroidBQ   = 0x800007BD
	slDefaultDeviceIDInput   = 0xFFFFFFFF
	slDefaultDeviceIDOutput  = 0xFFFFFFFE
)

// Recording presets (OpenSLES_AndroidConfiguration.h). VOICE_COMMUNICATION
// requests the platform's echo-cancellation + noise-suppression path, which
// is what a messenger voice room wants.
const (
	slRecordingPresetGeneric            = 0x00000001
	slRecordingPresetVoiceCommunication = 0x00000004
)

// Play/record states.
const (
	slPlayStateStopped     = 0x00000001
	slPlayStatePaused      = 0x00000002
	slPlayStatePlaying     = 0x00000003
	slRecordStateStopped   = 0x00000001
	slRecordStateRecording = 0x00000002
)

// slRecordingPresetKey is the SLchar* ("androidRecordingPreset") key used
// with SLAndroidConfigurationItf SetConfiguration — set BEFORE Realize.
const slRecordingPresetKey = "androidRecordingPreset"

// --- Go mirrors of the wire structs (64-bit layouts) ---

// slDataLocatorAndroidBQ mirrors SLDataLocator_AndroidSimpleBufferQueue.
type slDataLocatorAndroidBQ struct {
	locatorType uint32
	numBuffers  uint32
}

// slDataFormatPCM mirrors SLDataFormat_PCM.
type slDataFormatPCM struct {
	formatType    uint32
	numChannels   uint32
	samplesPerSec uint32
	bitsPerSample uint32
	containerSize uint32
	channelMask   uint32
	endianness    uint32
}

// slDataLocatorOutputMix mirrors SLDataLocator_OutputMix
// (locatorType uint32, padding to 8, outputMix pointer).
type slDataLocatorOutputMix struct {
	locatorType uint32
	_           uint32 // padding: SLObjectItf is 8-byte aligned
	outputMix   unsafe.Pointer
}

// slDataLocatorIODevice mirrors SLDataLocator_IODevice
// (locatorType, deviceType, deviceID, then the device pointer 8-aligned).
type slDataLocatorIODevice struct {
	locatorType uint32
	deviceType  uint32
	deviceID    uint32
	_           uint32         // padding before the pointer
	device      unsafe.Pointer // NULL = default input device
}

// slDataSource mirrors SLDataSource; slDataSink mirrors SLDataSink
// (pLocator, pFormat — both pointers).
type slDataSource struct {
	pLocator unsafe.Pointer
	pFormat  unsafe.Pointer
}

// slBQState mirrors SLBufferQueueState { SLuint32 count; SLuint32 playIndex; }.
type slBQState struct {
	count     uint32
	playIndex uint32
}

// slEngineOption mirrors SLEngineOption { SLuint32 id; SLuint32 value; }.

// --- JNI ABI ordinals (jni.h; stable since Java 1.2) ---
// JNIEnv is *pointer-to-vtable: fn k lives at offset k*8 from *env.
// Indices already include the 4 reserved slots at the table head.
const (
	jniEnvGetVersion            = 4
	jniEnvFindClass             = 6
	jniEnvExceptionOccurred     = 15
	jniEnvExceptionClear        = 17
	jniEnvNewGlobalRef          = 21
	jniEnvDeleteGlobalRef       = 22
	jniEnvDeleteLocalRef        = 23
	jniEnvGetObjectClass        = 31
	jniEnvIsInstanceOf          = 32
	jniEnvGetMethodID           = 33
	jniEnvCallObjectMethodA     = 36
	jniEnvCallBooleanMethodA    = 39
	jniEnvCallIntMethodA        = 51
	jniEnvCallVoidMethodA       = 63
	jniEnvNewStringUTF          = 167
	jniEnvGetStringUTFChars     = 169
	jniEnvReleaseStringUTFChars = 170
	jniEnvGetArrayLength        = 171
	jniEnvNewObjectArray        = 172
	jniEnvSetObjectArrayElement = 174
	jniEnvExceptionCheck        = 228
)

// JavaVM vtable ordinals (JNIInvokeInterface_; 3 reserved slots first).
const (
	jvmAttachCurrentThread = 4
	jvmDetachCurrentThread = 5
	jvmGetEnv              = 6
)

// jniVersion16 is JNI_VERSION_1_6 — the minimum GetVersion must report for
// the ordinal table above to be trusted at runtime.
const jniVersion16 = 0x00010006

// bqRing tracks buffer-queue bookkeeping for the polling pumps: which ring
// slots are enqueued vs completed, derived from the queue's reported count.
// It is pure Go so its arithmetic is unit-testable without OpenSL.
type bqRing struct {
	n    int // ring capacity
	enq  int // total buffers ever enqueued
	done int // total buffers reported completed
	bufs [][]byte
}

func newBQRing(n, bufLen int) *bqRing {
	r := &bqRing{n: n, bufs: make([][]byte, n)}
	for i := range r.bufs {
		r.bufs[i] = make([]byte, bufLen)
	}
	return r
}

// outstanding returns how many buffers are currently in flight.
func (r *bqRing) outstanding() int { return r.enq - r.done }

// completed drains completion events implied by the queue's reported count
// (OpenSL removes a buffer from the queue when it has been consumed: for
// capture, filled; for playback, played). It returns the ring slots that
// finished, in FIFO order.
func (r *bqRing) completed(queueCount int) []int {
	var out []int
	for r.enq-r.done > queueCount {
		out = append(out, r.done%r.n)
		r.done++
	}
	return out
}

// next returns the slot to enqueue next and records the enqueue.
func (r *bqRing) next() (int, []byte) {
	slot := r.enq % r.n
	r.enq++
	return slot, r.bufs[slot]
}

// reset clears the accounting (used after Clear()).
func (r *bqRing) reset() { r.enq, r.done = 0, 0 }
