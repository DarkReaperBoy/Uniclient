package gui

import (
	"fmt"
	"image"
	"strings"
	"time"

	"gioui.org/io/event"
	"gioui.org/io/key"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
)

const (
	twofaStepMain      = 0
	twofaStepNew       = 1
	twofaStepDisable   = 2
	twofaStepEmail     = 3
	twofaStepEmailCode = 4
)

const (
	twofaActSet          = "set_password"
	twofaActChange       = "change_password"
	twofaActDisable      = "disable_password"
	twofaActSetEmail     = "set_email"
	twofaActChangeEmail  = "change_email"
	twofaActConfirmEmail = "confirm_email"
)

var (
	errTwoFACurrentRequired = fmt.Errorf("current password required")
	errTwoFAMismatch        = fmt.Errorf("passwords do not match")
	errTwoFAEmpty           = fmt.Errorf("password must not be empty")
	errTwoFAShort           = fmt.Errorf("password is too short")
)

type twofaDlgState struct {
	accountID string
	step      int
	state     *cores.CloudPasswordState
	loading   bool
	busy      bool
	errMsg    string
	emailSent string
}

var (
	twofaRowBtns       []widget.Clickable
	twofaDlgTag        = new(struct{})
	twofaBackBtn       widget.Clickable
	twofaCancelBtn     widget.Clickable
	twofaSaveBtn       widget.Clickable
	twofaDisableBtn    widget.Clickable
	twofaEmailBtn      widget.Clickable
	twofaConfirmBtn    widget.Clickable
	twofaResendBtn     widget.Clickable
	twofaCancelEmailBt widget.Clickable
	twofaCurEd         widget.Editor
	twofaNewEd         widget.Editor
	twofaNew2Ed        widget.Editor
	twofaHintEd        widget.Editor
	twofaEmailEd       widget.Editor
	twofaCodeEd        widget.Editor
)

func init() {
	twofaCurEd.Mask = '*'
	twofaNewEd.Mask = '*'
	twofaNew2Ed.Mask = '*'
}

func twofaMainActions(st cores.CloudPasswordState) []string {
	if !st.HasPassword {
		return []string{twofaActSet}
	}
	acts := []string{twofaActChange, twofaActDisable}
	switch {
	case st.EmailUnconfirmedPattern != "":
		acts = append(acts, twofaActConfirmEmail)
	case st.HasRecovery:
		acts = append(acts, twofaActChangeEmail)
	default:
		acts = append(acts, twofaActSetEmail)
	}
	return acts
}

func twofaValidateNew(hasCur bool, cur, new1, new2 string) error {
	if hasCur && cur == "" {
		return errTwoFACurrentRequired
	}
	if new1 == "" {
		return errTwoFAEmpty
	}
	if len([]rune(new1)) < 2 {
		return errTwoFAShort
	}
	if new1 != new2 {
		return errTwoFAMismatch
	}
	return nil
}

func twofaLooksLikeEmail(s string) bool {
	if strings.ContainsAny(s, " \t\n") {
		return false
	}
	at := strings.IndexByte(s, '@')
	if at <= 0 || at == len(s)-1 {
		return false
	}
	domain := s[at+1:]
	return strings.Contains(domain, ".") && !strings.ContainsAny(domain, " @")
}

func twofaGoToEmailCode(d *twofaDlgState) bool {
	d.step = twofaStepEmailCode
	return true
}

func twofaStateSummary(st cores.CloudPasswordState) string {
	if !st.HasPassword {
		return "Off"
	}
	switch {
	case st.Hint != "":
		return "On · hint: " + st.Hint
	case st.HasRecovery:
		return "On · recovery email set"
	}
	return "On"
}

func twofaRowValue(st cores.CloudPasswordState) string {
	if st.HasPassword {
		return "On"
	}
	return "Off"
}

