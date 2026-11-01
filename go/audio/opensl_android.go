//go:build android

package audio

import (
	"encoding/binary"
	"fmt"
	"runtime"
	"sync"
	"time"
	"unsafe"

	_ "gioui.org/app/permission/microphone"
	"github.com/ebitengine/purego"
)

const audioAvailable = true

const (
	openslLib        = "libOpenSLES.so"
	bqQueueDepth     = 4
	bqTargetInflight = 3
	pumpTick         = 5 * time.Millisecond
	frameSamples     = 960
	frameBytes       = frameSamples * 2
)

type openslDevice struct {
	mu  sync.Mutex
	lib uintptr

	iidEngine   unsafe.Pointer
	iidPlay     unsafe.Pointer
	iidRecord   unsafe.Pointer
	iidBQ       unsafe.Pointer
	iidConfig   unsafe.Pointer
	slCreateEng uintptr

	engineObj unsafe.Pointer
	engineItf unsafe.Pointer
	mixObj    unsafe.Pointer

	playOn   bool
	playObj  unsafe.Pointer
	playItf  unsafe.Pointer
	playBQ   unsafe.Pointer
	playRing *bqRing
	playStop chan struct{}
	playDone chan struct{}

	micOn   bool
	recObj  unsafe.Pointer
	recItf  unsafe.Pointer
	recBQ   unsafe.Pointer
	micRing *bqRing
	micCh   chan []byte
	micStop chan struct{}
	micDone chan struct{}
}

func slFn(itf unsafe.Pointer, idx int) uintptr {
	return *(*uintptr)(unsafe.Add(itf, idx*8))
}

func slCall(itf unsafe.Pointer, idx int, args ...uintptr) uintptr {
	full := make([]uintptr, 0, len(args)+1)
	full = append(full, uintptr(itf))
	full = append(full, args...)
	r1, _, _ := purego.SyscallN(slFn(itf, idx), full...)
	return r1
}

func slErr(where string, r uintptr) error {
	if uint32(r) == slResultSuccess {
		return nil
	}
	return fmt.Errorf("audio: OpenSL ES %s: 0x%X", where, uint32(r))
}

func slRealize(obj unsafe.Pointer) error {
	return slErr("Realize", slCall(obj, slObjectRealize, slBooleanFalse))
}

func slGetItf(obj, iid unsafe.Pointer) (unsafe.Pointer, error) {
	var out unsafe.Pointer
	err := slErr("GetInterface", slCall(obj, slObjectGetItf,
		uintptr(iid), uintptr(unsafe.Pointer(&out))))
	runtime.KeepAlive(out)
	runtime.KeepAlive(obj)
	runtime.KeepAlive(iid)
	if err != nil {
		return nil, err
	}
	if out == nil {
		return nil, fmt.Errorf("audio: OpenSL ES GetInterface returned nil")
	}
	return out, nil
}

func slDestroy(obj unsafe.Pointer) {
	if obj != nil {
		slCall(obj, slObjectDestroy)
	}
}

func slIIDDeref(lib uintptr, name string) (unsafe.Pointer, error) {
	sym, err := purego.Dlsym(lib, name)
	if err != nil {
		return nil, fmt.Errorf("audio: dlsym %s: %w", name, err)
	}
	iid := *(*unsafe.Pointer)(unsafe.Pointer(sym))
	if iid == nil {
		return nil, fmt.Errorf("audio: %s IID is nil", name)
	}
	return iid, nil
}

