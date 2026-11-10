package engine

import (
	"context"
	"fmt"
	"strings"
	"sync"

	"uniclient/cores"
)

const (
	AuthStateChoose = "choose"
	AuthStateInput  = "input"
	AuthStateOTP    = "otp"
	AuthState2FA    = "2fa"
	AuthStateQR     = "qr"
	AuthStateSignUp = "signup"
	AuthStateEmail  = "email"
	AuthStateReady  = "ready"
	AuthStateError  = "error"
)

type AuthState struct {
	AccountID string `json:"account_id"`
	Platform  string `json:"platform"`
	State     string `json:"state"`

	Options           []AuthOption `json:"options,omitempty"`
	FieldType         string       `json:"field_type,omitempty"`
	Label             string       `json:"label,omitempty"`
	Hint              string       `json:"hint,omitempty"`
	Error             string       `json:"error,omitempty"`
	CodeLength        int          `json:"code_length,omitempty"`
	SentTo            string       `json:"sent_to,omitempty"`
	TimeoutSecs       int          `json:"timeout_secs,omitempty"`
	CanResend         bool         `json:"can_resend,omitempty"`
	HasRecovery       bool         `json:"has_recovery,omitempty"`
	QRData            []byte       `json:"qr_data,omitempty"`
	QRExpiresIn       int          `json:"qr_expires_in,omitempty"`
	DisplayName       string       `json:"display_name,omitempty"`
	AvatarB64         string       `json:"avatar_b64,omitempty"`
	Message           string       `json:"message,omitempty"`
	Recoverable       bool         `json:"recoverable,omitempty"`
	CodeByTelegram    bool         `json:"code_by_telegram,omitempty"`
	CodeByFragmentUrl string       `json:"code_by_fragment_url,omitempty"`
	Email             string       `json:"email,omitempty"`
	EmailPatternSetup string       `json:"email_pattern_setup,omitempty"`
	EmailPatternLogin string       `json:"email_pattern_login,omitempty"`
}

type AuthOption struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

type AuthFlow struct {
	mu        sync.Mutex
	state     *AuthState
	collected map[string]string
	core      cores.Core
	history   []*AuthState
}

func (e *Engine) StartAuth(accountID string) (*AuthState, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account %q not found", accountID)
	}

	factory := getCoreFactory()
	if factory == nil {
		return nil, fmt.Errorf("no core factory registered")
	}
	core, err := factory(acc.Platform, accountID)
	if err != nil {
		return nil, fmt.Errorf("create core: %w", err)
	}
	e.applyProxyToCore(core)

	initial := initialAuthState(acc.Platform, accountID)

	flow := &AuthFlow{
		state:     initial,
		collected: make(map[string]string),
		core:      core,
	}

	e.authFlowsMu.Lock()
	e.authFlows[accountID] = flow
	e.authFlowsMu.Unlock()

	e.emitEvent(EventAuthState, accountID, initial)
	return initial, nil
}

func (e *Engine) SubmitAuthInput(accountID, input string) (*AuthState, error) {
	e.authFlowsMu.Lock()
	flow, ok := e.authFlows[accountID]
	e.authFlowsMu.Unlock()
	if !ok {
		return nil, fmt.Errorf("no auth flow for %q", accountID)
	}

	flow.mu.Lock()
	defer flow.mu.Unlock()

	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account %q not found", accountID)
	}

	prevState := flow.state.State
	prevCollected := len(flow.collected)
	next, err := advanceAuth(acc.Platform, flow, input)
	if err != nil {
		errState := &AuthState{
			AccountID:   accountID,
			Platform:    acc.Platform,
			State:       AuthStateError,
			Message:     err.Error(),
			Recoverable: true,
		}
		flow.state = errState
		e.emitEvent(EventAuthState, accountID, errState)
		return errState, nil
	}

	forward := next.State != prevState || len(flow.collected) > prevCollected
	if forward && next.State != AuthStateReady && next.State != AuthStateError {
		flow.history = append(flow.history, flow.state)
	}
	flow.state = next

	if next.State == AuthStateQR {
		if tc, ok := flow.core.(telegramLoginFlow); ok {
			tc.SetQRRefreshCallback(func() { go e.onQRTokenUpdate(accountID) })
		}
	}

	if next.State == AuthStateReady {
		e.finalizeAuth(accountID, acc, flow)
	}

	e.emitEvent(EventAuthState, accountID, next)
	return next, nil
}

