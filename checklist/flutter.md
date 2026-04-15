# Flutter UI — Implementation Checklist

Status: **ALPHA** — scaffold exists, Telegram basic flow works, many features are placeholders/stubs/broken. See [gui.md](gui.md) for full bug list. Last updated: 2026-04-15, session 24.

For detailed per-component status with checkmarks, see [gui.md](gui.md).

## Architecture

- **Go backend** compiled to `libcores.so` (Linux), loaded via `dart:ffi`
- **Protobuf FFI bridge**: single entry point, 3,564 methods, async via `Isolate.run`
- **Engine layer**: SQLite cache, auth FSM, pending queue, media pipeline, reconnect
- **Provider state**: `AppState` (platform/theme), `ChatState` (chats/messages), `AuthState` (auth flow)
- **Event delivery**: `NativeCallable.listener` (Go→Dart) + 3-second polling fallback

## Core Files

| File | Purpose | Status |
|------|---------|--------|
| `lib/main.dart` | App entry, Provider setup | Done |
| `lib/bridge/ffi_bridge.dart` | FFI bindings to libcores.so | Done |
| `lib/bridge/engine_service.dart` | Typed Dart wrappers for engine methods | Done |
| `lib/proto/engine.pb.dart` | Protobuf message classes | Done |
| `lib/models/engine_models.dart` | Dart model classes (ChatInfo, CachedMessage, etc.) | Done |
| `lib/state/app_state.dart` | AppState ChangeNotifier | Done |
| `lib/state/chat_state.dart` | ChatState ChangeNotifier | Done |
| `lib/state/auth_state.dart` | AuthState ChangeNotifier | Done |
| `lib/theme/theme.dart` | AppColors, dark/light ThemeData | Done |
| `lib/screens/home_screen.dart` | Main layout (rail + sidebar + chat + right panel) | Done |
| `lib/screens/settings_screen.dart` | Settings with persistence to engine | Done |
| `lib/screens/auth_screen.dart` | 7-state auth FSM UI | Done |
| `lib/widgets/platform_rail.dart` | Platform icon strip | Done |
| `lib/widgets/sidebar.dart` | Chat list + search + user panel | Done |
| `lib/widgets/chat_view.dart` | Messages + input + emoji integration | Done |
| `lib/widgets/emoji_panel.dart` | Emoji/sticker/GIF panel | Done |
| `lib/widgets/forward_dialog.dart` | Forward message chat picker | Built |
| `lib/widgets/media_viewer.dart` | Full-screen media viewer | Built |
| `lib/widgets/notification_overlay.dart` | In-app notification toasts | Built |

## Test Suites

| File | Tests | Status |
|------|-------|--------|
| `test/bridge_test.dart` | 14 | Pass (requires libcores.so) |
| `test/widget_test.dart` | 2 | Pass |
| `test/widget_comprehensive_test.dart` | 83 | Pass (no FFI needed) |
| `test/telegram_auth_test.dart` | 1 | Pass (live Telegram auth) |
| `test/telegram_send_test.dart` | 1 | Pass (live send + verify) |
| `test/platform_gui_test.dart` | 34 | Pass (7/10 platforms connected, 2 skipped, 1 geo-restricted) |

## What's Working (125 items)

- Full 3-panel layout with responsive breakpoints
- Platform rail with all 10 platforms, status dots, unread badges, drag reorder, hover squircle, context menu
- Chat list with search, pin/mute/archive, context menus, type icons, draft preview, custom folders
- Message bubbles with reply, edit, forward, status indicators, hover actions, reactions UI
- Emoji panel (1500+ emoji, categories, search, recently used, skin tone picker)
- Sticker pack browser (4 mock packs, tab selection)
- Full auth flow for all platforms
- Settings: theme, accent color (12 presets), per-platform themes, font scale, cache, privacy, notifications, download dir, account removal
- Dark/light/system themes with Inter font
- Media metadata pipeline (Go → proto → Dart)
- Chat header: typing animation, pinned messages sheet, breadcrumb for topics, info dialog
- Input: mic/camera buttons, markdown toolbar, mention autocomplete, voice recording UI
- Topic group: channel tab bar, per-channel switching
- Channel broadcast style (no avatar/name)
- Custom status text in user panel

## What's Built But Untested (29 items)

- Media inline rendering (images, video, audio, files)
- Rich text parsing (URLs, code blocks, inline code)
- Responsive layout (narrow/medium/wide breakpoints)
- Topic group drill-in with slide animation
- Folder tabs (All/DMs/Groups/Channels) + custom folders
- Sticker/GIF tabs + sticker pack browser
- Message multi-select mode
- Forward dialog (wired to context menu)
- Full-screen media viewer
- Notification overlay toasts
- Reactions chip UI + quick picker
- Voice recording bar UI (no audio capture)
- Video recording placeholder

## Remaining Work (all built, need live testing/wiring)

- Wire reaction engine calls (UI done, backend not connected)
- Actual audio/video capture for recording UI (visual UI done)
- Real sticker/GIF API integration per platform
- Right panel real content (members, search, threads — placeholders built)
- Voice/video call screen (buttons exist, no call UI yet)
- System tray + desktop notifications (notification overlay built, OS integration pending)
