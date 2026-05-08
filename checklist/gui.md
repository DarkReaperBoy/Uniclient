# Audit: §1-§4 Layout & Navigation

## §1 — Window Layout & Column Structure

## §2 — Chat List Sidebar

## §3 — Hamburger Menu

## §4 — Chat Header / Top Bar

# Audit: §5-§7 Messages & Compose

## §5 — Message List & Bubbles


## §6 — Media Message Types


## §7 — Compose Area

# Audit: §8-§13 Panels & Overlays

## §9 — Context Menus & Actions


## §11 — Authentication / Login Flow

## §12 — Calls UI

## §13 — Mobile / Web Compatibility
# Audit: §14-§19 Settings

---

---

---

---

---

## Cross-Cutting Issues
# Audit: §20-§25 Media Viewer, Groups, Forum, Scheduled, Shortcuts, Theming

## §20 — Media Viewer / Lightbox


## §22 — Forum Topics UI


## §24 — Keyboard Shortcuts


# Audit: &sect;26-&sect;36 Admin, Export, Contacts, Calls, States

## &sect;26 -- Admin Tools

## &sect;27 -- Passcode Lock Screen

## &sect;28 -- Two-Factor Authentication Setup

## &sect;29 -- Chat Export

## &sect;30 -- Bot Interactions

## &sect;31 -- Saved Messages

## &sect;32 -- Stories

## &sect;33 -- Contacts Screen

## &sect;35 -- Empty, Error & Loading States

## &sect;36 -- Common Dialog & Modal Patterns
# Audit: §37-§49 Popups, Formatting & Interactions


## §38 — User Profile Popup

## §39 — Photo & Avatar Cropping Dialog

## §40 — Send Files Dialog

## §41 — Message Formatting Toolbar


## §42 — Reactions Detail Popup

## §43 — Read Receipts Detail



## §46 — Link Preview in Compose

## §47 — Restricted Permissions UI




# Audit: §50-§57 AyuGram Features & Appendices

## §51 — Ghost Mode


## §53 — Forward Enhancements

## §54 — AyuGram UI Customization


## §56 — Appendix A: Resolved Style Constants


## §57 — Appendix B: Dark Theme Color Palette

## General / Cross-Cutting Issues

- [ ] Ghost mode lock mechanism uses Shift+click on desktop and long-press on mobile (matching spec §51.2.1). Verified correct in `_LockableToggleRow`
- [ ] The collapsible toggle in `ayu_section_builder.dart` does not implement a master toggle that sets all sub-checkboxes — it only shows/hides nested checkboxes. Spec §51.2.1 says the master toggle calls `setGhostModeEnabled(bool)` which flips all five core toggles
- [ ] No `-ghost` command-line flag support for launch-time ghost mode activation