type telegramLoginFlow interface {
	StartQRAuth() (string, int, error)
	SetQRRefreshCallback(cb func())
	RefreshQRToken() (string, int, bool, error)
	AuthCodeInfo() (bool, string, string, int, int)
	VerifyEmailDuringAuth(code string) (int, bool, int, error)
	SendVerifyEmailCodeDuringAuth(email string) (string, int, error)
	SubmitSignUp(firstName, lastName string) error
	SubmitPhoneCodeAfterEmail(code string) error
	SubmitOTP(code string) error
	Submit2FAAfterEmail(password string) error
	Submit2FA(password string) error
	ResetPasswordDuringAuth() (map[string]interface{}, error)
	RequestRecoveryDuringAuth() (string, error)
	ResendOTPCode() error
	NoTelegramCode() (int, int, error)
	Get2FAStateDuringAuth() (bool, string, error)
}

type baleSubmitter interface {
	SubmitOTP(code string) error
	Submit2FA(password string) error
}

func (e *Engine) onQRTokenUpdate(accountID string) {
	e.authFlowsMu.Lock()
	flow, ok := e.authFlows[accountID]
	e.authFlowsMu.Unlock()
	if !ok {
		return
	}

	flow.mu.Lock()
	defer flow.mu.Unlock()

	if flow.state == nil || flow.state.State != AuthStateQR {
		return
	}
	tc, ok := flow.core.(telegramLoginFlow)
	if !ok {
		return
	}
	acc, ok := e.getAccount(accountID)
	if !ok {
		return
	}

	url, expires, accepted, err := tc.RefreshQRToken()
	if err != nil {
		return
	}

	base := &AuthState{AccountID: accountID, Platform: acc.Platform}
	if accepted {
		telegramReadyState(flow, base)
		flow.state = base
		e.finalizeAuth(accountID, acc, flow)
		e.emitEvent(EventAuthState, accountID, base)
		return
	}
	base.State = AuthStateQR
	base.QRData = []byte(url)
	base.QRExpiresIn = expires
	flow.state = base
	e.emitEvent(EventAuthState, accountID, base)
}

func (e *Engine) CancelAuth(accountID string) {
	e.authFlowsMu.Lock()
	flow, ok := e.authFlows[accountID]
	if ok {
		if flow.core != nil {
			flow.core.Close()
		}
		delete(e.authFlows, accountID)
	}
	e.authFlowsMu.Unlock()
}

func (e *Engine) GoBackAuth(accountID string) (*AuthState, bool) {
	e.authFlowsMu.Lock()
	flow, ok := e.authFlows[accountID]
	e.authFlowsMu.Unlock()
	if !ok {
		return nil, false
	}

	flow.mu.Lock()
	defer flow.mu.Unlock()

	if len(flow.history) == 0 {
		return nil, false
	}

	prev := flow.history[len(flow.history)-1]
	flow.history = flow.history[:len(flow.history)-1]
	flow.state = prev

	e.emitEvent(EventAuthState, accountID, prev)
	return prev, true
}

