// SPDX-License-Identifier: Unlicense OR MIT

package audio

import (
	"testing"
	"unsafe"
)

// The expected values below are an INDEPENDENT transcription of the official
// headers (AOSP frameworks/wilhelm include/SLES/{OpenSLES.h,
// OpenSLES_Android.h, OpenSLES_AndroidConfiguration.h}, fetched 2026-09-14),
// and of jni.h's JNINativeInterface_/JNIInvokeInterface_ tables. A typo in
// either the constants or this table fails the test — the two were written
// from the headers separately.

func TestSLObjectItfVTable(t *testing.T) {
	// struct SLObjectItf_ order: Realize, Resume, GetState, GetInterface,
	// RegisterCallback, AbortAsyncOperation, Destroy, SetPriority,
	// GetPriority, SetLossOfControlInterfaces.
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
	// struct SLEngineItf_ order: CreateLEDDevice(0), CreateVibraDevice(1),
	// CreateAudioPlayer(2), CreateAudioRecorder(3), CreateMidiPlayer(4),
	// CreateListener(5), Create3DGroup(6), CreateOutputMix(7),
	// CreateMetadataExtractor(8), CreateExtensionObject(9), ...
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
	// SLPlayItf_: SetPlayState(0), GetPlayState(1), GetDuration(2),
	// GetPosition(3), RegisterCallback(4), ...
	if slPlaySetPlayState != 0 || slPlayGetPlayState != 1 {
		t.Errorf("SLPlayItf play-state indices wrong: %d/%d", slPlaySetPlayState, slPlayGetPlayState)
	}
	// SLRecordItf_: SetRecordState(0), GetRecordState(1), SetDurationLimit(2)...
	if slRecordSetRecordState != 0 || slRecordGetRecordState != 1 {
		t.Errorf("SLRecordItf record-state indices wrong: %d/%d", slRecordSetRecordState, slRecordGetRecordState)
	}
	// SLBufferQueueItf_: Enqueue(0), Clear(1), GetState(2), RegisterCallback(3).
	if slBQEnqueue != 0 || slBQClear != 1 || slBQGetState != 2 {
		t.Errorf("SLBufferQueueItf indices wrong: %d/%d/%d", slBQEnqueue, slBQClear, slBQGetState)
	}
	// SLAndroidConfigurationItf_: SetConfiguration(0), GetConfiguration(1)...
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
	// 64-bit pointer model — android amd64/arm64 only ship as such.
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
	// JNINativeInterface_: 4 reserved slots, then GetVersion(4), DefineClass(5),
	// FindClass(6), FromReflectedMethod(7), FromReflectedField(8),
	// ToReflectedMethod(9), GetSuperclass(10), IsAssignableFrom(11),
	// ToReflectedField(12), Throw(13), ThrowNew(14), ExceptionOccurred(15),
	// ExceptionDescribe(16), ExceptionClear(17), FatalError(18),
	// PushLocalFrame(19), PopLocalFrame(20), NewGlobalRef(21),
	// DeleteGlobalRef(22), DeleteLocalRef(23), IsSameObject(24),
	// NewLocalRef(25), EnsureLocalCapacity(26), AllocObject(27),
	// NewObject(28), NewObjectV(29), NewObjectA(30), GetObjectClass(31),
	// IsInstanceOf(32), GetMethodID(33), then Call*Method triplets:
	// Object 34/35/36, Boolean 37/38/39, Byte 40..42, Char 43..45,
	// Short 46..48, Int 49/50/51, Long 52..54, Float 55..57, Double 58..60,
	// Void 61/62/63. Strings/arrays: NewString(163), NewStringUTF(167),
	// GetStringUTFChars(169), ReleaseStringUTFChars(170), GetArrayLength(171),
	// NewObjectArray(172), SetObjectArrayElement(174). ExceptionCheck(228).
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
	// JNIInvokeInterface_: reserved(0..2), DestroyJavaVM(3),
	// AttachCurrentThread(4), DetachCurrentThread(5), GetEnv(6),
	// AttachCurrentThreadAsDaemon(7).
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

	// Fill the queue: 4 enqueues, nothing completed.
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

	// Queue drains two buffers → the two oldest slots complete in order.
	got := r.completed(2)
	if len(got) != 2 || got[0] != 0 || got[1] != 1 {
		t.Fatalf("completed(2) = %v, want [0 1]", got)
	}
	if r.outstanding() != 2 {
		t.Fatalf("outstanding = %d, want 2", r.outstanding())
	}

	// Re-enqueue wraps around the ring.
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

	// Reset zeroes the accounting.
	r.reset()
	if r.outstanding() != 0 {
		t.Fatalf("after reset outstanding = %d", r.outstanding())
	}
	if got := r.completed(0); len(got) != 0 {
		t.Fatalf("after reset completed(0) = %v", got)
	}
}
