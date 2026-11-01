//go:build windows

package audio

import (
	"fmt"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

const audioAvailable = true

var (
	winmm = windows.NewLazySystemDLL("winmm.dll")

	procWaveOutOpen            = winmm.NewProc("waveOutOpen")
	procWaveOutPrepareHeader   = winmm.NewProc("waveOutPrepareHeader")
	procWaveOutWrite           = winmm.NewProc("waveOutWrite")
	procWaveOutUnprepareHeader = winmm.NewProc("waveOutUnprepareHeader")
	procWaveOutReset           = winmm.NewProc("waveOutReset")
	procWaveOutClose           = winmm.NewProc("waveOutClose")

	procWaveInOpen            = winmm.NewProc("waveInOpen")
	procWaveInPrepareHeader   = winmm.NewProc("waveInPrepareHeader")
	procWaveInAddBuffer       = winmm.NewProc("waveInAddBuffer")
	procWaveInUnprepareHeader = winmm.NewProc("waveInUnprepareHeader")
	procWaveInReset           = winmm.NewProc("waveInReset")
	procWaveInClose           = winmm.NewProc("waveInClose")
	procWaveInStart           = winmm.NewProc("waveInStart")
)

const (
	waveMapper    = 0xFFFFFFFF
	waveFormatPCM = 1
	whdrDone      = 0x00000001
	numPlayBufs   = 6
	numMicBufs    = 6
	playBufBytes  = 1920
	micBufBytes   = 1920
)

type waveFormatEx struct {
	formatTag      uint16
	channels       uint16
	samplesPerSec  uint32
	avgBytesPerSec uint32
	blockAlign     uint16
	bitsPerSample  uint16
	cbSize         uint16
}

type waveHdr struct {
	lpData          uintptr
	dwBufferLength  uint32
	dwBytesRecorded uint32
	dwUser          uintptr
	dwFlags         uint32
	dwLoops         uint32
	lpNext          uintptr
	reserved        uintptr
}

func pcmFormat() waveFormatEx {
	return waveFormatEx{
		formatTag:      waveFormatPCM,
		channels:       1,
		samplesPerSec:  48000,
		avgBytesPerSec: 96000,
		blockAlign:     2,
		bitsPerSample:  16,
	}
}

type buffer struct {
	hdr  waveHdr
	data []byte
}

func (b *buffer) prepare(in bool) error {
	b.hdr.lpData = uintptr(unsafe.Pointer(unsafe.SliceData(b.data)))
	b.hdr.dwBufferLength = uint32(len(b.data))
	b.hdr.dwFlags = 0
	var proc *windows.LazyProc
	if in {
		proc = procWaveInPrepareHeader
	} else {
		proc = procWaveOutPrepareHeader
	}
	r, _, _ := proc.Call(0, uintptr(unsafe.Pointer(&b.hdr)), unsafe.Sizeof(b.hdr))
	if r != 0 {
		return fmt.Errorf("audio: prepare header: winmm error %d", r)
	}
	return nil
}

func (b *buffer) unprepare(in bool) {
	var proc *windows.LazyProc
	if in {
		proc = procWaveInUnprepareHeader
	} else {
		proc = procWaveOutUnprepareHeader
	}
	for {
		r, _, _ := proc.Call(0, uintptr(unsafe.Pointer(&b.hdr)), unsafe.Sizeof(b.hdr))
		if r == 0 {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
}

type WinmmDevice struct {
	mu sync.Mutex

	playHandle uintptr
	playBufs   []buffer
	playFill   func(out []int16)
	playStop   chan struct{}
	playDone   chan struct{}

	micHandle uintptr
	micBufs   []buffer
	micCh     chan []byte
	micStop   chan struct{}
	micDone   chan struct{}
}

func OpenDevice() (Device, error) {
	return &WinmmDevice{}, nil
}

func (d *WinmmDevice) StartPlayback(fill func(out []int16)) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.playHandle != 0 {
		return fmt.Errorf("audio: playback already running")
	}
	wfx := pcmFormat()
	var h uintptr
	r, _, _ := procWaveOutOpen.Call(
		uintptr(unsafe.Pointer(&h)), waveMapper,
		uintptr(unsafe.Pointer(&wfx)), 0, 0, 0,
	)
	if r != 0 {
		return fmt.Errorf("audio: waveOutOpen: winmm error %d", r)
	}
	d.playHandle = h
	d.playFill = fill
	d.playBufs = make([]buffer, numPlayBufs)
	for i := range d.playBufs {
		d.playBufs[i].data = make([]byte, playBufBytes)
		if err := d.playBufs[i].prepare(false); err != nil {
			d.closePlaybackLocked()
			return err
		}
	}
	stop := make(chan struct{})
	done := make(chan struct{})
	d.playStop, d.playDone = stop, done

	pcm := make([]int16, playBufBytes/2)
	for i := range d.playBufs {
		fill(pcm)
		copy(d.playBufs[i].data, s16ToBytes(pcm))
		procWaveOutWrite.Call(h, uintptr(unsafe.Pointer(&d.playBufs[i].hdr)), unsafe.Sizeof(d.playBufs[i].hdr))
	}

	go d.playLoop()
	return nil
}

func (d *WinmmDevice) playLoop() {
	defer close(d.playDone)
	pcm := make([]int16, playBufBytes/2)
	for {
		select {
		case <-d.playStop:
			return
		default:
		}
		wrote := false
		d.mu.Lock()
		h := d.playHandle
		bufs := d.playBufs
		fill := d.playFill
		d.mu.Unlock()
		if h == 0 {
			return
		}
		for i := range bufs {
			if bufs[i].hdr.dwFlags&whdrDone != 0 {
				fill(pcm)
				copy(bufs[i].data, s16ToBytes(pcm))
				bufs[i].hdr.dwFlags &^= whdrDone
				bufs[i].hdr.dwBufferLength = playBufBytes
				procWaveOutWrite.Call(h, uintptr(unsafe.Pointer(&bufs[i].hdr)), unsafe.Sizeof(bufs[i].hdr))
				wrote = true
			}
		}
		if !wrote {
			time.Sleep(5 * time.Millisecond)
		}
	}
}

func (d *WinmmDevice) StopPlayback() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.closePlaybackLocked()
	if d.playDone != nil {
		<-d.playDone
		d.playStop, d.playDone = nil, nil
	}
}

func (d *WinmmDevice) closePlaybackLocked() {
	if d.playHandle == 0 {
		return
	}
	h := d.playHandle
	d.playHandle = 0
	if d.playStop != nil {
		close(d.playStop)
		d.playStop = nil
	}
	procWaveOutReset.Call(h)
	for i := range d.playBufs {
		d.playBufs[i].unprepare(false)
	}
	procWaveOutClose.Call(h)
	d.playBufs = nil
}

func (d *WinmmDevice) StartMic() (<-chan []byte, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.micHandle != 0 {
		return nil, fmt.Errorf("audio: mic already running")
	}
	wfx := pcmFormat()
	var h uintptr
	r, _, _ := procWaveInOpen.Call(
		uintptr(unsafe.Pointer(&h)), waveMapper,
		uintptr(unsafe.Pointer(&wfx)), 0, 0, 0,
	)
	if r != 0 {
		return nil, fmt.Errorf("audio: waveInOpen: winmm error %d", r)
	}
	d.micHandle = h
	d.micBufs = make([]buffer, numMicBufs)
	for i := range d.micBufs {
		d.micBufs[i].data = make([]byte, micBufBytes)
		if err := d.micBufs[i].prepare(true); err != nil {
			d.closeMicLocked()
			return nil, err
		}
	}
	frames := make(chan []byte, 8)
	stop := make(chan struct{})
	done := make(chan struct{})
	d.micCh, d.micStop, d.micDone = frames, stop, done

	for i := range d.micBufs {
		procWaveInAddBuffer.Call(h, uintptr(unsafe.Pointer(&d.micBufs[i].hdr)), unsafe.Sizeof(d.micBufs[i].hdr))
	}
	if r, _, _ := procWaveInStart.Call(h); r != 0 {
		d.closeMicLocked()
		return nil, fmt.Errorf("audio: waveInStart: winmm error %d", r)
	}

	go d.micLoop()
	return frames, nil
}

func (d *WinmmDevice) micLoop() {
	defer close(d.micDone)
	defer close(d.micCh)
	for {
		select {
		case <-d.micStop:
			return
		default:
		}
		d.mu.Lock()
		h := d.micHandle
		bufs := d.micBufs
		d.mu.Unlock()
		if h == 0 {
			return
		}
		delivered := false
		for i := range bufs {
			if bufs[i].hdr.dwFlags&whdrDone != 0 {
				n := int(bufs[i].hdr.dwBytesRecorded)
				if n > len(bufs[i].data) {
					n = len(bufs[i].data)
				}
				frame := make([]byte, n)
				copy(frame, bufs[i].data[:n])
				select {
				case d.micCh <- frame:
				case <-d.micStop:
					return
				}
				bufs[i].hdr.dwFlags &^= whdrDone
				bufs[i].hdr.dwBufferLength = micBufBytes
				bufs[i].hdr.dwBytesRecorded = 0
				procWaveInAddBuffer.Call(h, uintptr(unsafe.Pointer(&bufs[i].hdr)), unsafe.Sizeof(bufs[i].hdr))
				delivered = true
			}
		}
		if !delivered {
			time.Sleep(5 * time.Millisecond)
		}
	}
}

func (d *WinmmDevice) StopMic() {
	d.mu.Lock()
	d.closeMicLocked()
	d.mu.Unlock()
	if d.micDone != nil {
		<-d.micDone
		d.micStop, d.micDone = nil, nil
	}
}

func (d *WinmmDevice) closeMicLocked() {
	if d.micHandle == 0 {
		return
	}
	h := d.micHandle
	d.micHandle = 0
	if d.micStop != nil {
		close(d.micStop)
		d.micStop = nil
	}
	procWaveInReset.Call(h)
	for i := range d.micBufs {
		d.micBufs[i].unprepare(true)
	}
	procWaveInClose.Call(h)
	d.micBufs = nil
}

func (d *WinmmDevice) Close() {
	d.StopMic()
	d.StopPlayback()
}

func s16ToBytes(samples []int16) []byte {
	out := make([]byte, len(samples)*2)
	for i, s := range samples {
		out[2*i] = byte(s)
		out[2*i+1] = byte(s >> 8)
	}
	return out
}