func (e *Engine) SwitchAuthMethod(accountID, method string) (*AuthState, error) {
	e.authFlowsMu.Lock()
	flow, ok := e.authFlows[accountID]
	e.authFlowsMu.Unlock()
	if !ok {
		return nil, fmt.Errorf("no auth flow for %q", accountID)
	}

	flow.mu.Lock()
	defer flow.mu.Unlock()

	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account %q not found", accountID)
	}

	chooseState := initialAuthState(acc.Platform, accountID)
	flow.state = chooseState
	flow.collected = make(map[string]string)
	flow.history = nil

	next, err := advanceAuth(acc.Platform, flow, method)
	if err != nil {
		errState := &AuthState{
			AccountID:   accountID,
			Platform:    acc.Platform,
			State:       AuthStateError,
			Message:     err.Error(),
			Recoverable: true,
		}
		flow.state = errState
		e.emitEvent(EventAuthState, accountID, errState)
		return errState, nil
	}

	if next.State != AuthStateReady && next.State != AuthStateError {
		flow.history = append(flow.history, chooseState)
	}
	flow.state = next

	if next.State == AuthStateQR {
		if tc, ok := flow.core.(telegramLoginFlow); ok {
			tc.SetQRRefreshCallback(func() { go e.onQRTokenUpdate(accountID) })
		}
	}

	if next.State == AuthStateReady {
		e.finalizeAuth(accountID, acc, flow)
	}

	e.emitEvent(EventAuthState, accountID, next)
	return next, nil
}

func (e *Engine) finalizeAuth(accountID string, acc *Account, flow *AuthFlow) {
	cfg := BuildAuthConfig(acc.Platform, flow.collected)

	e.SaveCredentials(accountID, cfg)

	e.accountsMu.Lock()
	acc.Core = flow.core
	acc.ConnState = ConnConnected
	if flow.state.DisplayName != "" {
		acc.DisplayName = flow.state.DisplayName
	}
	if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
		acc.IsVerified = profile.IsVerified
		acc.IsPremium = profile.IsPremium
		acc.Phone = profile.Phone
		acc.Username = profile.Username
	}
	e.accountsMu.Unlock()

	e.UpdateAccountDisplay(accountID, acc.DisplayName, "")

	flow.core.OnUpdate(func(u cores.Update) {
		e.HandleUpdate(accountID, u)
	})

	e.authFlowsMu.Lock()
	delete(e.authFlows, accountID)
	e.authFlowsMu.Unlock()

	e.emitConnState(accountID, ConnConnected, "")
	e.emitAccountList()

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.syncAccount(context.Background(), accountID)
	}()
}

func initialAuthState(platform, accountID string) *AuthState {
	base := &AuthState{AccountID: accountID, Platform: platform}

	switch platform {
	case "telegram":
		base.State = AuthStateChoose
		base.Options = []AuthOption{
			{ID: "phone", Label: "Phone Number"},
			{ID: "bot_token", Label: "Bot Token"},
			{ID: "qr_code", Label: "QR Code"},
		}
	case "bale":
		base.State = AuthStateChoose
		base.Options = []AuthOption{
			{ID: "phone", Label: "Phone Number"},
			{ID: "bot_token", Label: "Bot Token"},
		}
	case "matrix":
		base.State = AuthStateInput
		base.FieldType = "url"
		base.Label = "Homeserver URL"
		base.Hint = "https://matrix.org"
	case "irc":
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Server"
		base.Hint = "irc.libera.chat:6697"
	case "xmpp":
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "JID (user@server)"
		base.Hint = "user@example.com"
	case "github":
		base.State = AuthStateInput
		base.FieldType = "token"
		base.Label = "Personal Access Token"
		base.Hint = "ghp_..."
	case "deltachat":
		base.State = AuthStateInput
		base.FieldType = "email"
		base.Label = "Email Address"
		base.Hint = "you@example.com"
	case "teamspeak":
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Server Address"
		base.Hint = "ts.example.com:9987"
	case "mumble":
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Server Address"
		base.Hint = "mumble.example.com:64738"
	default:
		base.State = AuthStateError
		base.Message = "Unknown platform: " + platform
	}
	return base
}

func advanceAuth(platform string, flow *AuthFlow, input string) (*AuthState, error) {
	s := flow.state
	base := &AuthState{AccountID: s.AccountID, Platform: platform}

	switch platform {
	case "telegram":
		return advanceTelegram(flow, input, base)
	case "bale":
		return advanceBale(flow, input, base)
	case "matrix":
		return advanceMatrix(flow, input, base)
	case "irc":
		return advanceIRC(flow, input, base)
	case "xmpp":
		return AdvanceXMPP(flow, input, base)
	case "github":
		return advanceGitHub(flow, input, base)
	case "deltachat":
		return advanceDeltaChat(flow, input, base)
	case "teamspeak":
		return advanceTeamSpeak(flow, input, base)
	case "mumble":
		return advanceMumble(flow, input, base)
	default:
		return nil, fmt.Errorf("unknown platform: %s", platform)
	}
}

