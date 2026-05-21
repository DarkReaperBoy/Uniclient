// Centralised translatable strings — maps to Telegram lang pack keys.
// Replace with server-sourced language packs when i18n is implemented.

class TrStrings {
  TrStrings._();

  // Theme confirmation overlay (window_theme_warning.cpp)
  static String lngThemeSureKeep() => 'Keep this theme?';
  static String lngThemeReverting(int count) =>
      'Theme will revert in $count second${count == 1 ? '' : 's'}';
  static String lngThemeKeepChanges() => 'Keep Changes';
  static String lngThemeRevert() => 'Revert';

  // Passcode lock (window_lock_widgets.cpp)
  static String lngPasscodeEnter() => 'Enter your local passcode';
  static String lngPasscodePh() => 'Your passcode';
  static String lngPasscodeSubmit() => 'Submit';
  static String lngPasscodeLogout() => 'Log out';
  static String lngPasscodeWrong() => 'Wrong passcode';
  static String lngFloodError() => 'Too many tries. Please try again later.';

  // Notification grouping (notifications_manager.cpp)
  static String lngForwardMessages(int count) =>
      '$count forwarded message${count == 1 ? '' : 's'}';
  static String lngInDlgAlbum() => 'Album';
}
