# edit_mark_box — Critical behavior mismatches with AyuGram reference

## Summary
The Dart implementation has fundamentally wrong button behavior and is missing critical features compared to AyuGram. The Reset button should only modify the text field, not save/close. A Cancel button is needed. Input validation is missing.

---

## Findings

- [ ] **[CRITICAL]** Reset button saves and closes immediately instead of just resetting text
  - `edit_mark_box.dart:86-89` (Reset button calls `onSave(widget.defaultValue)` + `Navigator.pop()`)
  - ← `edit_mark_box.cpp:44-48` (Reset button ONLY calls `_text->setText(_defaultValue)`, no save/close)
  - **Issue:** In AyuGram, clicking Reset just sets the text field to default; user must then click Save to persist or Cancel to discard. In Dart, clicking Reset immediately saves the default value and closes the dialog, removing the opportunity to edit or cancel.

- [ ] **[CRITICAL]** Missing Cancel button
  - `edit_mark_box.dart:82-96` (only Reset and Save buttons provided)
  - ← `edit_mark_box.cpp:44-59` (has Reset, Save, AND Cancel buttons)
  - **Issue:** AyuGram provides three buttons: Reset (left), Save (right), Cancel (right). Dart only has Reset and Save. There's no way to close without saving or resetting.

- [ ] **[CRITICAL]** No input validation — allows saving empty text
  - `edit_mark_box.dart:56-58` (`_save()` calls callback with `_controller.text` without any validation)
  - ← `edit_mark_box.cpp:73-80` (`submit()` checks `if (_text->getLastText().trimmed().isEmpty())`, shows error, only calls `save()` if not empty)
  - **Issue:** AyuGram validates that the text is not empty and shows an error state if the user tries to submit empty text. Dart allows any value including empty strings.

- [ ] **[MAJOR]** Missing Enter key validation flow
  - `edit_mark_box.dart:66-68` (TelegramBox onConfirm calls `_save()` directly, which has no validation)
  - ← `edit_mark_box.cpp:61-66` (submits signal calls `submit()`, which validates before calling `save()`)
  - **Issue:** In AyuGram, pressing Enter triggers `submit()` which validates first. In Dart, pressing Enter triggers `onConfirm` which directly saves without validation. If user presses Enter with empty text in Dart, it will save without error feedback.

---

## Impact
This dialog is fundamentally non-functional as implemented:
1. Users cannot cancel (would lose their edits)
2. Users cannot intentionally reset and then edit (Reset immediately commits)
3. Empty input is accepted without user feedback
4. The three-button UX pattern from the spec is not implemented
