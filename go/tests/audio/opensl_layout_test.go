package tests

import (
	"testing"
	. "uniclient/audio"
	"unsafe"
)

func TestSLObjectItfVTable(t *testing.T) {
	for _, tc := range []struct {
		name string
		got  int
		want int
	}{
		{"Realize", SLObjectRealize, 0},
		{"GetState", SLObjectGetState, 2},
		{"GetInterface", SLObjectGetItf, 3},
		{"Destroy", SLObjectDestroy, 6},
	} {
		if tc.got != tc.want {
			t.Errorf("SLObjectItf.%s = %d, want %d", tc.name, tc.got, tc.want)
		}
	}
}

func TestSLEngineItfVTable(t *testing.T) {
	for _, tc := range []struct {
		name string
		got  int
		want int
	}{
		{"CreateAudioPlayer", SLEngineCreateAudioPlayer, 2},
		{"CreateAudioRecorder", SLEngineCreateAudioRecorder, 3},
		{"CreateOutputMix", SLEngineCreateOutputMix, 7},
	} {
		if tc.got != tc.want {
			t.Errorf("SLEngineItf.%s = %d, want %d", tc.name, tc.got, tc.want)
		}
	}
}

func TestSLPlayRecordBQVTables(t *testing.T) {
	if SLPlaySetPlayState != 0 || SLPlayGetPlayState != 1 {
		t.Errorf("SLPlayItf play-state indices wrong: %d/%d", SLPlaySetPlayState, SLPlayGetPlayState)
	}
	if SLRecordSetRecordState != 0 || SLRecordGetRecordState != 1 {
		t.Errorf("SLRecordItf record-state indices wrong: %d/%d", SLRecordSetRecordState, SLRecordGetRecordState)
	}
	if SLBQEnqueue != 0 || SLBQClear != 1 || SLBQGetState != 2 {
		t.Errorf("SLBufferQueueItf indices wrong: %d/%d/%d", SLBQEnqueue, SLBQClear, SLBQGetState)
	}
	if SLConfigSetConfiguration != 0 {
		t.Errorf("SLAndroidConfigurationItf.SetConfiguration = %d, want 0", SLConfigSetConfiguration)
	}
}

func TestSLConstants(t *testing.T) {
	for _, tc := range []struct {
		name string
		got  uint32
		want uint32
	}{
		{"SL_RESULT_SUCCESS", SLResultSuccess, 0},
		{"SL_DATALOCATOR_IODEVICE", SLDatalocatorIODevice, 0x00000003},
		{"SL_IODEVICE_AUDIOINPUT", SLIODeviceAudioInput, 0x00000001},
		{"SL_DATALOCATOR_OUTPUTMIX", SLDatalocatorOutputMix, 0x00000004},
		{"SL_DATAFORMAT_PCM", SLDataformatPCM, 0x00000002},
		{"SL_SPEAKER_FRONT_CENTER", SLSpeakerFrontCenter, 0x00000004},
		{"SL_BYTEORDER_LITTLEENDIAN", SLByteorderLittleEndian, 0x00000002},
		{"SL_SAMPLINGRATE_48 (milli-Hz)", SLSamplingrate48, 48000000},
		{"SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE", SLDatalocatorAndroidBQ, 0x800007BD},
		{"SL_DEFAULTDEVICEID_AUDIOINPUT", SLDefaultDeviceIDInput, 0xFFFFFFFF},
		{"SL_DEFAULTDEVICEID_AUDIOOUTPUT", SLDefaultDeviceIDOutput, 0xFFFFFFFE},
		{"preset GENERIC", SLRecordingPresetGeneric, 1},
		{"preset VOICE_COMMUNICATION", SLRecordingPresetVoiceCommunication, 4},
		{"PLAYSTATE_STOPPED", SLPlayStateStopped, 1},
		{"PLAYSTATE_PAUSED", SLPlayStatePaused, 2},
		{"PLAYSTATE_PLAYING", SLPlayStatePlaying, 3},
		{"RECORDSTATE_STOPPED", SLRecordStateStopped, 1},
		{"RECORDSTATE_RECORDING", SLRecordStateRecording, 2},
	} {
		if tc.got != tc.want {
			t.Errorf("%s = 0x%X, want 0x%X", tc.name, tc.got, tc.want)
		}
	}
	if SLPCMSampleformatFixed16 != 0x0010 {
		t.Errorf("SL_PCMSAMPLEFORMAT_FIXED_16 = 0x%X, want 0x0010", SLPCMSampleformatFixed16)
	}
	if SLRecordingPresetKey != "androidRecordingPreset" {
		t.Errorf("preset key = %q, want androidRecordingPreset", SLRecordingPresetKey)
	}
}

