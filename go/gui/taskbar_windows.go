//go:build windows

package gui

import (
	"image"
	"image/color"
	"sync"
	"syscall"
	"unsafe"

	"gioui.org/app"

	"golang.org/x/sys/windows"
)

var (
	ole32                = windows.NewLazySystemDLL("ole32.dll")
	gdi32                = windows.NewLazySystemDLL("gdi32.dll")
	procCoInitializeEx   = ole32.NewProc("CoInitializeEx")
	procCoCreateInstance = ole32.NewProc("CoCreateInstance")

	procCreateDIBSection = gdi32.NewProc("CreateDIBSection")
	procCreateBitmap     = gdi32.NewProc("CreateBitmap")
	procDeleteObject     = gdi32.NewProc("DeleteObject")

	procCreateIconIndirect = windows.NewLazySystemDLL("user32.dll").NewProc("CreateIconIndirect")
	procDestroyIcon        = windows.NewLazySystemDLL("user32.dll").NewProc("DestroyIcon")

	clsidTaskbarList = windows.GUID{
		Data1: 0x56FDF344, Data2: 0xFD6D, Data3: 0x11D0,
		Data4: [8]byte{0x95, 0x8A, 0x00, 0x60, 0x97, 0xC9, 0xA0, 0x90},
	}
	iidITaskbarList3 = windows.GUID{
		Data1: 0xEA1AFB91, Data2: 0x9E28, Data3: 0x4B86,
		Data4: [8]byte{0x90, 0xE9, 0x9E, 0x9F, 0x8A, 0x5E, 0xEF, 0xAF},
	}

	taskbarMu    sync.Mutex
	taskbarHwnd  uintptr
	taskbarList3 uintptr
	taskbarReady bool
	taskbarLast  int = -1
	taskbarHICON uintptr
	taskbarColor uintptr
	taskbarMask  uintptr
)

type iconInfo struct {
	fIcon    uint32
	xHotspot uint32
	yHotspot uint32
	hbmMask  uintptr
	hbmColor uintptr
}

type bitmapInfoHeader struct {
	Size          uint32
	Width         int32
	Height        int32
	Planes        uint16
	BitCount      uint16
	Compression   uint32
	SizeImage     uint32
	XPelsPerMeter int32
	YPelsPerMeter int32
	ClrUsed       uint32
	ClrImportant  uint32
}

const (
	vtHrInit         = 3
	vtSetOverlayIcon = 18
)

func taskbarSetWindow(ev app.ViewEvent) {
	w32, ok := ev.(app.Win32ViewEvent)
	if !ok || w32.HWND == 0 {
		return
	}
	taskbarMu.Lock()
	defer taskbarMu.Unlock()
	taskbarHwnd = w32.HWND
	if taskbarList3 == 0 {
		if !initTaskbarList3Locked() {
			return
		}
	}
	applyOverlayLocked(taskbarLast, defaultTaskbarAccent())
}

func defaultTaskbarAccent() color.NRGBA { return color.NRGBA{R: 0x54, G: 0xA8, B: 0xF0, A: 0xFF} }

func initTaskbarList3Locked() bool {
	procCoInitializeEx.Call(0, 2)
	var itf uintptr
	r, _, _ := procCoCreateInstance.Call(
		uintptr(unsafe.Pointer(&clsidTaskbarList)),
		0,
		0x17,
		uintptr(unsafe.Pointer(&iidITaskbarList3)),
		uintptr(unsafe.Pointer(&itf)),
	)
	if r != 0 || itf == 0 {
		return false
	}
	lpVtbl := *(*uintptr)(unsafe.Pointer(itf))
	hrInit := *(*uintptr)(unsafe.Pointer(lpVtbl + vtHrInit*unsafe.Sizeof(uintptr(0))))
	r2, _, _ := syscall.SyscallN(hrInit, itf)
	if r2 != 0 {
		procRelease(itf)
		return false
	}
	taskbarList3 = itf
	taskbarReady = true
	return true
}

func procRelease(itf uintptr) {
	if itf == 0 {
		return
	}
	lpVtbl := *(*uintptr)(unsafe.Pointer(itf))
	release := *(*uintptr)(unsafe.Pointer(lpVtbl + 2*unsafe.Sizeof(uintptr(0))))
	syscall.SyscallN(release, itf)
}