func openDevice() (device, error) {
	d := &openslDevice{}
	lib, err := purego.Dlopen(openslLib, purego.RTLD_NOW|purego.RTLD_GLOBAL)
	if err != nil {
		return nil, fmt.Errorf("audio: OpenSL ES unavailable: %w", err)
	}
	d.lib = lib

	for _, ld := range []struct {
		name string
		dst  *unsafe.Pointer
	}{
		{"SL_IID_ENGINE", &d.iidEngine},
		{"SL_IID_PLAY", &d.iidPlay},
		{"SL_IID_RECORD", &d.iidRecord},
		{"SL_IID_ANDROIDSIMPLEBUFFERQUEUE", &d.iidBQ},
		{"SL_IID_ANDROIDCONFIGURATION", &d.iidConfig},
	} {
		iid, err := slIIDDeref(lib, ld.name)
		if err != nil {
			return nil, err
		}
		*ld.dst = iid
	}

	fn, err := purego.Dlsym(lib, "slCreateEngine")
	if err != nil {
		return nil, fmt.Errorf("audio: slCreateEngine: %w", err)
	}
	d.slCreateEng = fn

	var engine unsafe.Pointer
	r1, _, _ := purego.SyscallN(fn,
		uintptr(unsafe.Pointer(&engine)), 0, 0, 0, 0, 0)
	if err := slErr("slCreateEngine", r1); err != nil {
		return nil, err
	}
	if err := slRealize(engine); err != nil {
		slDestroy(engine)
		return nil, err
	}
	d.engineObj = engine

	engineItf, err := slGetItf(engine, d.iidEngine)
	if err != nil {
		slDestroy(engine)
		return nil, err
	}
	d.engineItf = engineItf

	var mix unsafe.Pointer
	if err := slErr("CreateOutputMix", slCall(engineItf, slEngineCreateOutputMix,
		uintptr(unsafe.Pointer(&mix)), 0, 0, 0)); err != nil {
		slDestroy(engine)
		return nil, err
	}
	runtime.KeepAlive(mix)
	if err := slRealize(mix); err != nil {
		slDestroy(mix)
		slDestroy(engine)
		return nil, err
	}
	d.mixObj = mix
	return d, nil
}

func pcmFormat() slDataFormatPCM {
	return slDataFormatPCM{
		formatType:    slDataformatPCM,
		numChannels:   1,
		samplesPerSec: slSamplingrate48,
		bitsPerSample: slPCMSampleformatFixed16,
		containerSize: slPCMSampleformatFixed16,
		channelMask:   slSpeakerFrontCenter,
		endianness:    slByteorderLittleEndian,
	}
}

func bqEnqueue(bq unsafe.Pointer, buf []byte) error {
	err := slErr("Enqueue", slCall(bq, slBQEnqueue,
		uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf))))
	runtime.KeepAlive(buf)
	return err
}

func bqCount(bq unsafe.Pointer) int {
	var st slBQState
	if err := slErr("GetState", slCall(bq, slBQGetState,
		uintptr(unsafe.Pointer(&st)))); err != nil {
		return -1
	}
	runtime.KeepAlive(st)
	return int(st.count)
}

