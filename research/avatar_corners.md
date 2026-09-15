# Avatar Corners (AyuGram userpic styling) — slice 215 research

Primary sources (GitHub API on AyuGramDesktop dev + its lib_ui fork +
tdesktop dev, verified 2026-09-15). This closes the last actionable half
of parity row "Ayu toasts + logo/userpic styling" (the logo half = app
icon picker, already slice 170).

## What the feature is (pinned from source)

AyuGram Settings → Appearance → "Avatar Corners"
(settings_appearance.cpp `BuildAvatarCorners`, engine
ayu/ui/ayu_userpic.cpp):

- Slider, `kMaxAvatarCorners + 1` = **24 discrete steps, integer 0..23**,
  default **23** (= circle; `_avatarCorners = 23` ayu_settings.h:711,
  `kMaxAvatarCorners = 23` in lib_ui ayu/ayu_ui_settings.h).
- Pill value label (`mapRadius`): `0 → "SQUARE"`, `23 → "CIRCLE"`, else
  the number (AyuGram/Languages Shared.json: AvatarCornersSquare_PC
  "Square", AvatarCornersCircle_PC "Circle", upper-cased at render).
- `ComputeRadius(int pixelSize)` (ayu_userpic.cpp):
  `corners >= 23 → size/2` (circle); `corners <= 0 → 0` (square);
  else `int(double(corners)/23.0 * size/2.0)`.
- Toggle **"Single Corner Radius"** (default false), description:
  "Forums will have the same avatar shape as chats."
  (`ShouldOverrideShape`: Circle/Auto → always override;
  Forum/Monoforum → only when singleCornerRadius).
- Forum avatars natively (tdesktop data_peer.cpp userpicShape +
  ui/userpic_view.cpp): corner radius = **30% of avatar size**
  (`ForumUserpicRadiusMultiplier() = 0.3`, rounded square — not circle).
- Preview widget (avatar_corners_preview.cpp): a real dialog row for the
  @AyuGramReleases channel, repainted live as the slider moves.
- AyuGram prompts for restart on release; Gio re-renders per frame so
  Uniclient applies it live (no restart needed — honest improvement).

## Plan (arch rating 9/10 — extend the slice-170/93 config-slider pattern)

Pure helpers in `gui/avatarcorners.go` (kMax=23 const, radius formula,
pill label, forum 30% radius, chat-level resolver incl. the toggle,
three-way clip shape). Plumbing mirrors AyuAppIcon (utils.AppConfig
`AyuAvatarCorners *int` + `AyuSingleCornerRadius *bool`, engine
ConfigChanges + apply with clamp, cfgSnapshot effective fields,
cfgFromAppConfig nil→23 / nil→false). Rendering: UI.Avatar gains a
shaped twin reading live UI state (letter avatars), avatarFromImage
threads a radius (image avatars), drawBookmarkAvatar follows the slider,
forum chats (engine ChatInfo.IsForum) resolve 30% unless the toggle is
on — chatAvatar is the chokepoint (it holds the ChatInfo). Settings
section "Ayu · Avatar corners": slider row via the shared
layoutSliderRow helper (24 steps, SQUARE/CIRCLE/number pill), live
preview row (a representative chat row — "Uniclient Releases / Better
late than never": our brand on AyuGram's structure; §1.10 note — it is
a settings preview control, not fake app content), and the
Single-corner toggle with the exact upstream string. Persist debounced
600 ms like the layout sliders; apply live everywhere.

Status dot / story ring stay circular (they sit on/outside the avatar;
AyuGram's online-badge repositioning is a visual micro-detail — noted
as the honest remainder).
