## Phase 8: Flutter UI

### Bridge Integration
- [ ] `ffi_bridge.dart` — dart:ffi bindings to Go shared lib
- [ ] `wasm_bridge.dart` — WASM bindings for web
- [ ] `bridge.dart` — conditional export (ffi vs wasm)
- [ ] Event stream (Go→Dart) working via ReceivePort / StreamController
- [ ] All Core methods callable from Dart

### Theme & Design System
- [ ] Dark-first Material 3 theme (true black OLED, electric indigo accent)
- [ ] Light mode variant
- [ ] System follow option
- [ ] 8dp spacing grid, elevation, ripple effects
- [ ] Smooth page transitions

### Screens
- [ ] Splash / startup (vault password prompt, loading)
- [ ] Login (platform selector, mode toggle, Telegram API client dropdown, server selector)
- [ ] Account switcher (server rail desktop, drawer mobile)
- [ ] Chat list (server rail + chat list + topics hierarchy)
- [ ] Chat / conversation (message bubbles, markdown rendering, media, encryption)
- [ ] Reply UI (quoted block, compose preview bar)
- [ ] Read receipts UI (checks, "seen by" list in groups)
- [ ] File upload/download (progress, encrypted toggle)
- [ ] Message search
- [ ] Settings (theme, proxy, encryption, accounts, about)
- [ ] System tray + notifications
- [ ] Call screen (1:1 and group)
- [ ] Telegram-specific screens (contacts, folders, sessions, group info)

### Widgets
- [ ] `message_bubble.dart` — all variants (text, media, encrypted, failed, markdown)
- [ ] `markdown_body.dart` — Markdown rendering with syntax highlighting
- [ ] `chat_tile.dart` — avatar, name, preview, badges
- [ ] `account_switcher.dart` — server rail / drawer
- [ ] `lock_button.dart` — encryption mode selector
- [ ] `media_player.dart` — inline video/audio/voice
- [ ] `download_indicator.dart` — progress circle/bar

### Platform-Specific
- [ ] Desktop: multi-column, hover states, right-click menus, keyboard shortcuts, system tray
- [ ] Mobile: single-column, bottom nav, swipe-to-reply, pull-to-refresh
- [ ] Web: desktop layout, browser APIs for file/notification

### Dart Tests
- [ ] `splash_test.dart`
- [ ] `login_test.dart`
- [ ] `chat_list_test.dart`
- [ ] `chat_test.dart`
- [ ] `message_bubble_test.dart`
- [ ] `markdown_body_test.dart`
- [ ] `lock_button_test.dart`
- [ ] `media_player_test.dart`
- [ ] `download_indicator_test.dart`
- [ ] `account_switcher_test.dart`
- [ ] `call_screen_test.dart`
- [ ] `settings_test.dart`
- [ ] `search_test.dart`
- [ ] `system_tray_test.dart`
- [ ] `notifications_test.dart`
- [ ] Golden snapshot tests
- [ ] Bridge mock tests
- [ ] State management tests
- [ ] **Gate**: `flutter test` — ALL PASS

---
