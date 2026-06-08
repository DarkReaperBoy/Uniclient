package engine

import (
	"fmt"
	"strings"
	"sync"

	"uniclient/cores"
)

// --- Auth state types ---

const (
	AuthStateChoose  = "choose"
	AuthStateInput   = "input"
	AuthStateOTP     = "otp"
	AuthState2FA     = "2fa"
	AuthStateQR      = "qr"
	AuthStateSignUp  = "signup"
	AuthStateEmail   = "email"
	AuthStateReady   = "ready"
	AuthStateError   = "error"
)

// AuthState represents the current auth step for a platform account.
type AuthState struct {
	AccountID string `json:"account_id"`
	Platform  string `json:"platform"`
	State     string `json:"state"`

	// Fields used by different states:
	Options      []AuthOption `json:"options,omitempty"`       // choose state
	FieldType    string       `json:"field_type,omitempty"`    // input state
	Label        string       `json:"label,omitempty"`         // input/otp/2fa
	Hint         string       `json:"hint,omitempty"`          // input/otp/2fa
	Error        string       `json:"error,omitempty"`         // input/error state
	CodeLength   int          `json:"code_length,omitempty"`   // otp state
	SentTo       string       `json:"sent_to,omitempty"`       // otp state
	TimeoutSecs  int          `json:"timeout_secs,omitempty"`  // otp state
	CanResend    bool         `json:"can_resend,omitempty"`    // otp state
	HasRecovery  bool         `json:"has_recovery,omitempty"`  // 2fa state
	QRData       []byte       `json:"qr_data,omitempty"`       // qr state
	QRExpiresIn  int          `json:"qr_expires_in,omitempty"` // qr state
	DisplayName  string       `json:"display_name,omitempty"`  // ready state
	AvatarB64    string       `json:"avatar_b64,omitempty"`    // ready state
	Message        string       `json:"message,omitempty"`         // error state
	Recoverable    bool         `json:"recoverable,omitempty"`     // error state
	CodeByTelegram bool         `json:"code_by_telegram,omitempty"` // otp state: code sent via Telegram app
	CodeByFragmentUrl string    `json:"code_by_fragment_url,omitempty"` // otp state: open this URL instead of typing a code
	Email             string    `json:"email,omitempty"`                // email state: prefilled address
	EmailPatternSetup string    `json:"email_pattern_setup,omitempty"`  // otp state: masked email the verify code went to
}

type AuthOption struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// authFlow tracks an in-progress auth flow.
type authFlow struct {
	mu        sync.Mutex
	state     *AuthState
	collected map[string]string // accumulated inputs
	core      cores.Core        // core being authenticated
}

var (
	authFlowsMu sync.Mutex
	authFlows   = make(map[string]*authFlow) // accountID → flow
)

// StartAuth begins the auth flow for a new account.
func (e *Engine) StartAuth(accountID string) (*AuthState, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account %q not found", accountID)
	}

	// Create core instance.
	factory := getCoreFactory()
	if factory == nil {
		return nil, fmt.Errorf("no core factory registered")
	}
	core, err := factory(acc.Platform, accountID)
	if err != nil {
		return nil, fmt.Errorf("create core: %w", err)
	}
	// Install any configured proxy before the core connects.
	e.applyProxyToCore(core)

	// Get initial state.
	initial := initialAuthState(acc.Platform, accountID)

	flow := &authFlow{
		state:     initial,
		collected: make(map[string]string),
		core:      core,
	}

	authFlowsMu.Lock()
	authFlows[accountID] = flow
	authFlowsMu.Unlock()

	e.emitEvent(EventAuthState, accountID, initial)
	return initial, nil
}

// SubmitAuthInput advances the auth flow with user input.
func (e *Engine) SubmitAuthInput(accountID, input string) (*AuthState, error) {
	authFlowsMu.Lock()
	flow, ok := authFlows[accountID]
	authFlowsMu.Unlock()
	if !ok {
		return nil, fmt.Errorf("no auth flow for %q", accountID)
	}

	flow.mu.Lock()
	defer flow.mu.Unlock()

	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account %q not found", accountID)
	}

	next, err := advanceAuth(acc.Platform, flow, input)
	if err != nil {
		// Return error state.
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

	flow.state = next

	// Entering QR: install the push-refresh callback so an updateLoginToken
	// (phone scanned the code) re-exports the token immediately rather than
	// waiting for the expiry poll. Mirrors AyuGram QrWidget::checkForTokenUpdate.
	if next.State == AuthStateQR {
		if tc, ok := flow.core.(*cores.TelegramCore); ok {
			tc.SetQRRefreshCallback(func() { go e.onQRTokenUpdate(accountID) })
		}
	}

	// If ready, finalize.
	if next.State == AuthStateReady {
		e.finalizeAuth(accountID, acc, flow)
	}

	e.emitEvent(EventAuthState, accountID, next)
	return next, nil
}

