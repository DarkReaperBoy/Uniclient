package material

import "image/color"

type Kind int

const (
	Light Kind = iota
	Dark
	Amoled
)

type Scheme struct {
	Primary                 color.NRGBA
	OnPrimary               color.NRGBA
	PrimaryContainer        color.NRGBA
	OnPrimaryContainer      color.NRGBA
	Secondary               color.NRGBA
	OnSecondary             color.NRGBA
	SecondaryContainer      color.NRGBA
	OnSecondaryContainer    color.NRGBA
	Tertiary                color.NRGBA
	OnTertiary              color.NRGBA
	TertiaryContainer       color.NRGBA
	OnTertiaryContainer     color.NRGBA
	Error                   color.NRGBA
	OnError                 color.NRGBA
	ErrorContainer          color.NRGBA
	OnErrorContainer        color.NRGBA
	Background              color.NRGBA
	OnBackground            color.NRGBA
	Surface                 color.NRGBA
	OnSurface               color.NRGBA
	SurfaceVariant          color.NRGBA
	OnSurfaceVariant        color.NRGBA
	SurfaceDim              color.NRGBA
	SurfaceBright           color.NRGBA
	SurfaceContainerLowest  color.NRGBA
	SurfaceContainerLow     color.NRGBA
	SurfaceContainer        color.NRGBA
	SurfaceContainerHigh    color.NRGBA
	SurfaceContainerHighest color.NRGBA
	Outline                 color.NRGBA
	OutlineVariant          color.NRGBA
	InverseSurface          color.NRGBA
	InverseOnSurface        color.NRGBA
	InversePrimary          color.NRGBA
	Scrim                   color.NRGBA
	SurfaceTint             color.NRGBA
}

func nrgba(r, g, b uint8) color.NRGBA {
	return color.NRGBA{R: r, G: g, B: b, A: 0xFF}
}

var schemeLight = Scheme{
	Primary:                 nrgba(0x67, 0x50, 0xA4),
	OnPrimary:               nrgba(0xFF, 0xFF, 0xFF),
	PrimaryContainer:        nrgba(0xEA, 0xDD, 0xFF),
	OnPrimaryContainer:      nrgba(0x21, 0x00, 0x5D),
	Secondary:               nrgba(0x62, 0x5B, 0x71),
	OnSecondary:             nrgba(0xFF, 0xFF, 0xFF),
	SecondaryContainer:      nrgba(0xE8, 0xDE, 0xF8),
	OnSecondaryContainer:    nrgba(0x1D, 0x19, 0x2B),
	Tertiary:                nrgba(0x7D, 0x52, 0x60),
	OnTertiary:              nrgba(0xFF, 0xFF, 0xFF),
	TertiaryContainer:       nrgba(0xFF, 0xD8, 0xE4),
	OnTertiaryContainer:     nrgba(0x31, 0x11, 0x1D),
	Error:                   nrgba(0xB3, 0x26, 0x1E),
	OnError:                 nrgba(0xFF, 0xFF, 0xFF),
	ErrorContainer:          nrgba(0xF9, 0xDE, 0xDC),
	OnErrorContainer:        nrgba(0x41, 0x0E, 0x0B),
	Background:              nrgba(0xFE, 0xF7, 0xFF),
	OnBackground:            nrgba(0x1D, 0x1B, 0x20),
	Surface:                 nrgba(0xFE, 0xF7, 0xFF),
	OnSurface:               nrgba(0x1D, 0x1B, 0x20),
	SurfaceVariant:          nrgba(0xE7, 0xE0, 0xEC),
	OnSurfaceVariant:        nrgba(0x49, 0x45, 0x4F),
	SurfaceDim:              nrgba(0xDE, 0xD8, 0xE1),
	SurfaceBright:           nrgba(0xFE, 0xF7, 0xFF),
	SurfaceContainerLowest:  nrgba(0xFF, 0xFF, 0xFF),
	SurfaceContainerLow:     nrgba(0xF7, 0xF2, 0xFA),
	SurfaceContainer:        nrgba(0xF3, 0xED, 0xF7),
	SurfaceContainerHigh:    nrgba(0xEC, 0xE6, 0xF0),
	SurfaceContainerHighest: nrgba(0xE6, 0xE0, 0xE9),
	Outline:                 nrgba(0x79, 0x74, 0x7E),
	OutlineVariant:          nrgba(0xCA, 0xC4, 0xD0),
	InverseSurface:          nrgba(0x32, 0x2F, 0x35),
	InverseOnSurface:        nrgba(0xF5, 0xEF, 0xF7),
	InversePrimary:          nrgba(0xD0, 0xBC, 0xFF),
	Scrim:                   nrgba(0x00, 0x00, 0x00),
	SurfaceTint:             nrgba(0x67, 0x50, 0xA4),
}