func advanceTelegram(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	switch flow.state.State {
	case AuthStateChoose:
		flow.collected["method"] = input
		switch input {
		case "phone":
			base.State = AuthStateInput
			base.FieldType = "phone"
			base.Label = "Phone Number"
			base.Hint = "+1234567890"
			return base, nil
		case "bot_token":
			base.State = AuthStateInput
			base.FieldType = "token"
			base.Label = "Bot Token"
			base.Hint = "123456:ABC-DEF..."
			return base, nil
		case "qr_code":
			tc, ok := flow.core.(telegramLoginFlow)
			if !ok {
				base.State = AuthStateError
				base.Message = "QR login only supported for Telegram"
				return base, nil
			}
			url, expires, err := tc.StartQRAuth()
			if err != nil {
				base.State = AuthStateError
				base.Message = fmt.Sprintf("QR auth failed: %v", err)
				return base, nil
			}
			if url == "" {
				base.State = AuthStateReady
				if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
					base.DisplayName = profile.DisplayName
					if base.DisplayName == "" {
						base.DisplayName = profile.Username
					}
					base.AvatarB64 = profile.AvatarB64
				}
				return base, nil
			}
			base.State = AuthStateQR
			base.QRData = []byte(url)
			base.QRExpiresIn = expires
			return base, nil
		}
	case AuthStateQR:
		tc, ok := flow.core.(telegramLoginFlow)
		if !ok {
			return nil, fmt.Errorf("expected TelegramCore for QR refresh")
		}
		url, expires, accepted, err := tc.RefreshQRToken()
		if err != nil {
			base.State = AuthStateError
			base.Message = fmt.Sprintf("QR refresh failed: %v", err)
			return base, nil
		}
		if accepted {
			base.State = AuthStateReady
			if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
				base.DisplayName = profile.DisplayName
				if base.DisplayName == "" {
					base.DisplayName = profile.Username
				}
				base.AvatarB64 = profile.AvatarB64
			}
			return base, nil
		}
		base.State = AuthStateQR
		base.QRData = []byte(url)
		base.QRExpiresIn = expires
		return base, nil
	case AuthStateInput:
		if flow.collected["method"] == "bot_token" {
			flow.collected["bot_token"] = input
			return tryAuth(flow, base)
		}
		flow.collected["phone"] = input
		err := flow.core.Authenticate(cores.AuthConfig{
			Mode:  cores.AuthModeUser,
			Phone: input,
		})
		if err == nil {
			base.State = AuthStateReady
			if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
				base.DisplayName = profile.DisplayName
				if base.DisplayName == "" {
					base.DisplayName = profile.Username
				}
				base.AvatarB64 = profile.AvatarB64
			}
			return base, nil
		}
		tc, ok := flow.core.(telegramLoginFlow)
		if !ok {
			return nil, fmt.Errorf("expected TelegramCore for phone auth")
		}
		if err.Error() == "email_setup_required" {
			base.State = AuthStateEmail
			base.FieldType = "email"
			base.Label = "Add Email"
			base.Hint = "Enter an email address to secure your account"
			return base, nil
		}
		if err.Error() != "otp_required" {
			return nil, err
		}
		return telegramOTPState(tc, base), nil
	case AuthStateOTP:
		tc, ok := flow.core.(telegramLoginFlow)
		if !ok {
			return nil, fmt.Errorf("expected TelegramCore for OTP")
		}
		if input == "__no_telegram_code" {
			length, timeout, err := tc.NoTelegramCode()
			if err != nil {
				return nil, fmt.Errorf("no-telegram-code resend: %w", err)
			}
			base.State = AuthStateOTP
			base.CodeLength = length
			base.SentTo = "SMS"
			base.TimeoutSecs = timeout
			base.CodeByTelegram = false
			base.CanResend = true
			return base, nil
		}
		if input == "__resend_code" {
			if err := tc.ResendOTPCode(); err != nil {
				return nil, fmt.Errorf("resend code: %w", err)
			}
			byTg, fragURL, emailPattern, timeout, length := tc.AuthCodeInfo()
			if length <= 0 {
				length = 5
			}
			base.State = AuthStateOTP
			base.CodeLength = length
			base.SentTo = "Telegram"
			base.TimeoutSecs = timeout
			base.CodeByTelegram = byTg
			base.CodeByFragmentUrl = fragURL
			base.EmailPatternLogin = emailPattern
			base.CanResend = true
			return base, nil
		}
		if flow.collected["email_mode"] == "verify" {
			phoneLen, byTg, timeout, err := tc.VerifyEmailDuringAuth(input)
			if err != nil {
				return nil, err
			}
			flow.collected["email_mode"] = "phone"
			base.State = AuthStateOTP
			if phoneLen <= 0 {
				phoneLen = 5
			}
			base.CodeLength = phoneLen
			base.SentTo = "Telegram"
			base.TimeoutSecs = timeout
			base.CodeByTelegram = byTg
			return base, nil
		}
		if flow.collected["email_mode"] == "phone" {
			err := tc.SubmitPhoneCodeAfterEmail(input)
			if err == nil {
				return telegramReadyState(flow, base), nil
			}
			if err.Error() == "2fa_required" {
				base.State = AuthState2FA
				base.Label = "Two-Factor Password"
				applyTelegram2FAState(tc, base)
				return base, nil
			}
			if err.Error() == "signup_required" {
				base.State = AuthStateSignUp
				base.Label = "Enter your name and add a profile photo"
				return base, nil
			}
			return nil, err
		}
		flow.collected["otp"] = input
		if flow.collected["method"] != "bot_token" {
			err := tc.SubmitOTP(input)
			if err == nil {
				return telegramReadyState(flow, base), nil
			}
			if err.Error() == "2fa_required" {
				base.State = AuthState2FA
				base.Label = "Two-Factor Password"
				applyTelegram2FAState(tc, base)
				return base, nil
			}
			if err.Error() == "signup_required" {
				base.State = AuthStateSignUp
				base.Label = "Enter your name and add a profile photo"
				return base, nil
			}
			return nil, err
		}
		return tryAuth(flow, base)
	case AuthState2FA:
		if input == "__request_recovery" {
			tc, ok := flow.core.(telegramLoginFlow)
			if !ok {
				return nil, fmt.Errorf("expected TelegramCore for recovery request")
			}
			emailPattern, err := tc.RequestRecoveryDuringAuth()
			if err != nil {
				return nil, fmt.Errorf("recovery request: %w", err)
			}
			base.State = AuthState2FA
			base.Label = "Two-Factor Password"
			base.HasRecovery = true
			base.SentTo = emailPattern
			return base, nil
		}
		if input == "__reset_account" {
			tc, ok := flow.core.(telegramLoginFlow)
			if !ok {
				return nil, fmt.Errorf("expected TelegramCore for account reset")
			}
			result, err := tc.ResetPasswordDuringAuth()
			if err != nil {
				return nil, fmt.Errorf("reset account: %w", err)
			}
			base.State = AuthState2FA
			base.Label = "Two-Factor Password"
			if status, ok := result["status"].(string); ok && status == "wait" {
				base.Message = "password_reset_requested"
			} else if status == "ok" {
				base.Message = "password_reset_done"
			} else {
				base.Message = "password_reset_failed"
			}
			return base, nil
		}
		flow.collected["2fa"] = input
		if flow.collected["method"] != "bot_token" {
			tc, ok := flow.core.(telegramLoginFlow)
			if !ok {
				return nil, fmt.Errorf("expected TelegramCore for 2FA submit")
			}
			var err error
			if flow.collected["email_mode"] == "phone" {
				err = tc.Submit2FAAfterEmail(input)
			} else {
				err = tc.Submit2FA(input)
			}
			if err == nil {
				return telegramReadyState(flow, base), nil
			}
			return nil, err
		}
		return tryAuth(flow, base)
	case AuthStateEmail:
		tc, ok := flow.core.(telegramLoginFlow)
		if !ok {
			return nil, fmt.Errorf("expected TelegramCore for email setup")
		}
		email := strings.TrimSpace(input)
		if email == "" {
			return nil, fmt.Errorf("EMAIL_INVALID")
		}
		pattern, length, err := tc.SendVerifyEmailCodeDuringAuth(email)
		if err != nil {
			return nil, err
		}
		flow.collected["email"] = email
		flow.collected["email_mode"] = "verify"
		if length <= 0 {
			length = 6
		}
		base.State = AuthStateOTP
		base.CodeLength = length
		base.SentTo = pattern
		base.Email = email
		base.EmailPatternSetup = pattern
		return base, nil
	case AuthStateSignUp:
		tc, ok := flow.core.(telegramLoginFlow)
		if !ok {
			return nil, fmt.Errorf("expected TelegramCore for signup")
		}
		parts := splitSignUpInput(input)
		err := tc.SubmitSignUp(parts[0], parts[1])
		if err == nil {
			base.State = AuthStateReady
			base.DisplayName = parts[0]
			if parts[1] != "" {
				base.DisplayName += " " + parts[1]
			}
			if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
				base.DisplayName = profile.DisplayName
				if base.DisplayName == "" {
					base.DisplayName = profile.Username
				}
				base.AvatarB64 = profile.AvatarB64
			}
			return base, nil
		}
		return nil, err
	}
	return nil, fmt.Errorf("unexpected state %s for telegram", flow.state.State)
}