func twofaSupportedFor(a *App, accountID string) bool {
	for _, c := range a.eng.AccountCapabilities(accountID) {
		if c == cores.CapCloudPassword {
			return true
		}
	}
	return false
}

func (a *App) openTwoFADialog(accountID string) {
	d := &twofaDlgState{accountID: accountID, loading: true}
	a.mu.Lock()
	a.twofaDlg = d
	a.mu.Unlock()
	a.invalidate()
	go func() {
		st, err := a.eng.GetCloudPasswordState(accountID)
		a.updateTwoFADlg(func(cur *twofaDlgState) bool {
			if cur.accountID != accountID {
				return false
			}
			cur.loading = false
			if err != nil {
				cur.errMsg = err.Error()
			} else {
				cur.state = &st
			}
			return true
		})
		a.invalidate()
	}()
}

func (a *App) closeTwoFADialog() {
	a.mu.Lock()
	a.twofaDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

func (a *App) updateTwoFADlg(fn func(d *twofaDlgState) bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.twofaDlg == nil {
		return
	}
	next := *a.twofaDlg
	if !fn(&next) {
		return
	}
	a.twofaDlg = &next
}

func (a *App) twofaFinish(d *twofaDlgState, what string, call func() error) {
	accountID := d.accountID
	a.updateTwoFADlg(func(cur *twofaDlgState) bool {
		if cur.accountID != accountID {
			return false
		}
		cur.busy = true
		return true
	})
	go func() {
		err := call()
		a.updateTwoFADlg(func(cur *twofaDlgState) bool {
			if cur.accountID != accountID {
				return false
			}
			cur.busy = false
			if err != nil {
				cur.errMsg = err.Error()
			} else {
				cur.errMsg = ""
				cur.step = twofaStepMain
			}
			return true
		})
		if err != nil {
			a.setToast(what + ": " + err.Error())
		} else {
			a.setToast(what)
		}
		if st, err := a.eng.GetCloudPasswordState(accountID); err == nil {
			a.updateTwoFADlg(func(cur *twofaDlgState) bool {
				if cur.accountID != accountID {
					return false
				}
				cur.state = &st
				cur.loading = false
				return true
			})
			a.refreshTwoFARowState(accountID, st)
		}
		a.invalidate()
	}()
}

func (a *App) refreshTwoFARowState(accountID string, st cores.CloudPasswordState) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.twofaStates == nil {
		return
	}
	fresh := make(map[string]cores.CloudPasswordState, len(a.twofaStates)+1)
	for k, v := range a.twofaStates {
		fresh[k] = v
	}
	fresh[accountID] = st
	a.twofaStates = fresh
}

func (a *App) layoutTwoFADialog(gtx layout.Context, f frame) layout.Dimensions {
	d := f.twofaDlg

	{
		stack := clip.Rect{Max: image.Pt(gtx.Constraints.Max.X, gtx.Constraints.Max.Y)}.Push(gtx.Ops)
		event.Op(gtx.Ops, twofaDlgTag)
		stack.Pop()
	}
	for {
		ev, ok := gtx.Source.Event(key.Filter{})
		if !ok {
			break
		}
		if ke, is := ev.(key.Event); is && ke.State == key.Press {
			if ke.Name == key.NameEscape {
				a.closeTwoFADialog()
			}
		}
	}
	if twofaCancelBtn.Clicked(gtx) {
		a.closeTwoFADialog()
	}
	if twofaBackBtn.Clicked(gtx) {
		acct := d.accountID
		a.updateTwoFADlg(func(cur *twofaDlgState) bool {
			if cur.accountID != acct {
				return false
			}
			cur.step = twofaStepMain
			cur.errMsg = ""
			return true
		})
		a.invalidate()
	}

	title := "Two-Step Verification"
	var body []layout.FlexChild

	switch d.step {
	case twofaStepMain:
		body = a.twofaMainBody(gtx, f, d)
	case twofaStepNew:
		body = a.twofaNewBody(gtx, f, d)
	case twofaStepDisable:
		body = a.twofaDisableBody(gtx, f, d)
	case twofaStepEmail:
		body = a.twofaEmailBody(gtx, f, d)
	case twofaStepEmailCode:
		body = a.twofaEmailCodeBody(gtx, f, d)
	}

	children := append([]layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(6), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if d.step == twofaStepMain {
							return layout.Dimensions{}
						}
						_ = twofaBackBtn.Clicked(gtx)
						return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.IconButton(&twofaBackBtn, iconNavigationBack, "Back").Layout(gtx)
						})
					}),
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(16), title)
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := a.ui.SurfaceButton(&twofaCancelBtn, "Close")
						return btn.Layout(gtx)
					}),
				)
			})
		}),
	}, body...)

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
}

