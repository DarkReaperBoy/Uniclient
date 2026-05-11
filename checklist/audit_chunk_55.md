# create_group_wizard — Audit Findings

## create_group_wizard — multi-step group/channel creation wizard

- [ ] [CRITICAL] Camera capture uses `FilePicker.platform.pickFiles()` instead of a real camera API — "Camera" menu item shown on mobile but calls file picker, never opens camera — `create_group_wizard.dart:341` ← `AyuGram/boxes/add_contact_box.cpp:560` (`Ui::UserpicButton::Role::ChoosePhoto` uses real camera/gallery picker via Qt)

- [ ] [MAJOR] Clipboard paste for images is fundamentally broken — `Clipboard.getData('image/png')` returns `null` on Flutter (only text is supported), so the code silently swallows the exception and falls through to open FilePicker, making "Paste from Clipboard" a misleading alias for file picking — `create_group_wizard.dart:368-396` ← `AyuGram/boxes/add_contact_box.cpp:568` (real clipboard image access via Qt `QImage::fromData`)

- [ ] [MAJOR] TTL picker in new group wizard is a simple 4-option popup (Off/1d/1w/1m), missing 12 additional options and the full `TTLMenu::TTLBox` dialog that AyuGram uses; also does not read the account's default message TTL via `api.selfDestruct().periodDefaultHistoryTTLCurrent()` so groups never inherit the user's default TTL preference — `create_group_wizard.dart:92-97` ← `AyuGram/menu/menu_ttl.cpp:169-184` (16 values: 1d–1y) and `AyuGram/boxes/add_contact_box.cpp:629-657` (TTLBox dialog, reads default TTL)

- [ ] [MAJOR] Default privacy for new channel setup step is Private (`_isPublic = false`); AyuGram's `SetupChannelBox` defaults to Public (`Privacy::Public`) so users see the public username field first — `create_group_wizard.dart:106` ← `AyuGram/boxes/add_contact_box.cpp:979` (`_privacyGroup(std::make_shared<Ui::RadioenumGroup<Privacy>>(Privacy::Public))`)

- [ ] [MAJOR] `_EditPeerTypeBox` always renders the `joinToSend` ("Only members can send") toggle for groups regardless of their privacy state or discussion-link status — AyuGram only shows the `whoSendWrap` section when the group is public OR has a linked discussion channel; private groups without a discussion link never see this section — `create_group_wizard.dart:2699-2713` ← `AyuGram/boxes/peers/edit_peer_type_box.cpp:241-244` (`whoSendWrap->toggle(privacy == HasUsername, ...)` when no discussion link)

- [ ] [MAJOR] `_ProgressRingPainter` forum mode draws the complete rounded-rect outline every frame, entirely ignoring `progress` and `rotation` parameters — the upload spinner appears as a static full ring rather than a rotating arc — `create_group_wizard.dart:1820-1825` ← `AyuGram/boxes/add_contact_box.cpp:563-569` (forum userpic uses `Ui::UserpicButton` which delegates to the same radial progress arc path regardless of shape)
