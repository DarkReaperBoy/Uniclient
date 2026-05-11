# contacts_screen — Contacts box: 4 critical, 5 major

- [ ] [CRITICAL] `_editContact()` shows the edit dialog but has no `.then()` handler to reload contacts on success — after saving, parent `_ContactsBoxState._contacts` is never refreshed, so the edited name stays stale until box is closed and reopened — `contacts_screen.dart:839` ← `boxes/add_contact_box.cpp:486` (AyuGram propagates changes via session data signals automatically)

- [ ] [CRITICAL] `_deleteContact()` context-menu callback fires `engine.deleteContact()` fire-and-forget with no reload afterward — deleted contact remains visible in the list until the box is closed and reopened — `contacts_screen.dart:860` ← `boxes/add_contact_box.cpp:496` (AyuGram removes peer from data layer via signal; Dart has no equivalent refresh)

- [ ] [CRITICAL] `_blockUser()` context-menu callback fires `engine.blockUser()` with no reload — blocked contact stays in list — `contacts_screen.dart:875` ← same pattern as above

- [ ] [CRITICAL] `AddContactBox._save()` on success just pops the dialog (`Navigator.of(context).pop(true)`) — AyuGram opens the newly-added user's chat with `window->showPeerHistory(user)` when the user is found; this navigation is completely absent — `contacts_screen.dart:1234` ← `boxes/add_contact_box.cpp:487`

- [ ] [MAJOR] `_filteredContacts` getter (line 263) is uncached and called twice per visible `ListView` item — once for `itemCount` and once inside each `itemBuilder` — triggering O(n log n) sort on every call; `_sortedCache` is declared at line 69 but never populated or read, indicating the optimisation was planned but not implemented — `contacts_screen.dart:263,434,437` ← (performance; no direct AyuGram equivalent needed, `_sortedCache` dead code)

- [ ] [MAJOR] `AddContactBox._isValidPhone()` at line 1158 allows `digits.startsWith('42') && digits.length == 4` (e.g. "4299" passes), but AyuGram's `IsValidPhone` only allows the literal `"4242"` at length 4 — all other 4-digit "42xx" strings must fail validation — `contacts_screen.dart:1158` ← `boxes/add_contact_box.cpp:59`

- [ ] [MAJOR] `AddContactBox._save()` does not implement the first-name fallback: AyuGram sets `firstName = lastName; lastName = ""` when `firstName.isEmpty()` (but lastName is non-empty), so the contact is saved with a name; Dart shows an error instead of applying the fallback — `contacts_screen.dart:1195` ← `boxes/add_contact_box.cpp:449`

- [ ] [MAJOR] `_PhoneNumberFormatter` inserts a space after every 3 digits regardless of country (line 1512: `if (i > 0 && i % 3 == 0) buf.write(' ')`), producing wrong grouping for most locales (US should be 3-3-4, not 3-3-3-1); AyuGram uses a country-aware `PhoneInput` widget — `contacts_screen.dart:1511` ← `boxes/add_contact_box.cpp:295` (uses `Ui::PhoneInput`)

- [ ] [MAJOR] `_CountryRow` horizontal padding is `EdgeInsets.symmetric(horizontal: 16)` giving 16 px left; AyuGram style requires `countryRowPadding: margins(22px, 9px, 8px, 0px)` — left is 22 px, a ~38% deviation — `contacts_screen.dart:1800` ← `boxes/boxes.style:46`