func telegramReadyState(flow *AuthFlow, base *AuthState) *AuthState {
	base.State = AuthStateReady
	if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
		base.DisplayName = profile.DisplayName
		if base.DisplayName == "" {
			base.DisplayName = profile.Username
		}
		base.AvatarB64 = profile.AvatarB64
	}
	return base
}

func applyTelegram2FAState(tc telegramLoginFlow, base *AuthState) {
	hasRecovery, hint, err := tc.Get2FAStateDuringAuth()
	if err != nil {
		base.HasRecovery = false
		return
	}
	base.HasRecovery = hasRecovery
	if hint != "" && base.Hint == "" {
		base.Hint = hint
	}
}

func telegramOTPState(tc telegramLoginFlow, base *AuthState) *AuthState {
	byTg, fragURL, emailPattern, timeout, length := tc.AuthCodeInfo()
	if length <= 0 {
		length = 5
	}
	if timeout <= 0 {
		timeout = 60
	}
	base.State = AuthStateOTP
	base.CodeLength = length
	base.TimeoutSecs = timeout
	base.CodeByTelegram = byTg
	base.CodeByFragmentUrl = fragURL
	base.EmailPatternLogin = emailPattern
	switch {
	case emailPattern != "":
		base.SentTo = "Email"
	case fragURL != "":
		base.SentTo = "Fragment"
	case byTg:
		base.SentTo = "Telegram app"
	default:
		base.SentTo = "SMS"
	}
	return base
}