// onQRTokenUpdate re-exports the QR login token after an updateLoginToken push
// and emits the resulting state to the UI. On acceptance the session is
// finalized. Mirrors AyuGram QrWidget::checkForTokenUpdate → refreshCode().
// Runs in its own goroutine (off the MTProto update path) to avoid blocking.
func (e *Engine) onQRTokenUpdate(accountID string) {
	authFlowsMu.Lock()
	flow, ok := authFlows[accountID]
	authFlowsMu.Unlock()
	if !ok {
		return
	}

	flow.mu.Lock()
	defer flow.mu.Unlock()

	if flow.state == nil || flow.state.State != AuthStateQR {
		return
	}
	tc, ok := flow.core.(*cores.TelegramCore)
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

// CancelAuth cancels an in-progress auth flow.
func (e *Engine) CancelAuth(accountID string) {
	authFlowsMu.Lock()
	flow, ok := authFlows[accountID]
	if ok {
		if flow.core != nil {
			flow.core.Close()
		}
		delete(authFlows, accountID)
	}
	authFlowsMu.Unlock()
}

// finalizeAuth saves credentials, attaches core, and starts connection.
func (e *Engine) finalizeAuth(accountID string, acc *Account, flow *authFlow) {
	// Build auth config from collected inputs.
	cfg := buildAuthConfig(acc.Platform, flow.collected)

	// Save credentials to vault.
	e.SaveCredentials(accountID, cfg)

	// Attach core to account.
	e.accountsMu.Lock()
	acc.Core = flow.core
	acc.ConnState = ConnConnected
	if flow.state.DisplayName != "" {
		acc.DisplayName = flow.state.DisplayName
	}
	// Fetch self-profile for verified/premium badges, phone and username.
	if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
		acc.IsVerified = profile.IsVerified
		acc.IsPremium = profile.IsPremium
		acc.Phone = profile.Phone
		acc.Username = profile.Username
	}
	e.accountsMu.Unlock()

	// Update DB.
	e.UpdateAccountDisplay(accountID, acc.DisplayName, "")

	// Register update handler.
	flow.core.OnUpdate(func(u cores.Update) {
		e.handleUpdate(accountID, u)
	})

	// Clean up flow.
	authFlowsMu.Lock()
	delete(authFlows, accountID)
	authFlowsMu.Unlock()

	// Emit connection state.
	e.emitConnState(accountID, ConnConnected, "")
	e.emitAccountList()

	// Start background sync.
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.syncAccount(nil, accountID)
	}()
}

// --- Platform-specific auth logic ---

// initialAuthState returns the first auth state for a platform.
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
	case "rubika":
		base.State = AuthStateInput
		base.FieldType = "phone"
		base.Label = "Phone Number"
		base.Hint = "+98..."
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

