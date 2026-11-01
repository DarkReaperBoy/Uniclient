package audio

import (
	"testing"
	"unsafe"
)

func TestSLObjectItfVTable(t *testing.T) {
	for _, tc := range []struct {
		name string
		got  int
		want int
	}{
		{"Realize", slObjectRealize, 0},
		{"GetState", slObjectGetState, 2},
		{"GetInterface", slObjectGetItf, 3},
		{"Destroy", slObjectDestroy, 6},
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
		{"CreateAudioPlayer", slEngineCreateAudioPlayer, 2},
		{"CreateAudioRecorder", slEngineCreateAudioRecorder, 3},
		{"CreateOutputMix", slEngineCreateOutputMix, 7},
	} {
		if tc.got != tc.want {
			t.Errorf("SLEngineItf.%s = %d, want %d", tc.name, tc.got, tc.want)
		}
	}
}

func TestSLPlayRecordBQVTables(t *testing.T) {
	if slPlaySetPlayState != 0 || slPlayGetPlayState != 1 {
		t.Errorf("SLPlayItf play-state indices wrong: %d/%d", slPlaySetPlayState, slPlayGetPlayState)
	}
	if slRecordSetRecordState != 0 || slRecordGetRecordState != 1 {
		t.Errorf("SLRecordItf record-state indices wrong: %d/%d", slRecordSetRecordState, slRecordGetRecordState)
	}
	if slBQEnqueue != 0 || slBQClear != 1 || slBQGetState != 2 {
		t.Errorf("SLBufferQueueItf indices wrong: %d/%d/%d", slBQEnqueue, slBQClear, slBQGetState)
	}
	if slConfigSetConfiguration != 0 {
		t.Errorf("SLAndroidConfigurationItf.SetConfiguration = %d, want 0", slConfigSetConfiguration)
	}
}

func TestSLConstants(t *testing.T) {
	for _, tc := range []struct {
		name string
		got  uint32
		want uint32
	}{
		{"SL_RESULT_SUCCESS", slResultSuccess, 0},
		{"SL_DATALOCATOR_IODEVICE", slDatalocatorIODevice, 0x00000003},
		{"SL_IODEVICE_AUDIOINPUT", slIODeviceAudioInput, 0x00000001},
		{"SL_DATALOCATOR_OUTPUTMIX", slDatalocatorOutputMix, 0x00000004},
		{"SL_DATAFORMAT_PCM", slDataformatPCM, 0x00000002},
		{"SL_SPEAKER_FRONT_CENTER", slSpeakerFrontCenter, 0x00000004},
		{"SL_BYTEORDER_LITTLEENDIAN", slByteorderLittleEndian, 0x00000002},
		{"SL_SAMPLINGRATE_48 (milli-Hz)", slSamplingrate48, 48000000},
		{"SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE", slDatalocatorAndroidBQ, 0x800007BD},
		{"SL_DEFAULTDEVICEID_AUDIOINPUT", slDefaultDeviceIDInput, 0xFFFFFFFF},
		{"SL_DEFAULTDEVICEID_AUDIOOUTPUT", slDefaultDeviceIDOutput, 0xFFFFFFFE},
		{"preset GENERIC", slRecordingPresetGeneric, 1},
		{"preset VOICE_COMMUNICATION", slRecordingPresetVoiceCommunication, 4},
		{"PLAYSTATE_STOPPED", slPlayStateStopped, 1},
		{"PLAYSTATE_PAUSED", slPlayStatePaused, 2},
		{"PLAYSTATE_PLAYING", slPlayStatePlaying, 3},
		{"RECORDSTATE_STOPPED", slRecordStateStopped, 1},
		{"RECORDSTATE_RECORDING", slRecordStateRecording, 2},
	} {
		if tc.got != tc.want {
			t.Errorf("%s = 0x%X, want 0x%X", tc.name, tc.got, tc.want)
		}
	}
	if slPCMSampleformatFixed16 != 0x0010 {
		t.Errorf("SL_PCMSAMPLEFORMAT_FIXED_16 = 0x%X, want 0x0010", slPCMSampleformatFixed16)
	}
	if slRecordingPresetKey != "androidRecordingPreset" {
		t.Errorf("preset key = %q, want androidRecordingPreset", slRecordingPresetKey)
	}
}

