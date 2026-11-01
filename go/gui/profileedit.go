package gui

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/x/explorer"

	"uniclient/engine"
)

type profileEditState struct {
	accountID   string
	loaded      bool
	displayName string
	username    string
	bio         string
	phone       string
	avatarPath  string
	bdayDay     int
	bdayMonth   int
	bdayYear    int
}

var (
	profileUserEd   widget.Editor
	profileBioEd    widget.Editor
	profileBdayD    widget.Editor
	profileBdayM    widget.Editor
	profileBdayY    widget.Editor
	profilePhotoBtn widget.Clickable
	profileUserBtn  widget.Clickable
	profileBioBtn   widget.Clickable
	profileBdayBtn  widget.Clickable
	profileBackBtn  widget.Clickable

	profileEdSynced atomic.Bool
)

func init() {
	profileUserEd.SingleLine = true
	profileBioEd.SingleLine = true
	profileBioEd.MaxLen = 140
	profileBdayD.SingleLine = true
	profileBdayM.SingleLine = true
	profileBdayY.SingleLine = true
}

func (a *App) openProfileEdit(accountID string) {
	a.mu.Lock()
	a.profileEdit = &profileEditState{accountID: accountID}
	a.businessPage = nil
	a.stickerMgr = nil
	a.folderMgr = nil
	a.premiumPage = nil
	a.starsPage = nil
	a.mu.Unlock()
	profileEdSynced.Store(false)
	go a.loadProfileEdit(accountID)
	a.invalidate()
}

func (a *App) closeProfileEdit() {
	a.mu.Lock()
	a.profileEdit = nil
	a.mu.Unlock()
	profileEdSynced.Store(false)
	a.invalidate()
}

func (a *App) loadProfileEdit(accountID string) {
	st := &profileEditState{accountID: accountID}
	for _, acc := range a.eng.ListAccounts() {
		if acc.ID == accountID {
			st.displayName = acc.DisplayName
			st.username = acc.Username
			st.phone = acc.Phone
			st.avatarPath = acc.AvatarPath
			break
		}
	}
	if acc, ok := accountByIDSnapshot(a, accountID); ok && acc.SelfUserID != "" {
		if p, err := a.eng.GetUserProfile(accountID, acc.SelfUserID); err == nil && p != nil {
			if p.Bio != "" {
				st.bio = p.Bio
			}
			if p.Username != "" {
				st.username = p.Username
			}
			if p.Phone != "" {
				st.phone = p.Phone
			}
			if p.DisplayName != "" {
				st.displayName = p.DisplayName
			}
			if p.BirthdayDay > 0 {
				st.bdayDay = p.BirthdayDay
				st.bdayMonth = p.BirthdayMonth
				st.bdayYear = p.BirthdayYear
			}
		}
	}
	if bio, err := a.eng.GetSelfBio(accountID); err == nil && bio != "" {
		st.bio = bio
	}
	if d, m, y, err := a.eng.GetSelfBirthday(accountID); err == nil && d > 0 {
		st.bdayDay, st.bdayMonth, st.bdayYear = d, m, y
	}
	st.loaded = true
	a.mu.Lock()
	if a.profileEdit != nil && a.profileEdit.accountID == accountID {
		a.profileEdit = st
	}
	a.mu.Unlock()
	profileEdSynced.Store(false)
	a.invalidate()
}

func accountByIDSnapshot(a *App, id string) (engine.AccountInfo, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	for _, acc := range a.accounts {
		if acc.ID == id {
			return acc, true
		}
	}
	return engine.AccountInfo{}, false
}

func validateUsername(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" {
		return ""
	}
	switch {
	case len(s) < 5:
		return "at least 5 characters"
	case len(s) > 32:
		return "at most 32 characters"
	}
	if s[0] < 'a' || s[0] > 'z' {
		return "must start with a letter"
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_') {
			return "only letters, digits and _"
		}
	}
	return ""
}

func validateBio(s string) string {
	if len([]rune(s)) > 70 {
		return "at most 70 characters"
	}
	return ""
}