var schemeDark = Scheme{
	Primary:                 nrgba(0xD0, 0xBC, 0xFF),
	OnPrimary:               nrgba(0x38, 0x1E, 0x72),
	PrimaryContainer:        nrgba(0x4F, 0x37, 0x8B),
	OnPrimaryContainer:      nrgba(0xEA, 0xDD, 0xFF),
	Secondary:               nrgba(0xCC, 0xC2, 0xDC),
	OnSecondary:             nrgba(0x33, 0x2D, 0x41),
	SecondaryContainer:      nrgba(0x4A, 0x44, 0x58),
	OnSecondaryContainer:    nrgba(0xE8, 0xDE, 0xF8),
	Tertiary:                nrgba(0xEF, 0xB8, 0xC8),
	OnTertiary:              nrgba(0x49, 0x25, 0x32),
	TertiaryContainer:       nrgba(0x63, 0x3B, 0x48),
	OnTertiaryContainer:     nrgba(0xFF, 0xD8, 0xE4),
	Error:                   nrgba(0xF2, 0xB8, 0xB5),
	OnError:                 nrgba(0x60, 0x14, 0x10),
	ErrorContainer:          nrgba(0x8C, 0x1D, 0x18),
	OnErrorContainer:        nrgba(0xF9, 0xDE, 0xDC),
	Background:              nrgba(0x14, 0x12, 0x18),
	OnBackground:            nrgba(0xE6, 0xE0, 0xE9),
	Surface:                 nrgba(0x14, 0x12, 0x18),
	OnSurface:               nrgba(0xE6, 0xE0, 0xE9),
	SurfaceVariant:          nrgba(0x49, 0x45, 0x4F),
	OnSurfaceVariant:        nrgba(0xCA, 0xC4, 0xD0),
	SurfaceDim:              nrgba(0x14, 0x12, 0x18),
	SurfaceBright:           nrgba(0x3B, 0x38, 0x3E),
	SurfaceContainerLowest:  nrgba(0x0F, 0x0D, 0x13),
	SurfaceContainerLow:     nrgba(0x1D, 0x1B, 0x20),
	SurfaceContainer:        nrgba(0x21, 0x1F, 0x26),
	SurfaceContainerHigh:    nrgba(0x2B, 0x29, 0x30),
	SurfaceContainerHighest: nrgba(0x36, 0x34, 0x3B),
	Outline:                 nrgba(0x93, 0x8F, 0x99),
	OutlineVariant:          nrgba(0x49, 0x45, 0x4F),
	InverseSurface:          nrgba(0xE6, 0xE0, 0xE9),
	InverseOnSurface:        nrgba(0x32, 0x2F, 0x35),
	InversePrimary:          nrgba(0x67, 0x50, 0xA4),
	Scrim:                   nrgba(0x00, 0x00, 0x00),
	SurfaceTint:             nrgba(0xD0, 0xBC, 0xFF),
}

var pureBlack = nrgba(0x00, 0x00, 0x00)

func SchemeFor(kind Kind) Scheme {
	switch kind {
	case Light:
		return schemeLight
	case Dark:
		return schemeDark
	case Amoled:
		amoled := schemeDark
		amoled.Background = pureBlack
		amoled.Surface = pureBlack
		amoled.SurfaceDim = pureBlack
		amoled.SurfaceContainerLowest = pureBlack
		return amoled
	}
	return schemeLight
}
