# engine_models — Data Model Gaps vs AyuGram

## GroupCallParticipant — Missing fields & dead field

- [ ] [MAJOR] `audioLevel` field (Dart:2151) is always 0.0 — never set by Go engine. `dispatch_engine.go:2063` populates the proto but omits `audio_level`; `engine.pb.go:7762` proto struct has no such field. AyuGram uses `sounding` + `speaking` + `volume` from `data_group_call.h:45-47` to drive speaking indicators — `engine_models.dart:2151` ← `AyuGram/data/data_group_call.h:45`

- [ ] [MAJOR] `canSelfUnmute` missing from `GroupCallParticipant` — AyuGram distinguishes admin-forced mute (participant cannot unmute themselves) from self-mute; this drives a different icon in group call UI. Go engine logs it (`telegram.go:562`) but never exports it. Dart model has no field for it — `engine_models.dart:2144` ← `AyuGram/data/data_group_call.h:52`

- [ ] [MAJOR] `raisedHandRating` missing from `GroupCallParticipant` — AyuGram shows a raised-hand indicator ordered by `raisedHandRating`. Field absent from proto (`engine.pb.go:7762`), dispatch, and Dart model. Hand-raise feature entirely invisible in the UI — `engine_models.dart:2144` ← `AyuGram/data/data_group_call.h:43`

- [ ] [MAJOR] `volume` missing from `GroupCallParticipant` — AyuGram exposes per-participant volume (0–20000, kDefaultVolume=10000, kMaxVolume=20000) for the volume knob in group calls. `SetGroupCallParticipantVolume` API method exists but current volume is never returned to the UI. — `engine_models.dart:2144` ← `AyuGram/calls/group/calls_group_common.h:88`

## CachedMessage.copyWith — Fields silently dropped on update

- [ ] [MAJOR] `mediaUnread` and `ttlSeconds` are absent from `copyWith` parameter list and body (`engine_models.dart:947–1171`). Any `copyWith` call (e.g. on `MsgEdited` event) resets both to defaults (`false` / `0`), silently losing the TTL-media state. AyuGram always preserves these across message updates — `engine_models.dart:947` ← `AyuGram/data/data_group_call.h:38` (general data preservation principle; no direct AyuGram counterpart file, this is a Dart-internal correctness issue)

## StoryItem — Missing fields from AyuGram data_story.h

- [ ] [MAJOR] `noForwards` missing from `StoryItem` — AyuGram `data_story.h:299` has `_noForwards` flag that prevents users from re-sharing / saving a story. Go engine's `storyItem` struct (`telegram.go:16778`) does not expose it. Dart model cannot enforce the restriction — `engine_models.dart:2851` ← `AyuGram/data/data_story.h:299`

- [ ] [MAJOR] `expires` timestamp missing from `StoryItem` — AyuGram `data_story.h:289` has `_expires` (Unix timestamp when story disappears). Neither Go engine (`telegram.go:16778`) nor Dart model expose it. "N hours remaining" countdown on story viewer is impossible — `engine_models.dart:2851` ← `AyuGram/data/data_story.h:289`

- [ ] [MAJOR] `forwards` and `reactions` counts missing from `StoryItem` — AyuGram `StoryViews` struct (`data_story.h:78-80`) contains `reactions`, `forwards`, `views`. Dart model only has `views`; the other two stats (shown in story viewer) are unreachable — `engine_models.dart:2861` ← `AyuGram/data/data_story.h:78`
