/// Platform WebAuthn / passkey support detection.
///
/// Mirrors AyuGram's `Platform::WebAuthn::IsSupported()` (platform_webauthn.h).
/// Passkey login requires the OS authenticator (Touch ID / Windows Hello /
/// FIDO2 security key), which has no pure-Dart implementation and no pure-Go
/// (no-CGo) path. Telegram Desktop's own Linux build returns `false` here
/// (webauthn_linux.cpp:13), so the intro's "Log in using passkey" link is
/// hidden on Linux exactly as upstream — gating on this is the faithful
/// behavior, not a missing feature.
class WebAuthn {
  WebAuthn._();

  /// Whether a platform authenticator is available for passkey login.
  /// Always false in this build (no CGo / platform authenticator binding),
  /// matching Telegram Desktop's Linux `IsSupported()`.
  static bool isSupported() => false;
}