func splitSignUpInput(input string) [2]string {
	idx := 0
	for i, c := range input {
		if c == '\n' {
			idx = i
			break
		}
	}
	if idx == 0 {
		return [2]string{input, ""}
	}
	return [2]string{input[:idx], input[idx+1:]}
}

func advanceBale(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	switch flow.state.State {
	case AuthStateChoose:
		flow.collected["method"] = input
		if input == "bot_token" {
			base.State = AuthStateInput
			base.FieldType = "token"
			base.Label = "Bot Token"
			return base, nil
		}
		base.State = AuthStateInput
		base.FieldType = "phone"
		base.Label = "Phone Number"
		return base, nil
	case AuthStateInput:
		if flow.collected["method"] == "bot_token" {
			flow.collected["bot_token"] = input
			return tryAuth(flow, base)
		}
		flow.collected["phone"] = input
		err := flow.core.Authenticate(cores.AuthConfig{
			Mode:  cores.AuthModeUser,
			Phone: input,
		})
		if err == nil {
			base.State = AuthStateReady
			if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
				base.DisplayName = profile.DisplayName
				if base.DisplayName == "" {
					base.DisplayName = profile.Username
				}
				base.AvatarB64 = profile.AvatarB64
			}
			return base, nil
		}
		if err.Error() != "otp_required" {
			return nil, err
		}
		base.State = AuthStateOTP
		base.CodeLength = 6
		base.SentTo = "Bale app"
		base.TimeoutSecs = 120
		return base, nil
	case AuthStateOTP:
		flow.collected["otp"] = input
		bc, ok := flow.core.(baleSubmitter)
		if !ok {
			return nil, fmt.Errorf("expected BaleCore for OTP submit")
		}
		err := bc.SubmitOTP(input)
		if err == nil {
			base.State = AuthStateReady
			if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
				base.DisplayName = profile.DisplayName
				if base.DisplayName == "" {
					base.DisplayName = profile.Username
				}
				base.AvatarB64 = profile.AvatarB64
			}
			return base, nil
		}
		if err.Error() == "2fa_required" {
			base.State = AuthState2FA
			base.Label = "Two-Factor Password"
			base.HasRecovery = false
			return base, nil
		}
		return nil, err
	case AuthState2FA:
		flow.collected["2fa"] = input
		bc, ok := flow.core.(baleSubmitter)
		if !ok {
			return nil, fmt.Errorf("expected BaleCore for 2FA submit")
		}
		err := bc.Submit2FA(input)
		if err == nil {
			base.State = AuthStateReady
			if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
				base.DisplayName = profile.DisplayName
				if base.DisplayName == "" {
					base.DisplayName = profile.Username
				}
				base.AvatarB64 = profile.AvatarB64
			}
			return base, nil
		}
		return nil, err
	}
	return nil, fmt.Errorf("unexpected state %s for bale", flow.state.State)
}

