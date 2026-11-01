package gui

import "path/filepath"

type winGUID struct {
	Data1 uint32
	Data2 uint16
	Data3 uint16
	Data4 [8]byte
}

var (
	clsidShellLink = winGUID{
		Data1: 0x00021401, Data2: 0x0000, Data3: 0x0000,
		Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46},
	}
	iidIShellLinkW = winGUID{
		Data1: 0x000214F9, Data2: 0x0000, Data3: 0x0000,
		Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46},
	}
	iidIPersistFile = winGUID{
		Data1: 0x0000010B, Data2: 0x0000, Data3: 0x0000,
		Data4: [8]byte{0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46},
	}
	iidIPropertyStore = winGUID{
		Data1: 0x886D8EEB, Data2: 0x8CF2, Data3: 0x4446,
		Data4: [8]byte{0x8D, 0x02, 0xCD, 0xBA, 0x1D, 0xBD, 0xCF, 0x99},
	}
)

type propertyKey struct {
	fmtid winGUID
	pid   uint32
}

var iidIToastNotification2 = winGUID{
	Data1: 0x9DFB9FD1, Data2: 0x143A, Data3: 0x490E,
	Data4: [8]byte{0x90, 0xBF, 0xB9, 0xFB, 0xA7, 0x13, 0x2D, 0xE7},
}

var pkeyAppUserModelID = propertyKey{
	fmtid: winGUID{
		Data1: 0x9F4C2855, Data2: 0x9F79, Data3: 0x4B39,
		Data4: [8]byte{0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3},
	},
	pid: 5,
}

const propVariantVTLPWSTR = 31

type propVariant struct {
	vt  uint16
	_   [6]byte
	ptr uintptr
	_   [8]byte
}

const ourAUMID = "DarkReaperBoy.Uniclient"

func shortcutPath(appData string) string {
	if appData == "" {
		return ""
	}
	return filepath.Join(appData, "Microsoft", "Windows", "Start Menu", "Programs", "Uniclient.lnk")
}
