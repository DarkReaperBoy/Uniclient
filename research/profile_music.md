# Profile Music (tdesktop "Saved Music") — slice 206 research

Verified 2026-09-14 against primary sources (tdesktop dev tree via GitHub API,
gotd v0.161.0 = layer 228 generated code). This feature is NEW upstream
(tdesektop ~Aug 2026, AyuGramDesktop merged it in 7.0.9-dev: "fix: music
widget" 2026-08-05) — after our 2026-09-13 parity truth pass, hence a fresh
gap.

## What it is

Users can pin songs on their profile ("profile music"). Every user profile
can carry an ordered playlist; other users can listen to it and save songs
from it to their own profile.

## Wire surface (layer 228 — all present in gotd v0.161.0)

- `users.getSavedMusic(id: InputUser, offset, limit, hash)`
  → `users.savedMusicNotModified{count}` | `users.savedMusic{count, documents[]}`
- `users.getSavedMusicByID(id, documents[]: InputDocument[])` — refresh refs
- `account.getSavedMusicIDs(countHash)` → `account.savedMusicIDs{ids[]}`
  | `account.savedMusicIDsNotModified` (own full ID list; hash = sum of ids
  in tdesktop Api::CountHash style)
- `account.saveMusic(flags{unsave, after_id}, id: InputDocument, after: InputDocument)`
  — semantics per gotd doc comments:
  - plain: add song (or move to TOP if already present)
  - +after_id: insert/move AFTER the passed song
  - +unsave: remove
- `userFull.saved_music: flags.0?Document` — the last-saved doc (refresh hint)
- tdesktop update path: userFull processing calls `savedMusic().apply(user,
  last)` → rotate-to-front / insert + reload.

## tdesktop UI surfaces (info/saved/*, history_view_save_document_action.cpp)

1. Profile panel (users only — `Supported = peerIsUser`): a MusicButton row
   under the cover showing the FIRST song (title + performer, music glyph);
   tap → the peer's music section (full playlist).
2. Music section: playlist rows (song name via FormatSongNameFor), select
   mode, paging; own profile rows support remove + drag reorder
   (account.saveMusic after_id).
3. Audio-bubble context menu ("Save music to…" submenu for
   `isMusicForProfile()` docs = audio w/ title+performer):
   - "Add to profile music" (not in profile) → account.saveMusic + toast
   - "Save to Saved Messages" → forward to self
   - "Save to folder" → save-as file
4. Music attach box lists your saved music as a pick source (out of slice
   scope: our music attach is the OS picker; adding an in-app saved-music
   picker is a separate future slice).

## Our implementation (slice 206)

- Core: `cores/telegram_savedmusic.go` — normalize documents →
  MusicTrackInfo (title/performer/duration from DocumentAttributeAudio,
  non-voice only), GetProfileMusic (users.getSavedMusic hash=0 fresh),
  SaveProfileMusicDoc (flags mapping: unsave / after), OwnSavedMusicIDs
  (account.getSavedMusicIDs). RPC wrappers already existed (bulk surface
  slice); this adds the typed feature layer.
- Engine: `engine/profilemusic.go` + migrateV55 (`profile_music` cache
  table, position-ordered per (account, peer)) + EventProfileMusicChanged
  → GUI panel refresh. Playback: download via core DownloadFile into the
  media cache, then the shared in-app player (PlayMedia) keyed
  (account, "profilemusic", docID).
- GUI: `gui/profilemusic.go` — panel "Music" section (first track + count,
  opens the playlist surface), full playlist view (tap = play, own rows:
  move up/down + remove; other rows: add-to-my-profile), bubble-menu
  add/remove gated on real own-ID state.

Ratings (§1.14): telegram core good (8/10 — withAPI-clean, wrappers exist;
extend, don't replace). Engine cache pattern proven (saved-sublist slices);
reuse. GUI panel/dialog patterns proven (mute dialog, saved sublists).
