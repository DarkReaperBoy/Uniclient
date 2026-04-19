# GUI Checklist

**BEFORE STARTING ANY WORK: Read `CLAUDE.md` and obey ALL its rules.**

## MANDATORY: Research-first, AyuGram Desktop 1:1

**Every UI feature MUST match AyuGram Desktop exactly.** Before implementing anything:
1. Check `research/telegram_desktop_ui.md` for the relevant section
2. If info is missing or insufficient, research AyuGram Desktop source (https://github.com/AyuGram/AyuGramDesktop) and ADD findings to `research/telegram_desktop_ui.md` BEFORE writing any code
3. Never guess how a feature should look or behave — find the real implementation

## MANDATORY: Self-test with automated interaction

**After implementing any change, you MUST test it yourself using the automated interaction pipeline.** See `CLAUDE.md` § GUI Automation Toolkit for full command reference (`flutter_inspect.sh`, `flutter_interact.sh`, `flutter_auth.sh`).

**Workflow:** screenshot → identify coordinates → interact → screenshot → verify result. Do NOT mark anything as done until visually confirmed.

## Bugs (fix first, verify with automated interaction)




## TODO (features not yet implemented)

### Folder management

### Chat row enhancements

### Chat view / DM

### Profile/Info panel

### Search

### Other features

## Needs visual review (implemented but not screenshot-verified against AyuGram)