func parseBirthday(ds, ms, ys string) (int, int, int, string) {
	ds, ms, ys = strings.TrimSpace(ds), strings.TrimSpace(ms), strings.TrimSpace(ys)
	if ds == "" && ms == "" && ys == "" {
		return 0, 0, 0, ""
	}
	if ds == "" || ms == "" {
		return 0, 0, 0, "day and month are required"
	}
	d, err := strconv.Atoi(ds)
	if err != nil {
		return 0, 0, 0, "day must be a number"
	}
	m, err := strconv.Atoi(ms)
	if err != nil {
		return 0, 0, 0, "month must be a number"
	}
	y := 0
	if ys != "" {
		y, err = strconv.Atoi(ys)
		if err != nil {
			return 0, 0, 0, "year must be a number"
		}
	}
	if d < 1 || d > 31 {
		return 0, 0, 0, "day must be 1-31"
	}
	if m < 1 || m > 12 {
		return 0, 0, 0, "month must be 1-12"
	}
	if y != 0 && (y < 1800 || y > time.Now().Year()) {
		return 0, 0, 0, "year looks wrong"
	}
	dim := 31
	switch m {
	case 2:
		dim = 29
	case 4, 6, 9, 11:
		dim = 30
	}
	if d > dim {
		return 0, 0, 0, "that month has fewer days"
	}
	return d, m, y, ""
}

var monthNames = [13]string{"", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

func birthdayLabel(d, m, y int) string {
	if d == 0 || m == 0 || m < 1 || m > 12 {
		return "not set"
	}
	if y > 0 {
		return fmt.Sprintf("%s %d, %d", monthNames[m], d, y)
	}
	return fmt.Sprintf("%s %d", monthNames[m], d)
}

func (a *App) layoutProfileEdit(gtx layout.Context, f frame, st *profileEditState) layout.Dimensions {
	if profileBackBtn.Clicked(gtx) {
		a.closeProfileEdit()
		return layout.Dimensions{}
	}
	if !st.loaded {
		return a.loadingNote(gtx)
	}
	if !profileEdSynced.Load() {
		profileUserEd.SetText(st.username)
		profileBioEd.SetText(st.bio)
		profileBdayD.SetText("")
		profileBdayM.SetText("")
		profileBdayY.SetText("")
		if st.bdayDay > 0 {
			profileBdayD.SetText(strconv.Itoa(st.bdayDay))
			profileBdayM.SetText(strconv.Itoa(st.bdayMonth))
			if st.bdayYear > 0 {
				profileBdayY.SetText(strconv.Itoa(st.bdayYear))
			}
		}
		profileEdSynced.Store(true)
	}
	acc, _ := accountByIDSnapshot(a, st.accountID)

	var children []layout.FlexChild
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					btn := a.ui.IconButton(&profileBackBtn, iconNavigationBack, "Back")
					btn.Color = a.ui.p.TextDim
					return btn.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.H3("Edit profile · " + platformTitle(acc.Platform))
					return lbl.Layout(gtx)
				}),
			)
		})
	}))

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.profileAvatar(gtx, st, acc, unit.Dp(64))
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					if profilePhotoBtn.Clicked(gtx) {
						a.pickProfilePhoto(st.accountID)
					}
					return layout.Inset{Left: unit.Dp(16)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.SurfaceButton(&profilePhotoBtn, "Change photo")
						return btn.Layout(gtx)
					})
				}),
			)
		})
	}))

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Name", st.displayName)
	}))
	if st.phone != "" {
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Phone", st.phone)
		}))
	}

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Username", "5-32 characters: letters, digits, underscore")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.markEditorRow(gtx, &profileUserEd, "Username")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if profileUserBtn.Clicked(gtx) {
			u := strings.ToLower(strings.TrimSpace(profileUserEd.Text()))
			go func() {
				if msg := validateUsername(u); msg != "" {
					a.setToast("Username: " + msg)
					return
				}
				if u == "" || u == st.username {
					return
				}
				if err := a.eng.UpdateAccountUsername(st.accountID, u); err != nil {
					a.setToast("Username: " + err.Error())
					return
				}
				a.setToast("Username updated")
				a.loadProfileEdit(st.accountID)
				go a.refreshAccounts()
			}()
		}
		return a.profileApplyRow(gtx, &profileUserBtn, "Apply username")
	}))

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Bio", "Shown on your profile (70 characters max)")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.markEditorRow(gtx, &profileBioEd, "Bio")
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if profileBioBtn.Clicked(gtx) {
			bio := strings.TrimSpace(profileBioEd.Text())
			go func() {
				if msg := validateBio(bio); msg != "" {
					a.setToast("Bio: " + msg)
					return
				}
				if bio == st.bio {
					return
				}
				if err := a.eng.UpdateBio(st.accountID, bio); err != nil {
					a.setToast("Bio: " + err.Error())
					return
				}
				a.setToast("Bio updated")
				a.loadProfileEdit(st.accountID)
			}()
		}
		return a.profileApplyRow(gtx, &profileBioBtn, "Apply bio")
	}))

	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, "Birthday", "Current: "+birthdayLabel(st.bdayDay, st.bdayMonth, st.bdayYear))
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.markEditorRow(gtx, &profileBdayD, "Day")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.markEditorRow(gtx, &profileBdayM, "Month")
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return a.markEditorRow(gtx, &profileBdayY, "Year")
				}),
			)
		})
	}))
	children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if profileBdayBtn.Clicked(gtx) {
			d, m, y, msg := parseBirthday(profileBdayD.Text(), profileBdayM.Text(), profileBdayY.Text())
			go func() {
				if msg != "" {
					a.setToast("Birthday: " + msg)
					return
				}
				if d == st.bdayDay && m == st.bdayMonth && y == st.bdayYear {
					return
				}
				if err := a.eng.UpdateBirthday(st.accountID, d, m, y); err != nil {
					a.setToast("Birthday: " + err.Error())
					return
				}
				a.setToast("Birthday updated")
				a.loadProfileEdit(st.accountID)
			}()
		}
		return a.profileApplyRow(gtx, &profileBdayBtn, "Apply birthday")
	}))

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) profileApplyRow(gtx layout.Context, btn *widget.Clickable, label string) layout.Dimensions {
	return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(12), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		b := a.ui.TextButton(btn, label)
		b.Color = a.ui.p.Accent
		return b.Layout(gtx)
	})
}

