# strings — Critical mismatch: fabricated notification strings

- [ ] [CRITICAL] Notification content type strings (`lngNotifPhoto`, `lngNotifVideo`, etc. at lines 44-58) do NOT exist in AyuGram source. AyuGram uses `lng_in_dlg_photo`, `lng_in_dlg_video`, `lng_in_dlg_audio`, etc. in `data_media_types.cpp` instead. These are completely fabricated strings. — `strings.dart:44-58` ← `AyuGramDesktop/Telegram/SourceFiles/data/data_media_types.cpp` (actual strings like `lng_in_dlg_photo`, not `lng_notif_photo`)

- [ ] [CRITICAL] Reaction notification strings (`lngNotifReactedToMessage`, `lngNotifReactedToPhoto`, etc. at lines 64-88) do NOT exist in AyuGram source. AyuGram uses `lng_reaction_*` strings (e.g., `lng_reaction_photo`, `lng_reaction_video`, `lng_reaction_sticker`) in `notifications_manager.cpp:ComposeReactionNotification()`. These are completely fabricated and incompatible with actual AyuGram implementation. — `strings.dart:64-88` ← `AyuGramDesktop/Telegram/SourceFiles/window/notifications_manager.cpp:ComposeReactionNotification()` (uses `lng_reaction_*`, not `lng_notif_reacted_to_*`)

## Verified Correct Strings

- ✅ Theme warning strings (lines 15-19): match `window_theme_warning.cpp` (`lng_theme_sure_keep`, `lng_theme_reverting`, `lng_theme_keep_changes`, `lng_theme_revert`)
- ✅ Passcode strings (lines 22-28): match `window_lock_widgets.cpp` (`lng_passcode_*`)
- ✅ Report reaction strings (lines 91-94): match `info_profile_actions.cpp` (`lng_report_reaction_title`, `lng_report_reaction_about`, `lng_report_and_ban_button`)
- ✅ Auto-delete strings (lines 97-98): match `delete_messages_box.cpp` (`lng_enable_auto_delete`, `lng_edit_auto_delete_settings`)
- ✅ Paid post deletion strings (lines 101-107): match `delete_messages_box.cpp` (`lng_suggest_warn_*`)
- ✅ Forward & album strings (lines 39-41): match `notifications_manager.cpp` (`lng_forward_messages`, `lng_in_dlg_album`)
- ✅ Intro strings (lines 8-12): match `intro_signup.cpp`, `intro_step.cpp`, `intro_password_check.cpp` (`lng_intro_finish`, `lng_intro_next`, `lng_signin_cant_email_forgot`)
- ✅ AyuForward strings (lines 120-127): match `ayu_forward.cpp` (`ayu_AyuForwardStatus*`)

## Impact

The fabricated notification strings mean:
1. Flutter app has incompatible notification content type labeling vs. AyuGram Desktop
2. Reaction notifications use wrong format entirely
3. If this file is meant to sync with AyuGram localization, it will fail on all content type notifications
4. ~40 lines of completely unused/incorrect string definitions (lines 44-88)