func advanceMatrix(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["homeserver"] == "":
		flow.collected["homeserver"] = input
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Username"
		base.Hint = "@user:matrix.org"
		return base, nil
	case flow.collected["username"] == "":
		flow.collected["username"] = input
		base.State = AuthStateInput
		base.FieldType = "password"
		base.Label = "Password"
		return base, nil
	default:
		flow.collected["password"] = input
		return tryAuth(flow, base)
	}
}

func advanceIRC(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["server"] == "":
		flow.collected["server"] = input
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Nickname"
		return base, nil
	case flow.collected["nickname"] == "":
		flow.collected["nickname"] = input
		result, err := tryAuth(flow, base)
		if err == nil {
			return result, nil
		}
		base.State = AuthStateInput
		base.FieldType = "password"
		base.Label = "NickServ Password (optional)"
		base.Hint = "Leave empty to skip"
		return base, nil
	default:
		flow.collected["password"] = input
		return tryAuth(flow, base)
	}
}

func AdvanceXMPP(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["jid"] == "":
		flow.collected["jid"] = input
		base.State = AuthStateInput
		base.FieldType = "password"
		base.Label = "Password"
		return base, nil
	case flow.collected["register_offer"] == "":
		flow.collected["password"] = input
		result, err := tryAuth(flow, base)
		if err == nil {
			return result, nil
		}
		flow.collected["register_offer"] = "1"
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Create this account on the server? (y = register, empty = retry)"
		base.Hint = "y"
		return base, nil
	default:
		flow.collected["register"] = ParseYesNo(input)
		return tryAuth(flow, base)
	}
}

func ParseYesNo(input string) string {
	switch strings.ToLower(strings.TrimSpace(input)) {
	case "y", "yes", "1", "true", "register", "create":
		return "true"
	default:
		return "false"
	}
}

func advanceGitHub(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	flow.collected["token"] = input
	return tryAuth(flow, base)
}

func advanceDeltaChat(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["email"] == "":
		flow.collected["email"] = input
		base.State = AuthStateInput
		base.FieldType = "password"
		base.Label = "IMAP Password"
		return base, nil
	default:
		flow.collected["password"] = input
		return tryAuth(flow, base)
	}
}