func (a *App) profileAvatar(gtx layout.Context, st *profileEditState, acc engine.AccountInfo, size unit.Dp) layout.Dimensions {
	sz := gtx.Dp(size)
	if st.avatarPath != "" {
		if img := a.avatarImage(st.avatarPath, ""); img != nil {
			return drawImageRRectCover(gtx, img, sz)
		}
	}
	name := st.displayName
	if name == "" {
		name = accountName(acc)
	}
	return a.ui.Avatar(gtx, name, size, dotNone)
}

func (a *App) pickProfilePhoto(accountID string) {
	if a.expl == nil {
		a.setToast("Photo: file picker unavailable on this platform")
		return
	}
	go func() {
		rcs, err := a.expl.ChooseFiles(photoExts...)
		if err != nil {
			if !errors.Is(err, explorer.ErrUserDecline) && !errors.Is(err, explorer.ErrNotAvailable) {
				a.setToast("Photo: " + err.Error())
			}
			return
		}
		paths, temps := resolveUploadPaths(rcs)
		defer func() {
			for _, t := range temps {
				os.Remove(t)
			}
		}()
		if len(paths) == 0 {
			a.setToast("Photo: could not read the selected file")
			return
		}
		if err := a.eng.UploadProfilePhoto(accountID, paths[0]); err != nil {
			a.setToast("Photo: " + err.Error())
			return
		}
		a.setToast("Profile photo updated")
		go a.refreshAccounts()
		a.loadProfileEdit(accountID)
	}()
}