func (d *openslDevice) startPlayback(fill func(out []int16)) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.engineItf == nil {
		return ErrNoAudio
	}
	if d.playOn {
		return fmt.Errorf("audio: playback already running")
	}

	loc := slDataLocatorAndroidBQ{locatorType: slDatalocatorAndroidBQ, numBuffers: bqQueueDepth}
	pcm := pcmFormat()
	src := slDataSource{pLocator: unsafe.Pointer(&loc), pFormat: unsafe.Pointer(&pcm)}
	outLoc := slDataLocatorOutputMix{locatorType: slDatalocatorOutputMix, outputMix: d.mixObj}
	sink := slDataSource{pLocator: unsafe.Pointer(&outLoc), pFormat: nil}

	var player unsafe.Pointer
	iid := d.iidBQ
	req := uint32(slBooleanTrue)
	if err := slErr("CreateAudioPlayer", slCall(d.engineItf, slEngineCreateAudioPlayer,
		uintptr(unsafe.Pointer(&player)),
		uintptr(unsafe.Pointer(&src)), uintptr(unsafe.Pointer(&sink)),
		1, uintptr(unsafe.Pointer(&iid)), uintptr(unsafe.Pointer(&req)))); err != nil {
		return err
	}
	runtime.KeepAlive(player)
	runtime.KeepAlive(src)
	runtime.KeepAlive(sink)
	runtime.KeepAlive(loc)
	runtime.KeepAlive(pcm)
	runtime.KeepAlive(outLoc)
	runtime.KeepAlive(iid)
	runtime.KeepAlive(req)
	if err := slRealize(player); err != nil {
		slDestroy(player)
		return err
	}
	playItf, err := slGetItf(player, d.iidPlay)
	if err != nil {
		slDestroy(player)
		return err
	}
	bqItf, err := slGetItf(player, d.iidBQ)
	if err != nil {
		slDestroy(player)
		return err
	}
	if err := slErr("SetPlayState", slCall(playItf, slPlaySetPlayState, slPlayStatePlaying)); err != nil {
		slDestroy(player)
		return err
	}

	stop := make(chan struct{})
	done := make(chan struct{})
	d.playOn = true
	d.playObj, d.playItf, d.playBQ = player, playItf, bqItf
	d.playRing = newBQRing(bqQueueDepth, frameBytes)
	d.playStop, d.playDone = stop, done
	ring := d.playRing

	go func() {
		defer close(done)
		pcmS16 := make([]int16, frameSamples)
		ticker := time.NewTicker(pumpTick)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
			}
			count := bqCount(bqItf)
			if count < 0 {
				return
			}
			ring.completed(count)
			for ring.outstanding() < bqTargetInflight {
				_, buf := ring.next()
				fill(pcmS16)
				for i, s := range pcmS16 {
					binary.LittleEndian.PutUint16(buf[2*i:], uint16(s))
				}
				if err := bqEnqueue(bqItf, buf); err != nil {
					return
				}
			}
		}
	}()
	return nil
}

func (d *openslDevice) stopPlayback() {
	d.mu.Lock()
	if !d.playOn {
		d.mu.Unlock()
		return
	}
	d.playOn = false
	obj, playItf, bqItf := d.playObj, d.playItf, d.playBQ
	d.playObj, d.playItf, d.playBQ = nil, nil, nil
	stop, done := d.playStop, d.playDone
	d.playStop, d.playDone = nil, nil
	ring := d.playRing
	d.mu.Unlock()

	close(stop)
	<-done
	slCall(playItf, slPlaySetPlayState, slPlayStateStopped)
	slCall(bqItf, slBQClear)
	slDestroy(obj)
	ring.reset()
}

