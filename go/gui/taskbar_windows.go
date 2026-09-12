//go:build windows

package gui

// taskbar_windows.go — slice 153: the Windows taskbar overlay badge
// (tdesktop's unread count on the taskbar button). Pure-Go COM:
// ITaskbarList3::SetOverlayIcon (vtable index 18 — pinned against the
// mingw-w64 shobjidl.h ABI: IUnknown 0-2, ITaskbarList 3-7
// (HrInit/AddTab/DeleteTab/ActivateTab/SetActiveAlt),
// ITaskbarList2::MarkFullscreenWindow 8, ITaskbarList3 9-20 with
// SetOverlayIcon at 18). The overlay icon is composed in-process
// (rounded accent tile + the tray glyph digits) and converted to an
// HICON via CreateDIBSection + CreateIconIndirect.

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

	// CLSID_TaskbarList {56FDF344-FD6D-11d0-958A-006097C9A090}
	clsidTaskbarList = windows.GUID{
		Data1: 0x56FDF344, Data2: 0xFD6D, Data3: 0x11D0,
		Data4: [8]byte{0x95, 0x8A, 0x00, 0x60, 0x97, 0xC9, 0xA0, 0x90},
	}
	// IID_ITaskbarList3 {EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF}
	iidITaskbarList3 = windows.GUID{
		Data1: 0xEA1AFB91, Data2: 0x9E28, Data3: 0x4B86,
		Data4: [8]byte{0x90, 0xE9, 0x9E, 0x9F, 0x8A, 0x5E, 0xEF, 0xAF},
	}

	taskbarMu    sync.Mutex
	taskbarHwnd  uintptr // captured from the gio Win32ViewEvent
	taskbarList3 uintptr // ITaskbarList3* interface pointer
	taskbarReady bool
	taskbarLast  int     = -1 // last applied count
	taskbarHICON uintptr      // live overlay HICON (0 = none)
	taskbarColor uintptr      // bitmap/mask handles for cleanup
	taskbarMask  uintptr
)

// iconInfo mirrors the Win32 ICONINFO layout (x64).
type iconInfo struct {
	fIcon    uint32
	xHotspot uint32
	yHotspot uint32
	hbmMask  uintptr
	hbmColor uintptr
}

// bitmapInfoHeader mirrors BITMAPINFOHEADER.
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

// vtable slot offsets (uintptr-sized).
const (
	vtHrInit         = 3
	vtSetOverlayIcon = 18
)

// taskbarSetWindow captures the HWND from the gio ViewEvent and lazily
// initializes the COM interface (called from ListenEvents).
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
			return // COM unavailable: overlays simply stay off (§1.10)
		}
	}
	applyOverlayLocked(taskbarLast, defaultTaskbarAccent())
}

// defaultTaskbarAccent is the boot-time accent stand-in (the first real
// updateTray call replaces it).
func defaultTaskbarAccent() color.NRGBA { return color.NRGBA{R: 0x54, G: 0xA8, B: 0xF0, A: 0xFF} }

// initTaskbarList3Locked CoCreates ITaskbarList3 and calls HrInit.
func initTaskbarList3Locked() bool {
	// CoInitializeEx is idempotent-per-mode; S_FALSE (already init) and
	// RPC_E_CHANGED_MODE (STA already set by gio) are both fine here.
	procCoInitializeEx.Call(0, 2 /*COINIT_APARTMENTTHREADED*/)
	var itf uintptr
	r, _, _ := procCoCreateInstance.Call(
		uintptr(unsafe.Pointer(&clsidTaskbarList)),
		0,
		0x17, // CLSCTX_ALL
		uintptr(unsafe.Pointer(&iidITaskbarList3)),
		uintptr(unsafe.Pointer(&itf)),
	)
	if r != 0 || itf == 0 {
		return false
	}
	// vtable call HrInit()
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

// procRelease calls IUnknown::Release (vtable index 2).
func procRelease(itf uintptr) {
	if itf == 0 {
		return
	}
	lpVtbl := *(*uintptr)(unsafe.Pointer(itf))
	release := *(*uintptr)(unsafe.Pointer(lpVtbl + 2*unsafe.Sizeof(uintptr(0))))
	syscall.SyscallN(release, itf)
}

// updateTaskbarBadge applies the unread count to the taskbar button.
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

// applyOverlayLocked renders + installs (or clears) the overlay icon.
func applyOverlayLocked(count int, accent color.NRGBA) {
	taskbarLast = count
	taskbarAccentCache = accent
	// drop the previous overlay icon
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

// overlayDescription builds the accessibility description ("3 unread").
func overlayDescription(count int) *uint16 {
	desc := "Unread messages"
	if count > 0 {
		desc = itoa(count) + " unread messages"
	}
	p, _ := windows.UTF16PtrFromString(desc)
	return p
}

// setOverlayIcon calls ITaskbarList3::SetOverlayIcon (vtable 18).
func setOverlayIcon(hicon uintptr, desc *uint16) {
	if taskbarList3 == 0 || taskbarHwnd == 0 {
		return
	}
	lpVtbl := *(*uintptr)(unsafe.Pointer(taskbarList3))
	setOverlay := *(*uintptr)(unsafe.Pointer(lpVtbl + vtSetOverlayIcon*unsafe.Sizeof(uintptr(0))))
	syscall.SyscallN(setOverlay, taskbarList3, taskbarHwnd, hicon, uintptr(unsafe.Pointer(desc)))
}

// destroyOverlayIconLocked frees the live overlay HICON + bitmaps.
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

// stopTaskbar clears the overlay and releases the COM reference (app
// exit / tray toggle off).
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

// rgbaToHICON converts an RGBA image into an HICON via
// CreateDIBSection (32bpp top-down) + CreateIconIndirect.
func rgbaToHICON(img *image.NRGBA) (hicon, bmColor, bmMask uintptr) {
	w := img.Bounds().Dx()
	h := img.Bounds().Dy()
	if w <= 0 || h <= 0 {
		return 0, 0, 0
	}
	// color bitmap: 32bpp BGRA, top-down (negative height)
	var bits uintptr
	bi := struct {
		header bitmapInfoHeader
		colors [1]uint32 // unused for 32bpp
	}{}
	bi.header.Size = uint32(unsafe.Sizeof(bi.header))
	bi.header.Width = int32(w)
	bi.header.Height = int32(-h) // top-down
	bi.header.Planes = 1
	bi.header.BitCount = 32
	bi.header.Compression = 0 // BI_RGB
	bmColor, _, _ = procCreateDIBSection.Call(
		0, uintptr(unsafe.Pointer(&bi)), 0, /*DIB_RGB_COLORS*/
		uintptr(unsafe.Pointer(&bits)), 0, 0,
	)
	if bmColor == 0 || bits == 0 {
		return 0, 0, 0
	}
	// fill BGRA (RGBA → BGRA)
	dst := (*[1 << 30]byte)(unsafe.Pointer(bits))[:w*h*4]
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			i := img.PixOffset(x, y)
			j := (y*w + x) * 4
			dst[j] = img.Pix[i+2]   // B
			dst[j+1] = img.Pix[i+1] // G
			dst[j+2] = img.Pix[i]   // R
			dst[j+3] = img.Pix[i+3] // A
		}
	}
	// mask bitmap: 1bpp monochrome (all visible — the color alpha rules)
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