func TestSLStructLayouts64(t *testing.T) {
	if unsafe.Sizeof(unsafe.Pointer(nil)) != 8 {
		t.Skip("layout checks are 64-bit only")
	}
	if got := unsafe.Sizeof(slDataLocatorAndroidBQ{}); got != 8 {
		t.Errorf("SLDataLocator_AndroidSimpleBufferQueue size = %d, want 8", got)
	}
	if got := unsafe.Offsetof(slDataLocatorAndroidBQ{}.numBuffers); got != 4 {
		t.Errorf("numBuffers offset = %d, want 4", got)
	}
	if got := unsafe.Sizeof(slDataFormatPCM{}); got != 28 {
		t.Errorf("SLDataFormat_PCM size = %d, want 28", got)
	}
	if got := unsafe.Sizeof(slDataSource{}); got != 16 {
		t.Errorf("SLDataSource size = %d, want 16", got)
	}
	if got := unsafe.Offsetof(slDataLocatorOutputMix{}.outputMix); got != 8 {
		t.Errorf("SLDataLocator_OutputMix.outputMix offset = %d, want 8", got)
	}
	if got := unsafe.Sizeof(slDataLocatorOutputMix{}); got != 16 {
		t.Errorf("SLDataLocator_OutputMix size = %d, want 16", got)
	}
	if got := unsafe.Sizeof(slBQState{}); got != 8 {
		t.Errorf("SLBufferQueueState size = %d, want 8", got)
	}
	if got := unsafe.Sizeof(slDataLocatorIODevice{}); got != 24 {
		t.Errorf("SLDataLocator_IODevice size = %d, want 24", got)
	}
	if got := unsafe.Offsetof(slDataLocatorIODevice{}.device); got != 16 {
		t.Errorf("SLDataLocator_IODevice.device offset = %d, want 16", got)
	}
}

func TestJNIOrdinals(t *testing.T) {
	for _, tc := range []struct {
		name string
		got  int
		want int
	}{
		{"GetVersion", jniEnvGetVersion, 4},
		{"FindClass", jniEnvFindClass, 6},
		{"ExceptionOccurred", jniEnvExceptionOccurred, 15},
		{"ExceptionClear", jniEnvExceptionClear, 17},
		{"NewGlobalRef", jniEnvNewGlobalRef, 21},
		{"DeleteGlobalRef", jniEnvDeleteGlobalRef, 22},
		{"DeleteLocalRef", jniEnvDeleteLocalRef, 23},
		{"GetObjectClass", jniEnvGetObjectClass, 31},
		{"GetMethodID", jniEnvGetMethodID, 33},
		{"CallObjectMethodA", jniEnvCallObjectMethodA, 36},
		{"CallBooleanMethodA", jniEnvCallBooleanMethodA, 39},
		{"CallIntMethodA", jniEnvCallIntMethodA, 51},
		{"CallVoidMethodA", jniEnvCallVoidMethodA, 63},
		{"NewStringUTF", jniEnvNewStringUTF, 167},
		{"GetStringUTFChars", jniEnvGetStringUTFChars, 169},
		{"ReleaseStringUTFChars", jniEnvReleaseStringUTFChars, 170},
		{"GetArrayLength", jniEnvGetArrayLength, 171},
		{"NewObjectArray", jniEnvNewObjectArray, 172},
		{"SetObjectArrayElement", jniEnvSetObjectArrayElement, 174},
		{"ExceptionCheck", jniEnvExceptionCheck, 228},
	} {
		if tc.got != tc.want {
			t.Errorf("JNIEnv.%s = %d, want %d", tc.name, tc.got, tc.want)
		}
	}
	if jvmAttachCurrentThread != 4 || jvmDetachCurrentThread != 5 || jvmGetEnv != 6 {
		t.Errorf("JavaVM ordinals wrong: attach=%d detach=%d getenv=%d",
			jvmAttachCurrentThread, jvmDetachCurrentThread, jvmGetEnv)
	}
	if jniVersion16 != 0x00010006 {
		t.Errorf("JNI_VERSION_1_6 = 0x%X", jniVersion16)
	}
}

func TestBQRing(t *testing.T) {
	r := newBQRing(4, 1920)

	for i := 0; i < 4; i++ {
		slot, buf := r.next()
		if slot != i%4 {
			t.Fatalf("enqueue %d: slot %d, want %d", i, slot, i%4)
		}
		if len(buf) != 1920 {
			t.Fatalf("buffer len %d", len(buf))
		}
	}
	if got := r.completed(4); len(got) != 0 {
		t.Fatalf("completed(4) = %v, want empty", got)
	}
	if r.outstanding() != 4 {
		t.Fatalf("outstanding = %d, want 4", r.outstanding())
	}

	got := r.completed(2)
	if len(got) != 2 || got[0] != 0 || got[1] != 1 {
		t.Fatalf("completed(2) = %v, want [0 1]", got)
	}
	if r.outstanding() != 2 {
		t.Fatalf("outstanding = %d, want 2", r.outstanding())
	}

	for i := 0; i < 2; i++ {
		slot, _ := r.next()
		want := (4 + i) % 4
		if slot != want {
			t.Fatalf("re-enqueue %d: slot %d, want %d", i, slot, want)
		}
	}
	got = r.completed(3)
	if len(got) != 1 || got[0] != 2 {
		t.Fatalf("completed(3) = %v, want [2]", got)
	}

	r.reset()
	if r.outstanding() != 0 {
		t.Fatalf("after reset outstanding = %d", r.outstanding())
	}
	if got := r.completed(0); len(got) != 0 {
		t.Fatalf("after reset completed(0) = %v", got)
	}
}
