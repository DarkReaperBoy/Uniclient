package audio

import "unsafe"

const (
	SLObjectRealize  = 0
	SLObjectResume   = 1
	SLObjectGetState = 2
	SLObjectGetItf   = 3
	SLObjectDestroy  = 6
)

const (
	SLEngineCreateAudioPlayer   = 2
	SLEngineCreateAudioRecorder = 3
	SLEngineCreateOutputMix     = 7
)

const (
	SLPlaySetPlayState = 0
	SLPlayGetPlayState = 1
)

const (
	SLRecordSetRecordState = 0
	SLRecordGetRecordState = 1
)

const (
	SLBQEnqueue  = 0
	SLBQClear    = 1
	SLBQGetState = 2
)

const (
	SLConfigSetConfiguration = 0
)

const (
	SLResultSuccess          = 0x00000000
	SLBooleanFalse           = 0
	SLBooleanTrue            = 1
	SLDatalocatorOutputMix   = 0x00000004
	SLDatalocatorIODevice    = 0x00000003
	SLIODeviceAudioInput     = 0x00000001
	SLDataformatPCM          = 0x00000002
	SLPCMSampleformatFixed16 = 0x0010
	SLSpeakerFrontCenter     = 0x00000004
	SLByteorderLittleEndian  = 0x00000002
	SLSamplingrate48         = 48000000
	SLDatalocatorAndroidBQ   = 0x800007BD
	SLDefaultDeviceIDInput   = 0xFFFFFFFF
	SLDefaultDeviceIDOutput  = 0xFFFFFFFE
)

const (
	SLRecordingPresetGeneric            = 0x00000001
	SLRecordingPresetVoiceCommunication = 0x00000004
)

const (
	SLPlayStateStopped     = 0x00000001
	SLPlayStatePaused      = 0x00000002
	SLPlayStatePlaying     = 0x00000003
	SLRecordStateStopped   = 0x00000001
	SLRecordStateRecording = 0x00000002
)

const SLRecordingPresetKey = "androidRecordingPreset"

type SLDataLocatorAndroidBQ struct {
	LocatorType uint32
	NumBuffers  uint32
}

type SLDataFormatPCM struct {
	formatType    uint32
	numChannels   uint32
	samplesPerSec uint32
	bitsPerSample uint32
	containerSize uint32
	channelMask   uint32
	endianness    uint32
}

type SLDataLocatorOutputMix struct {
	LocatorType uint32
	_           uint32
	OutputMix   unsafe.Pointer
}

type SLDataLocatorIODevice struct {
	LocatorType uint32
	DeviceType  uint32
	DeviceID    uint32
	_           uint32
	Device      unsafe.Pointer
}

type SLDataSource struct {
	pLocator unsafe.Pointer
	pFormat  unsafe.Pointer
}

type SLBQState struct {
	count     uint32
	playIndex uint32
}

const (
	JNIEnvGetVersion            = 4
	JNIEnvFindClass             = 6
	JNIEnvExceptionOccurred     = 15
	JNIEnvExceptionClear        = 17
	JNIEnvNewGlobalRef          = 21
	JNIEnvDeleteGlobalRef       = 22
	JNIEnvDeleteLocalRef        = 23
	JNIEnvGetObjectClass        = 31
	JNIEnvIsInstanceOf          = 32
	JNIEnvGetMethodID           = 33
	JNIEnvCallObjectMethodA     = 36
	JNIEnvCallBooleanMethodA    = 39
	JNIEnvCallIntMethodA        = 51
	JNIEnvCallVoidMethodA       = 63
	JNIEnvNewStringUTF          = 167
	JNIEnvGetStringUTFChars     = 169
	JNIEnvReleaseStringUTFChars = 170
	JNIEnvGetArrayLength        = 171
	JNIEnvNewObjectArray        = 172
	JNIEnvSetObjectArrayElement = 174
	JNIEnvExceptionCheck        = 228
)

const (
	JvmAttachCurrentThread = 4
	JvmDetachCurrentThread = 5
	JvmGetEnv              = 6
)

const JniVersion16 = 0x00010006

type BQRing struct {
	n    int
	enq  int
	done int
	bufs [][]byte
}

func NewBQRing(n, bufLen int) *BQRing {
	r := &BQRing{n: n, bufs: make([][]byte, n)}
	for i := range r.bufs {
		r.bufs[i] = make([]byte, bufLen)
	}
	return r
}

func (r *BQRing) Outstanding() int { return r.enq - r.done }

func (r *BQRing) Completed(queueCount int) []int {
	var out []int
	for r.enq-r.done > queueCount {
		out = append(out, r.done%r.n)
		r.done++
	}
	return out
}

func (r *BQRing) Next() (int, []byte) {
	slot := r.enq % r.n
	r.enq++
	return slot, r.bufs[slot]
}

func (r *BQRing) Reset() { r.enq, r.done = 0, 0 }