func updateTaskbarBadge(count int, accent color.NRGBA) {
	taskbarMu.Lock()
	defer taskbarMu.Unlock()
	if !taskbarReady || taskbarHwnd == 0 {
		return
	}
	if count == taskbarLast && accent == taskbarAccentCache {
		return
	}
	applyOverlayLocked(count, accent)
}

var taskbarAccentCache = color.NRGBA{}

func applyOverlayLocked(count int, accent color.NRGBA) {
	taskbarLast = count
	taskbarAccentCache = accent
	setOverlayIcon(0, nil)
	destroyOverlayIconLocked()
	if count <= 0 {
		return
	}
	px := 24
	img := renderTaskbarOverlayRGBA(px, accent, count)
	hicon, bmColor, bmMask := rgbaToHICON(img)
	if hicon == 0 {
		return
	}
	taskbarHICON, taskbarColor, taskbarMask = hicon, bmColor, bmMask
	setOverlayIcon(hicon, overlayDescription(count))
}

func overlayDescription(count int) *uint16 {
	desc := "Unread messages"
	if count > 0 {
		desc = itoa(count) + " unread messages"
	}
	p, _ := windows.UTF16PtrFromString(desc)
	return p
}

func setOverlayIcon(hicon uintptr, desc *uint16) {
	if taskbarList3 == 0 || taskbarHwnd == 0 {
		return
	}
	lpVtbl := *(*uintptr)(unsafe.Pointer(taskbarList3))
	setOverlay := *(*uintptr)(unsafe.Pointer(lpVtbl + vtSetOverlayIcon*unsafe.Sizeof(uintptr(0))))
	syscall.SyscallN(setOverlay, taskbarList3, taskbarHwnd, hicon, uintptr(unsafe.Pointer(desc)))
}

func destroyOverlayIconLocked() {
	if taskbarHICON != 0 {
		procDestroyIcon.Call(taskbarHICON)
		taskbarHICON = 0
	}
	if taskbarColor != 0 {
		procDeleteObject.Call(taskbarColor)
		taskbarColor = 0
	}
	if taskbarMask != 0 {
		procDeleteObject.Call(taskbarMask)
		taskbarMask = 0
	}
}

func stopTaskbar() {
	taskbarMu.Lock()
	defer taskbarMu.Unlock()
	setOverlayIcon(0, nil)
	destroyOverlayIconLocked()
	if taskbarList3 != 0 {
		procRelease(taskbarList3)
		taskbarList3 = 0
		taskbarReady = false
	}
}

func rgbaToHICON(img *image.NRGBA) (hicon, bmColor, bmMask uintptr) {
	w := img.Bounds().Dx()
	h := img.Bounds().Dy()
	if w <= 0 || h <= 0 {
		return 0, 0, 0
	}
	var bits uintptr
	bi := struct {
		header bitmapInfoHeader
		colors [1]uint32
	}{}
	bi.header.Size = uint32(unsafe.Sizeof(bi.header))
	bi.header.Width = int32(w)
	bi.header.Height = int32(-h)
	bi.header.Planes = 1
	bi.header.BitCount = 32
	bi.header.Compression = 0
	bmColor, _, _ = procCreateDIBSection.Call(
		0, uintptr(unsafe.Pointer(&bi)), 0,
		uintptr(unsafe.Pointer(&bits)), 0, 0,
	)
	if bmColor == 0 || bits == 0 {
		return 0, 0, 0
	}
	dst := (*[1 << 30]byte)(unsafe.Pointer(bits))[:w*h*4]
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			i := img.PixOffset(x, y)
			j := (y*w + x) * 4
			dst[j] = img.Pix[i+2]
			dst[j+1] = img.Pix[i+1]
			dst[j+2] = img.Pix[i]
			dst[j+3] = img.Pix[i+3]
		}
	}
	bmMask, _, _ = procCreateBitmap.Call(uintptr(w), uintptr(h), 1, 1, 0)
	if bmMask == 0 {
		procDeleteObject.Call(bmColor)
		return 0, 0, 0
	}
	info := iconInfo{
		fIcon:    1,
		hbmMask:  bmMask,
		hbmColor: bmColor,
	}
	hicon, _, _ = procCreateIconIndirect.Call(uintptr(unsafe.Pointer(&info)))
	return hicon, bmColor, bmMask
}