// advanceAuth processes input and returns the next state.
// When enough info is collected, calls core.Authenticate().
func advanceAuth(platform string, flow *authFlow, input string) (*AuthState, error) {
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
		return advanceXMPP(flow, input, base)
	case "github":
		return advanceGitHub(flow, input, base)
	case "rubika":
		return advanceRubika(flow, input, base)
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

// --- Per-platform advance functions ---

func advanceTelegram(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
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
			tc, ok := flow.core.(*cores.TelegramCore)
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
				// Session was already valid
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
		// QR refresh/poll — re-export token and check acceptance
		tc, ok := flow.core.(*cores.TelegramCore)
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
		// Trigger phone auth — core will send OTP.
		err := flow.core.Authenticate(cores.AuthConfig{
			Mode:  cores.AuthModeUser,
			Phone: input,
		})
		if err == nil {
			// Session was already authenticated — skip OTP.
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
		tc, ok := flow.core.(*cores.TelegramCore)
		if !ok {
			return nil, fmt.Errorf("expected TelegramCore for phone auth")
		}
		if err.Error() == "email_setup_required" {
			// The account must set up a login email before a phone code is sent
			// (intro_email.cpp / EmailStatus::SetupRequired).
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
		tc, ok := flow.core.(*cores.TelegramCore)
		if !ok {
			return nil, fmt.Errorf("expected TelegramCore for OTP")
		}
		if input == "__no_telegram_code" {
			// AyuGram CodeWidget::noTelegramCode — resend via the next method and
			// switch out of Telegram-app delivery into the call-countdown mode.
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
			byTg, fragURL, timeout, length := tc.AuthCodeInfo()
			if length <= 0 {
				length = 5
			}
			base.State = AuthStateOTP
			base.CodeLength = length
			base.SentTo = "Telegram"
			base.TimeoutSecs = timeout
			base.CodeByTelegram = byTg
			base.CodeByFragmentUrl = fragURL
			base.CanResend = true
			return base, nil
		}
		// Email-setup detour: the first code entered here verifies the email; the
		// server then sends a phone code which we sign in with manually.
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
		// For Telegram user mode, use the interactive SubmitOTP method.
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
			tc, ok := flow.core.(*cores.TelegramCore)
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
			tc, ok := flow.core.(*cores.TelegramCore)
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
		// For Telegram user mode, use the interactive Submit2FA method.
		if flow.collected["method"] != "bot_token" {
			tc, ok := flow.core.(*cores.TelegramCore)
			if !ok {
				return nil, fmt.Errorf("expected TelegramCore for 2FA submit")
			}
			// In the email-setup detour the gotd flow is parked, so the SRP check
			// must run on preAuthAPI directly.
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
		// Login-email setup (intro_email.cpp). Collect the address, send the
		// verification code, then move to the OTP step in email-verify mode.
		tc, ok := flow.core.(*cores.TelegramCore)
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
		// Input format: "firstName\nlastName"
		tc, ok := flow.core.(*cores.TelegramCore)
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

// telegramReadyState marks the flow authenticated and fills the display profile.
func telegramReadyState(flow *authFlow, base *AuthState) *AuthState {
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

// applyTelegram2FAState fills the real cloud-password recovery flag (and hint)
// onto a 2FA auth state by reading the live password state on the in-progress
// connection, so the login UI offers recovery-by-email exactly when the account
// has a recovery address — instead of always pushing toward account reset. The
// engine used to hardcode HasRecovery=false here and only flip it true after a
// recovery request, which the UI's own gate then prevented from ever being sent.
// Mirrors AyuGram CodeWidget::gotPassword → pwdState.hasRecovery
// (intro_code.cpp:341-358). Falls back to no-recovery if the state can't be read.
func applyTelegram2FAState(tc *cores.TelegramCore, base *AuthState) {
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

// telegramOTPState builds the OTP step from the code-delivery details captured by
// the core (Telegram-app code, Fragment URL, SMS) — AyuGram updateDescText.
func telegramOTPState(tc *cores.TelegramCore, base *AuthState) *AuthState {
	byTg, fragURL, timeout, length := tc.AuthCodeInfo()
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
	switch {
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

func advanceBale(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
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
		// Trigger phone auth — Bale will send OTP via StartPhoneAuth.
		err := flow.core.Authenticate(cores.AuthConfig{
			Mode:  cores.AuthModeUser,
			Phone: input,
		})
		if err == nil {
			// Session was already valid — no OTP needed.
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
		bc, ok := flow.core.(*cores.BaleCore)
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
		bc, ok := flow.core.(*cores.BaleCore)
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

func advanceMatrix(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
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

func advanceIRC(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["server"] == "":
		flow.collected["server"] = input
		base.State = AuthStateInput
		base.FieldType = "text"
		base.Label = "Nickname"
		return base, nil
	case flow.collected["nickname"] == "":
		flow.collected["nickname"] = input
		// Try connecting — might work without password.
		result, err := tryAuth(flow, base)
		if err == nil {
			return result, nil
		}
		// Ask for NickServ password.
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

func advanceXMPP(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["jid"] == "":
		flow.collected["jid"] = input
		base.State = AuthStateInput
		base.FieldType = "password"
		base.Label = "Password"
		return base, nil
	default:
		flow.collected["password"] = input
		return tryAuth(flow, base)
	}
}

func advanceGitHub(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
	flow.collected["token"] = input
	return tryAuth(flow, base)
}

func advanceRubika(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
	switch {
	case flow.collected["phone"] == "":
		flow.collected["phone"] = input
		base.State = AuthStateOTP
		base.CodeLength = 5
		base.SentTo = "SMS"
		return base, nil
	default:
		flow.collected["otp"] = input
		return tryAuth(flow, base)
	}
}

func advanceDeltaChat(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
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

func advanceTeamSpeak(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
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

func advanceMumble(flow *authFlow, input string, base *AuthState) (*AuthState, error) {
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

// tryAuth attempts to authenticate with the collected inputs.
func tryAuth(flow *authFlow, base *AuthState) (*AuthState, error) {
	cfg := buildAuthConfig(base.Platform, flow.collected)
	err := flow.core.Authenticate(cfg)
	if err != nil {
		// Check for 2FA requirement.
		if err.Error() == "2fa_required" {
			base.State = AuthState2FA
			base.Label = "Two-Factor Password"
			base.HasRecovery = false
			return base, nil
		}
		return nil, err
	}

	// Success.
	base.State = AuthStateReady
	// Try to get display name.
	if profile, pErr := flow.core.GetProfile(""); pErr == nil && profile != nil {
		base.DisplayName = profile.DisplayName
		if base.DisplayName == "" {
			base.DisplayName = profile.Username
		}
		base.AvatarB64 = profile.AvatarB64
	}
	return base, nil
}

// buildAuthConfig converts collected inputs into a cores.AuthConfig.
func buildAuthConfig(platform string, collected map[string]string) cores.AuthConfig {
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
	case "github":
		cfg.Mode = cores.AuthModeBot
		cfg.BotToken = collected["token"]
	case "rubika":
		cfg.Mode = cores.AuthModeUser
		cfg.Phone = collected["phone"]
		cfg.OTP = collected["otp"]
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