func (d *openslDevice) startMic() (<-chan []byte, error) {
	d.mu.Lock()
	if d.engineItf == nil {
		d.mu.Unlock()
		return nil, ErrNoAudio
	}
	if d.micOn {
		d.mu.Unlock()
		return nil, fmt.Errorf("audio: mic already running")
	}
	d.mu.Unlock()

	if err := ensureMicPermission(); err != nil {
		return nil, err
	}

	d.mu.Lock()
	defer d.mu.Unlock()
	if d.engineItf == nil || d.micOn {
		return nil, ErrNoAudio
	}

	inDev := slDataLocatorIODevice{
		locatorType: slDatalocatorIODevice,
		deviceType:  slIODeviceAudioInput,
		deviceID:    slDefaultDeviceIDInput,
	}
	src := slDataSource{pLocator: unsafe.Pointer(&inDev), pFormat: nil}
	loc := slDataLocatorAndroidBQ{locatorType: slDatalocatorAndroidBQ, numBuffers: bqQueueDepth}
	pcm := pcmFormat()
	sink := slDataSource{pLocator: unsafe.Pointer(&loc), pFormat: unsafe.Pointer(&pcm)}

	var rec unsafe.Pointer
	iids := []unsafe.Pointer{d.iidBQ, d.iidConfig}
	reqs := []uint32{slBooleanTrue, slBooleanTrue}
	if err := slErr("CreateAudioRecorder", slCall(d.engineItf, slEngineCreateAudioRecorder,
		uintptr(unsafe.Pointer(&rec)),
		uintptr(unsafe.Pointer(&src)), uintptr(unsafe.Pointer(&sink)),
		2, uintptr(unsafe.Pointer(&iids[0])), uintptr(unsafe.Pointer(&reqs[0])))); err != nil {
		return nil, err
	}
	runtime.KeepAlive(rec)
	runtime.KeepAlive(src)
	runtime.KeepAlive(sink)
	runtime.KeepAlive(inDev)
	runtime.KeepAlive(loc)
	runtime.KeepAlive(pcm)
	runtime.KeepAlive(iids)
	runtime.KeepAlive(reqs)

	if cfgItf, err := slGetItf(rec, d.iidConfig); err == nil {
		preset := uint32(slRecordingPresetVoiceCommunication)
		key, keep := cstr(slRecordingPresetKey)
		_ = slCall(cfgItf, slConfigSetConfiguration,
			uintptr(key), uintptr(unsafe.Pointer(&preset)), unsafe.Sizeof(preset))
		runtime.KeepAlive(keep)
		runtime.KeepAlive(preset)
	}

	if err := slRealize(rec); err != nil {
		slDestroy(rec)
		return nil, err
	}
	recItf, err := slGetItf(rec, d.iidRecord)
	if err != nil {
		slDestroy(rec)
		return nil, err
	}
	bqItf, err := slGetItf(rec, d.iidBQ)
	if err != nil {
		slDestroy(rec)
		return nil, err
	}
	if err := slErr("SetRecordState", slCall(recItf, slRecordSetRecordState, slRecordStateRecording)); err != nil {
		slDestroy(rec)
		return nil, err
	}

	frames := make(chan []byte, 16)
	stop := make(chan struct{})
	done := make(chan struct{})
	d.micOn = true
	d.recObj, d.recItf, d.recBQ = rec, recItf, bqItf
	d.micRing = newBQRing(bqQueueDepth, frameBytes)
	d.micCh, d.micStop, d.micDone = frames, stop, done
	ring := d.micRing

	go func() {
		defer close(done)
		for ring.outstanding() < bqQueueDepth {
			_, buf := ring.next()
			if err := bqEnqueue(bqItf, buf); err != nil {
				return
			}
		}
		ticker := time.NewTicker(pumpTick)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
			}
			count := bqCount(bqItf)
			if count < 0 {
				return
			}
			for _, slot := range ring.completed(count) {
				frame := make([]byte, frameBytes)
				copy(frame, ring.bufs[slot])
				select {
				case frames <- frame:
				case <-stop:
					return
				}
				reSlot, buf := ring.next()
				if reSlot != slot {
					return
				}
				if err := bqEnqueue(bqItf, buf); err != nil {
					return
				}
			}
		}
	}()
	return frames, nil
}

func (d *openslDevice) stopMic() {
	d.mu.Lock()
	if !d.micOn {
		d.mu.Unlock()
		return
	}
	d.micOn = false
	obj, recItf, bqItf := d.recObj, d.recItf, d.recBQ
	d.recObj, d.recItf, d.recBQ = nil, nil, nil
	stop, done, frames := d.micStop, d.micDone, d.micCh
	d.micCh, d.micStop, d.micDone = nil, nil, nil
	ring := d.micRing
	d.mu.Unlock()

	close(stop)
	<-done
	close(frames)
	slCall(recItf, slRecordSetRecordState, slRecordStateStopped)
	slCall(bqItf, slBQClear)
	slDestroy(obj)
	ring.reset()
}

func (d *openslDevice) close() {
	d.stopMic()
	d.stopPlayback()
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.mixObj != nil {
		slDestroy(d.mixObj)
		d.mixObj = nil
	}
	if d.engineObj != nil {
		slDestroy(d.engineObj)
		d.engineObj = nil
	}
	d.engineItf = nil
	if d.lib != 0 {
		purego.Dlclose(d.lib)
		d.lib = 0
	}
}