func (a *App) twofaMainBody(gtx layout.Context, f frame, d *twofaDlgState) []layout.FlexChild {
	var body []layout.FlexChild
	if d.loading {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.loadingNote(gtx)
		}))
		return body
	}
	st := d.state
	if st == nil {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaErrNote(gtx, d)
		}))
		return body
	}
	body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.settingRow(gtx, twofaStateSummary(*st), "")
	}))
	if st.EmailUnconfirmedPattern != "" {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Confirm email: "+st.EmailUnconfirmedPattern, "")
		}))
	}
	if st.PendingResetDate > 0 {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Reset pending · "+time.Unix(int64(st.PendingResetDate), 0).Format("Jan 2, 15:04"), "")
		}))
	}
	body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return a.twofaErrNote(gtx, d)
	}))

	acts := twofaMainActions(*st)
	growClickables(&twofaRowBtns, len(acts))
	labels := map[string]string{
		twofaActSet:          "Set Password",
		twofaActChange:       "Change Password",
		twofaActDisable:      "Turn Password Off…",
		twofaActSetEmail:     "Set Recovery Email",
		twofaActChangeEmail:  "Change Recovery Email",
		twofaActConfirmEmail: "Enter Email Code",
	}
	for i, act := range acts {
		act := act
		btn := &twofaRowBtns[i]
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if btn.Clicked(gtx) {
				twofaClearEditors()
				acct := d.accountID
				a.updateTwoFADlg(func(cur *twofaDlgState) bool {
					if cur.accountID != acct {
						return false
					}
					switch act {
					case twofaActSet, twofaActChange:
						cur.step = twofaStepNew
					case twofaActDisable:
						cur.step = twofaStepDisable
					case twofaActSetEmail, twofaActChangeEmail:
						cur.step = twofaStepEmail
					case twofaActConfirmEmail:
						cur.step = twofaStepEmailCode
					}
					cur.errMsg = ""
					return true
				})
				a.invalidate()
			}
			bl := material.ButtonLayout(a.ui.Theme, btn)
			bl.Background = a.ui.p.AccentDim
			bl.CornerRadius = 10
			return layout.Inset{Top: unit.Dp(3), Bottom: unit.Dp(3), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return bl.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(14), labels[act])
						return lbl.Layout(gtx)
					})
				})
			})
		}))
	}
	return body
}

func (a *App) twofaNewBody(gtx layout.Context, f frame, d *twofaDlgState) []layout.FlexChild {
	hasCur := d.state != nil && d.state.HasPassword
	var body []layout.FlexChild
	if hasCur {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaField(gtx, &twofaCurEd, "Current password", false)
		}))
	}
	body = append(body,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaField(gtx, &twofaNewEd, "New password", false)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaField(gtx, &twofaNew2Ed, "Repeat new password", false)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaField(gtx, &twofaHintEd, "Hint (optional)", true)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaErrNote(gtx, d)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if twofaSaveBtn.Clicked(gtx) && !d.busy {
				if err := twofaValidateNew(hasCur, twofaCurEd.Text(), twofaNewEd.Text(), twofaNew2Ed.Text()); err != nil {
					acct := d.accountID
					a.updateTwoFADlg(func(cur *twofaDlgState) bool {
						if cur.accountID != acct {
							return false
						}
						cur.errMsg = err.Error()
						return true
					})
					a.invalidate()
				} else {
					cur, new1, hint := twofaCurEd.Text(), twofaNewEd.Text(), twofaHintEd.Text()
					twofaClearEditors()
					a.twofaFinish(d, "Password updated", func() error {
						return a.eng.SetCloudPassword(d.accountID, cur, new1, hint, "")
					})
				}
			}
			btn := a.ui.PrimaryButton(&twofaSaveBtn, "Save")
			return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, btn.Layout)
		}),
	)
	return body
}

