package audio

import "unsafe"

const (
	slObjectRealize  = 0
	slObjectResume   = 1
	slObjectGetState = 2
	slObjectGetItf   = 3
	slObjectDestroy  = 6
)

const (
	slEngineCreateAudioPlayer   = 2
	slEngineCreateAudioRecorder = 3
	slEngineCreateOutputMix     = 7
)

const (
	slPlaySetPlayState = 0
	slPlayGetPlayState = 1
)

const (
	slRecordSetRecordState = 0
	slRecordGetRecordState = 1
)

const (
	slBQEnqueue  = 0
	slBQClear    = 1
	slBQGetState = 2
)

const (
	slConfigSetConfiguration = 0
)

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
	slSamplingrate48         = 48000000
	slDatalocatorAndroidBQ   = 0x800007BD
	slDefaultDeviceIDInput   = 0xFFFFFFFF
	slDefaultDeviceIDOutput  = 0xFFFFFFFE
)

const (
	slRecordingPresetGeneric            = 0x00000001
	slRecordingPresetVoiceCommunication = 0x00000004
)

const (
	slPlayStateStopped     = 0x00000001
	slPlayStatePaused      = 0x00000002
	slPlayStatePlaying     = 0x00000003
	slRecordStateStopped   = 0x00000001
	slRecordStateRecording = 0x00000002
)

const slRecordingPresetKey = "androidRecordingPreset"

type slDataLocatorAndroidBQ struct {
	locatorType uint32
	numBuffers  uint32
}

type slDataFormatPCM struct {
	formatType    uint32
	numChannels   uint32
	samplesPerSec uint32
	bitsPerSample uint32
	containerSize uint32
	channelMask   uint32
	endianness    uint32
}

type slDataLocatorOutputMix struct {
	locatorType uint32
	_           uint32
	outputMix   unsafe.Pointer
}

type slDataLocatorIODevice struct {
	locatorType uint32
	deviceType  uint32
	deviceID    uint32
	_           uint32
	device      unsafe.Pointer
}

type slDataSource struct {
	pLocator unsafe.Pointer
	pFormat  unsafe.Pointer
}

type slBQState struct {
	count     uint32
	playIndex uint32
}

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

const (
	jvmAttachCurrentThread = 4
	jvmDetachCurrentThread = 5
	jvmGetEnv              = 6
)

const jniVersion16 = 0x00010006

type bqRing struct {
	n    int
	enq  int
	done int
	bufs [][]byte
}

func newBQRing(n, bufLen int) *bqRing {
	r := &bqRing{n: n, bufs: make([][]byte, n)}
	for i := range r.bufs {
		r.bufs[i] = make([]byte, bufLen)
	}
	return r
}

func (r *bqRing) outstanding() int { return r.enq - r.done }

func (r *bqRing) completed(queueCount int) []int {
	var out []int
	for r.enq-r.done > queueCount {
		out = append(out, r.done%r.n)
		r.done++
	}
	return out
}

func (r *bqRing) next() (int, []byte) {
	slot := r.enq % r.n
	r.enq++
	return slot, r.bufs[slot]
}

func (r *bqRing) reset() { r.enq, r.done = 0, 0 }
