# GUI Build Process — Mandatory Steps Before Writing Any Widget Code

**This document exists because we built the entire left panel wrong on the first attempt.** We invented a "navigation rail with account icons" layout instead of Telegram Desktop's actual hamburger-menu + filters-sidebar design. The root cause: jumping to code after skimming the spec instead of deeply studying it first.

## The Problem Pattern

When building UI that must match an existing application 1:1, there's a strong temptation to:
1. Glance at the spec section titles
2. Form a mental model based on what you *think* it looks like
3. Start coding immediately from that mental model
4. Discover 500 lines later that the mental model was wrong

This wastes an entire session. The code must be deleted and restarted.

## Mandatory Process — Do NOT Skip Steps

### Phase 1: Study (NO code allowed)

For **every screen or component** you're about to build:

1. **Read the FULL spec section** — not just headers, not just the first paragraph. Read every subsection, every dimension, every state. For the left panel, that means ALL of §1 (layout), §2 (chat list), §3 (hamburger menu), and §18 (folders).

2. **Write a component breakdown doc** — Before touching any `.dart` file, write a markdown file (`research/gui_component_plan_{name}.md`) that lists:
   - Every widget you'll create, with its exact purpose
   - Parent-child nesting (what contains what)
   - Exact dimensions from the spec (px values, ratios)
   - State each widget needs (what data drives it)
   - How it differs from your first instinct (this is the critical one)

3. **Cross-reference related sections** — UI components reference each other. The filters sidebar (§1) connects to folders (§18) connects to the hamburger menu (§3) connects to the chat list (§2). Read ALL related sections, not just the one you're building.

4. **Identify UniClient adaptations explicitly** — Where we deviate from Telegram Desktop (multi-platform accounts, unified chat list), write down *exactly* how we adapt, referencing the original behavior. "Telegram does X, we do Y because Z."

### Phase 2: Review the plan

5. **Re-read your plan against the spec one more time** — Specifically look for things you assumed vs. things the spec says. If you wrote "left rail with icons" but the spec says "hamburger menu with expandable account list", that's a miss.

### Phase 3: Build one widget at a time

6. **Build the smallest self-contained widget first** — Don't write 10 files in parallel. Write one widget, verify it matches the spec, then move to the next.

7. **Screenshot after each widget** — Build, launch, screenshot, compare against the spec description. Catch mismatches early.

## Checklist Before Starting Any UI Component

- [ ] Read ALL related spec sections completely (not skimming)
- [ ] Wrote component breakdown with exact dimensions
- [ ] Identified where my assumption differs from spec
- [ ] Cross-referenced related sections
- [ ] Know exactly what state/data each widget needs
- [ ] Plan reviewed against spec one final time

## Common Traps

| Trap | Example | Fix |
|------|---------|-----|
| Inventing layout from generic UX knowledge | "Chat apps have a left rail" | Read the spec — Telegram uses hamburger menu + optional filters sidebar |
| Assuming mobile patterns on desktop | Bottom nav bar, tab bar | Telegram Desktop uses column layout with hamburger drawer |
| Building all widgets in parallel | Writing 10 files then discovering the foundation was wrong | Build one widget, verify, then next |
| Skipping the "how does this actually work" question | "Account switching must be in the rail" | Read §3 — it's in the hamburger menu's expandable account section |
| Confusing folder tabs with platform tabs | Using the filters sidebar for platform icons | Filters sidebar = chat folders. Platform filtering is a UniClient-specific addition that needs its own design decision |