func TestSLStructLayouts64(t *testing.T) {
	if unsafe.Sizeof(unsafe.Pointer(nil)) != 8 {
		t.Skip("layout checks are 64-bit only")
	}
	if got := unsafe.Sizeof(SLDataLocatorAndroidBQ{}); got != 8 {
		t.Errorf("SLDataLocator_AndroidSimpleBufferQueue size = %d, want 8", got)
	}
	if got := unsafe.Offsetof(SLDataLocatorAndroidBQ{}.NumBuffers); got != 4 {
		t.Errorf("NumBuffers offset = %d, want 4", got)
	}
	if got := unsafe.Sizeof(SLDataFormatPCM{}); got != 28 {
		t.Errorf("SLDataFormat_PCM size = %d, want 28", got)
	}
	if got := unsafe.Sizeof(SLDataSource{}); got != 16 {
		t.Errorf("SLDataSource size = %d, want 16", got)
	}
	if got := unsafe.Offsetof(SLDataLocatorOutputMix{}.OutputMix); got != 8 {
		t.Errorf("SLDataLocator_OutputMix.outputMix offset = %d, want 8", got)
	}
	if got := unsafe.Sizeof(SLDataLocatorOutputMix{}); got != 16 {
		t.Errorf("SLDataLocator_OutputMix size = %d, want 16", got)
	}
	if got := unsafe.Sizeof(SLBQState{}); got != 8 {
		t.Errorf("SLBufferQueueState size = %d, want 8", got)
	}
	if got := unsafe.Sizeof(SLDataLocatorIODevice{}); got != 24 {
		t.Errorf("SLDataLocator_IODevice size = %d, want 24", got)
	}
	if got := unsafe.Offsetof(SLDataLocatorIODevice{}.Device); got != 16 {
		t.Errorf("SLDataLocator_IODevice.device offset = %d, want 16", got)
	}
}

func TestJNIOrdinals(t *testing.T) {
	for _, tc := range []struct {
		name string
		got  int
		want int
	}{
		{"GetVersion", JNIEnvGetVersion, 4},
		{"FindClass", JNIEnvFindClass, 6},
		{"ExceptionOccurred", JNIEnvExceptionOccurred, 15},
		{"ExceptionClear", JNIEnvExceptionClear, 17},
		{"NewGlobalRef", JNIEnvNewGlobalRef, 21},
		{"DeleteGlobalRef", JNIEnvDeleteGlobalRef, 22},
		{"DeleteLocalRef", JNIEnvDeleteLocalRef, 23},
		{"GetObjectClass", JNIEnvGetObjectClass, 31},
		{"GetMethodID", JNIEnvGetMethodID, 33},
		{"CallObjectMethodA", JNIEnvCallObjectMethodA, 36},
		{"CallBooleanMethodA", JNIEnvCallBooleanMethodA, 39},
		{"CallIntMethodA", JNIEnvCallIntMethodA, 51},
		{"CallVoidMethodA", JNIEnvCallVoidMethodA, 63},
		{"NewStringUTF", JNIEnvNewStringUTF, 167},
		{"GetStringUTFChars", JNIEnvGetStringUTFChars, 169},
		{"ReleaseStringUTFChars", JNIEnvReleaseStringUTFChars, 170},
		{"GetArrayLength", JNIEnvGetArrayLength, 171},
		{"NewObjectArray", JNIEnvNewObjectArray, 172},
		{"SetObjectArrayElement", JNIEnvSetObjectArrayElement, 174},
		{"ExceptionCheck", JNIEnvExceptionCheck, 228},
	} {
		if tc.got != tc.want {
			t.Errorf("JNIEnv.%s = %d, want %d", tc.name, tc.got, tc.want)
		}
	}
	if JvmAttachCurrentThread != 4 || JvmDetachCurrentThread != 5 || JvmGetEnv != 6 {
		t.Errorf("JavaVM ordinals wrong: attach=%d detach=%d getenv=%d",
			JvmAttachCurrentThread, JvmDetachCurrentThread, JvmGetEnv)
	}
	if JniVersion16 != 0x00010006 {
		t.Errorf("JNI_VERSION_1_6 = 0x%X", JniVersion16)
	}
}

func TestBQRing(t *testing.T) {
	r := NewBQRing(4, 1920)

	for i := 0; i < 4; i++ {
		slot, buf := r.Next()
		if slot != i%4 {
			t.Fatalf("enqueue %d: slot %d, want %d", i, slot, i%4)
		}
		if len(buf) != 1920 {
			t.Fatalf("buffer len %d", len(buf))
		}
	}
	if got := r.Completed(4); len(got) != 0 {
		t.Fatalf("completed(4) = %v, want empty", got)
	}
	if r.Outstanding() != 4 {
		t.Fatalf("outstanding = %d, want 4", r.Outstanding())
	}

	got := r.Completed(2)
	if len(got) != 2 || got[0] != 0 || got[1] != 1 {
		t.Fatalf("completed(2) = %v, want [0 1]", got)
	}
	if r.Outstanding() != 2 {
		t.Fatalf("outstanding = %d, want 2", r.Outstanding())
	}

	for i := 0; i < 2; i++ {
		slot, _ := r.Next()
		want := (4 + i) % 4
		if slot != want {
			t.Fatalf("re-enqueue %d: slot %d, want %d", i, slot, want)
		}
	}
	got = r.Completed(3)
	if len(got) != 1 || got[0] != 2 {
		t.Fatalf("completed(3) = %v, want [2]", got)
	}

	r.Reset()
	if r.Outstanding() != 0 {
		t.Fatalf("after reset outstanding = %d", r.Outstanding())
	}
	if got := r.Completed(0); len(got) != 0 {
		t.Fatalf("after reset completed(0) = %v", got)
	}
}
