package engine

import (
	"fmt"
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
	Message      string       `json:"message,omitempty"`       // error state
	Recoverable  bool         `json:"recoverable,omitempty"`   // error state
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

	// If ready, finalize.
	if next.State == AuthStateReady {
		e.finalizeAuth(accountID, acc, flow)
	}

	e.emitEvent(EventAuthState, accountID, next)
	return next, nil
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
			base.State = AuthStateQR
			base.QRExpiresIn = 30
			// QR data would come from core
			return base, nil
		}
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
		if err.Error() != "otp_required" {
			return nil, err
		}
		base.State = AuthStateOTP
		base.CodeLength = 5
		base.SentTo = "Telegram app"
		base.TimeoutSecs = 60
		return base, nil
	case AuthStateOTP:
		flow.collected["otp"] = input
		// For Telegram user mode, use the interactive SubmitOTP method.
		if flow.collected["method"] != "bot_token" {
			tc, ok := flow.core.(*cores.TelegramCore)
			if !ok {
				return nil, fmt.Errorf("expected TelegramCore for OTP submit")
			}
			err := tc.SubmitOTP(input)
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
		}
		return tryAuth(flow, base)
	case AuthState2FA:
		flow.collected["2fa"] = input
		// For Telegram user mode, use the interactive Submit2FA method.
		if flow.collected["method"] != "bot_token" {
			tc, ok := flow.core.(*cores.TelegramCore)
			if !ok {
				return nil, fmt.Errorf("expected TelegramCore for 2FA submit")
			}
			err := tc.Submit2FA(input)
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
		return tryAuth(flow, base)
	}
	return nil, fmt.Errorf("unexpected state %s for telegram", flow.state.State)
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
		base.State = AuthStateOTP
		base.CodeLength = 5
		base.SentTo = "Bale app"
		return base, nil
	case AuthStateOTP:
		flow.collected["otp"] = input
		return tryAuth(flow, base)
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