func (a *App) twofaDisableBody(gtx layout.Context, f frame, d *twofaDlgState) []layout.FlexChild {
	var body []layout.FlexChild
	body = append(body,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaField(gtx, &twofaCurEd, "Current password", false)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Disabling removes the second login step on every device.", "")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaErrNote(gtx, d)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if twofaDisableBtn.Clicked(gtx) && !d.busy {
				cur := twofaCurEd.Text()
				if cur == "" {
					acct := d.accountID
					a.updateTwoFADlg(func(c *twofaDlgState) bool {
						if c.accountID != acct {
							return false
						}
						c.errMsg = errTwoFACurrentRequired.Error()
						return true
					})
					a.invalidate()
				} else {
					twofaClearEditors()
					a.twofaFinish(d, "Password disabled", func() error {
						return a.eng.RemoveCloudPassword(d.accountID, cur)
					})
				}
			}
			btn := a.ui.PrimaryButton(&twofaDisableBtn, "Turn Off")
			return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, btn.Layout)
		}),
	)
	return body
}

func (a *App) twofaEmailBody(gtx layout.Context, f frame, d *twofaDlgState) []layout.FlexChild {
	hasCur := d.state != nil && d.state.HasPassword
	var body []layout.FlexChild
	if hasCur {
		body = append(body, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaField(gtx, &twofaCurEd, "Current password", false)
		}))
	}
	body = append(body,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaField(gtx, &twofaEmailEd, "Recovery email", true)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaErrNote(gtx, d)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if twofaEmailBtn.Clicked(gtx) && !d.busy {
				cur, email := twofaCurEd.Text(), twofaEmailEd.Text()
				if email == "" || !twofaLooksLikeEmail(email) {
					acct := d.accountID
					a.updateTwoFADlg(func(c *twofaDlgState) bool {
						if c.accountID != acct {
							return false
						}
						c.errMsg = "Enter a valid email address"
						return true
					})
					a.invalidate()
				} else {
					twofaClearEditors()
					acct := d.accountID
					a.updateTwoFADlg(func(c *twofaDlgState) bool {
						if c.accountID != acct {
							return false
						}
						c.emailSent = email
						return true
					})
					a.twofaFinishSendEmail(d, cur, email)
				}
			}
			btn := a.ui.PrimaryButton(&twofaEmailBtn, "Continue")
			return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, btn.Layout)
		}),
	)
	return body
}

func (a *App) twofaFinishSendEmail(d *twofaDlgState, cur, email string) {
	accountID := d.accountID
	a.updateTwoFADlg(func(c *twofaDlgState) bool {
		if c.accountID != accountID {
			return false
		}
		c.busy = true
		return true
	})
	go func() {
		err := a.eng.SetCloudPasswordEmail(accountID, cur, email)
		a.updateTwoFADlg(func(c *twofaDlgState) bool {
			if c.accountID != accountID {
				return false
			}
			c.busy = false
			if err != nil {
				c.errMsg = err.Error()
			} else {
				c.errMsg = ""
				twofaGoToEmailCode(c)
			}
			return true
		})
		if err != nil {
			a.setToast("Recovery email: " + err.Error())
		} else {
			a.setToast("Code sent to " + email)
		}
		a.invalidate()
	}()
}