func advanceTeamSpeak(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["server"] == "":
		flow.collected["server"] = input
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Nickname"
		return base, nil
	case flow.collected["nickname"] == "":
		flow.collected["nickname"] = input
		result, err := tryAuth(flow, base)
		if err == nil {
			return result, nil
		}
		base.State = AuthStateInput
		base.FieldType = "password"
		base.Label = "Server Password (optional)"
		return base, nil
	default:
		flow.collected["password"] = input
		return tryAuth(flow, base)
	}
}

func advanceMumble(flow *AuthFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["server"] == "":
		flow.collected["server"] = input
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Username"
		return base, nil
	case flow.collected["username"] == "":
		flow.collected["username"] = input
		result, err := tryAuth(flow, base)
		if err == nil {
			return result, nil
		}
		base.State = AuthStateInput
		base.FieldType = "password"
		base.Label = "Password (optional)"
		return base, nil
	default:
		flow.collected["password"] = input
		return tryAuth(flow, base)
	}
}

func tryAuth(flow *AuthFlow, base *AuthState) (*AuthState, error) {
	cfg := BuildAuthConfig(base.Platform, flow.collected)
	err := flow.core.Authenticate(cfg)
	if err != nil {
		if err.Error() == "2fa_required" {
			base.State = AuthState2FA
			base.Label = "Two-Factor Password"
			base.HasRecovery = false
			return base, nil
		}
		return nil, err
	}

	base.State = AuthStateReady
	if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
		base.DisplayName = profile.DisplayName
		if base.DisplayName == "" {
			base.DisplayName = profile.Username
		}
		base.AvatarB64 = profile.AvatarB64
	}
	return base, nil
}

func BuildAuthConfig(platform string, collected map[string]string) cores.AuthConfig {
	cfg := cores.AuthConfig{
		Extra: make(map[string]string),
	}

	switch platform {
	case "telegram":
		if collected["method"] == "bot_token" {
			cfg.Mode = cores.AuthModeBot
			cfg.BotToken = collected["bot_token"]
		} else {
			cfg.Mode = cores.AuthModeUser
			cfg.Phone = collected["phone"]
			cfg.OTP = collected["otp"]
			cfg.Password2F = collected["2fa"]
		}
	case "bale":
		if collected["method"] == "bot_token" {
			cfg.Mode = cores.AuthModeBot
			cfg.BotToken = collected["bot_token"]
		} else {
			cfg.Mode = cores.AuthModeUser
			cfg.Phone = collected["phone"]
			cfg.OTP = collected["otp"]
		}
	case "matrix":
		cfg.Mode = cores.AuthModeUser
		cfg.Extra["homeserver"] = collected["homeserver"]
		cfg.Extra["username"] = collected["username"]
		cfg.Extra["password"] = collected["password"]
	case "irc":
		cfg.Mode = cores.AuthModeUser
		cfg.Extra["server"] = collected["server"]
		cfg.Extra["nick"] = collected["nickname"]
		cfg.Extra["password"] = collected["password"]
	case "xmpp":
		cfg.Mode = cores.AuthModeUser
		cfg.Extra["jid"] = collected["jid"]
		cfg.Extra["password"] = collected["password"]
		if collected["register"] == "true" {
			cfg.Extra["register"] = "true"
		}
	case "github":
		cfg.Mode = cores.AuthModeBot
		cfg.BotToken = collected["token"]
	case "deltachat":
		cfg.Mode = cores.AuthModeUser
		cfg.Extra["email"] = collected["email"]
		cfg.Extra["password"] = collected["password"]
	case "teamspeak":
		cfg.Mode = cores.AuthModeUser
		cfg.Extra["server_address"] = collected["server"]
		cfg.Extra["nickname"] = collected["nickname"]
		cfg.Extra["password"] = collected["password"]
	case "mumble":
		cfg.Mode = cores.AuthModeUser
		cfg.Extra["server"] = collected["server"]
		cfg.Extra["username"] = collected["username"]
		cfg.Extra["password"] = collected["password"]
	}

	return cfg
}
