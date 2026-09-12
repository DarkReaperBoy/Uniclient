package gui

import (
	"testing"

	"uniclient/engine"
)

// Bot commands menu (AyuGram parity slice 76): the a.wid.composer's "/" button
// lists the chat's bot commands (engine.GetChatBotCommands); tapping one
// inserts it. Pure derivations locked here.

func TestBotCmdTitle(t *testing.T) {
	c := engine.BotCommandInfo{Command: "start", Description: "Start the bot"}
	if got := botCmdTitle(c); got != "/start" {
		t.Fatalf("title = %q, want /start", got)
	}
	// Commands sometimes come with the slash already — never doubled.
	c.Command = "/help"
	if got := botCmdTitle(c); got != "/help" {
		t.Fatalf("title = %q, want /help", got)
	}
}

func TestBotCmdSub(t *testing.T) {
	c := engine.BotCommandInfo{Command: "start", Description: "Start the bot", BotName: "Helper"}
	if got := botCmdSub(c); got != "Helper — Start the bot" {
		t.Fatalf("sub = %q", got)
	}
	c.BotName = ""
	if got := botCmdSub(c); got != "Start the bot" {
		t.Fatalf("sub without bot name = %q", got)
	}
	c.Description = ""
	if got := botCmdSub(c); got != "" {
		t.Fatalf("empty description should hide the sub line, got %q", got)
	}
}

func TestBotCmdPanelNeeded(t *testing.T) {
	// The "/" button only appears for chats that actually have commands —
	// an empty panel would be a dead button (AGENTS.md §1.10).
	if botCmdPanelNeeded(nil) {
		t.Fatal("no commands: no button")
	}
	cmds := []engine.BotCommandInfo{{Command: "start"}}
	if !botCmdPanelNeeded(cmds) {
		t.Fatal("commands present: button must show")
	}
}

func TestBotCmdInsertText(t *testing.T) {
	if got := botCmdInsertText("", "start"); got != "/start " {
		t.Fatalf("empty a.wid.composer: %q", got)
	}
	if got := botCmdInsertText("hello ", "help"); got != "hello /help " {
		t.Fatalf("append: %q", got)
	}
}