func (a *App) twofaEmailCodeBody(gtx layout.Context, f frame, d *twofaDlgState) []layout.FlexChild {
	pattern := ""
	if d.state != nil && d.state.EmailUnconfirmedPattern != "" {
		pattern = d.state.EmailUnconfirmedPattern
	} else if d.emailSent != "" {
		pattern = d.emailSent
	}
	var body []layout.FlexChild
	body = append(body,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.settingRow(gtx, "Code sent to "+pattern, "")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaField(gtx, &twofaCodeEd, "Confirmation code", true)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return a.twofaErrNote(gtx, d)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if twofaConfirmBtn.Clicked(gtx) && !d.busy {
				code := twofaCodeEd.Text()
				if code == "" {
					acct := d.accountID
					a.updateTwoFADlg(func(c *twofaDlgState) bool {
						if c.accountID != acct {
							return false
						}
						c.errMsg = "Enter the code from the email"
						return true
					})
					a.invalidate()
				} else {
					twofaClearEditors()
					a.twofaFinish(d, "Recovery email confirmed", func() error {
						return a.eng.ConfirmPasswordEmail(d.accountID, code)
					})
				}
			}
			if twofaResendBtn.Clicked(gtx) && !d.busy {
				go func() {
					if err := a.eng.ResendPasswordEmail(d.accountID); err != nil {
						a.setToast("Resend: " + err.Error())
					} else {
						a.setToast("Code re-sent")
					}
				}()
			}
			if twofaCancelEmailBt.Clicked(gtx) && !d.busy {
				acct := d.accountID
				go func() {
					if err := a.eng.CancelPasswordEmail(acct); err != nil {
						a.setToast("Cancel: " + err.Error())
					} else {
						a.setToast("Email change cancelled")
					}
					a.updateTwoFADlg(func(cur *twofaDlgState) bool {
						if cur.accountID != acct {
							return false
						}
						cur.step = twofaStepMain
						return true
					})
					a.invalidate()
				}()
			}
			return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
					layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
						return a.ui.PrimaryButton(&twofaConfirmBtn, "Confirm").Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.SurfaceButton(&twofaResendBtn, "Resend").Layout(gtx)
						})
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return a.ui.SurfaceButton(&twofaCancelEmailBt, "Cancel").Layout(gtx)
						})
					}),
				)
			})
		}),
	)
	return body
}

func (a *App) twofaField(gtx layout.Context, ed *widget.Editor, label string, plain bool) layout.Dimensions {
	if plain {
		ed.Mask = 0
	} else if ed.Mask == 0 {
		ed.Mask = '*'
	}
	return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := a.ui.Dim(unit.Sp(11), label)
				return lbl.Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(2)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					for {
						ev, ok := ed.Update(gtx)
						if !ok {
							break
						}
						if _, is := ev.(widget.ChangeEvent); is {
							a.invalidate()
						}
					}
					e := a.ui.Editor(ed, label)
					return roundedFill(gtx, a.ui.p.SurfaceHi, 8, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(6)).Layout(gtx, e.Layout)
					})
				})
			}),
		)
	})
}

func (a *App) twofaErrNote(gtx layout.Context, d *twofaDlgState) layout.Dimensions {
	if d.errMsg == "" {
		return layout.Dimensions{}
	}
	lbl := a.ui.Dim(unit.Sp(12), d.errMsg)
	lbl.Color = a.ui.p.Error
	return layout.Inset{Top: unit.Dp(4), Left: unit.Dp(14), Right: unit.Dp(14)}.Layout(gtx, lbl.Layout)
}

func twofaClearEditors() {
	twofaCurEd.SetText("")
	twofaNewEd.SetText("")
	twofaNew2Ed.SetText("")
	twofaHintEd.SetText("")
	twofaEmailEd.SetText("")
	twofaCodeEd.SetText("")
}
