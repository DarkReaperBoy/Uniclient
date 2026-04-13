package utils

import (
	"strings"
	"testing"
)

// helper: generate a string of n words
func nWords(n int, word string) string {
	words := make([]string, n)
	for i := range words {
		words[i] = word
	}
	return strings.Join(words, " ")
}

func TestSplitMessageEmpty(t *testing.T) {
	result := SplitMessage("", 4000)
	if len(result) != 1 || result[0] != "" {
		t.Fatalf("expected single empty chunk, got %v", result)
	}
}

func TestSplitMessageUnderLimit(t *testing.T) {
	text := nWords(100, "hello")
	result := SplitMessage(text, 4000)
	if len(result) != 1 {
		t.Fatalf("expected 1 chunk, got %d", len(result))
	}
	if result[0] != text {
		t.Fatal("chunk does not match original text")
	}
}

func TestSplitMessageExactly4000(t *testing.T) {
	text := nWords(4000, "word")
	result := SplitMessage(text, 4000)
	if len(result) != 1 {
		t.Fatalf("expected 1 chunk for exactly 4000 words, got %d", len(result))
	}
	if result[0] != text {
		t.Fatal("chunk does not match original text")
	}
}

func TestSplitMessage4001(t *testing.T) {
	text := nWords(4001, "word")
	result := SplitMessage(text, 4000)
	if len(result) != 2 {
		t.Fatalf("expected 2 chunks for 4001 words, got %d", len(result))
	}
	if wc := len(strings.Fields(result[0])); wc != 4000 {
		t.Fatalf("first chunk should have 4000 words, got %d", wc)
	}
	if wc := len(strings.Fields(result[1])); wc != 1 {
		t.Fatalf("second chunk should have 1 word, got %d", wc)
	}
}

func TestSplitMessage12000(t *testing.T) {
	text := nWords(12000, "word")
	result := SplitMessage(text, 4000)
	if len(result) != 3 {
		t.Fatalf("expected 3 chunks for 12000 words, got %d", len(result))
	}
	for i, chunk := range result {
		if wc := len(strings.Fields(chunk)); wc != 4000 {
			t.Fatalf("chunk %d should have 4000 words, got %d", i, wc)
		}
	}
}

func TestSplitMessageUnicode(t *testing.T) {
	// CJK characters separated by spaces
	cjk := "中文 日本語 한국어 中文 日本語"
	result := SplitMessage(cjk, 3)
	if len(result) != 2 {
		t.Fatalf("expected 2 chunks for CJK, got %d", len(result))
	}

	// Arabic text
	arabic := "مرحبا بالعالم العربي اليوم"
	result = SplitMessage(arabic, 2)
	if len(result) != 2 {
		t.Fatalf("expected 2 chunks for Arabic, got %d", len(result))
	}

	// Emoji words
	emoji := "😀 🎉 🚀 💡 🌍"
	result = SplitMessage(emoji, 3)
	if len(result) != 2 {
		t.Fatalf("expected 2 chunks for emoji, got %d", len(result))
	}
}

func TestSplitMessageSingleLongWord(t *testing.T) {
	long := strings.Repeat("a", 50000)
	result := SplitMessage(long, 4000)
	if len(result) != 1 {
		t.Fatalf("expected 1 chunk for single long word, got %d", len(result))
	}
	if result[0] != long {
		t.Fatal("chunk does not match original long word")
	}
}

func TestSplitMessageRejoin(t *testing.T) {
	text := nWords(10001, "test")
	result := SplitMessage(text, 4000)
	rejoined := strings.Join(result, " ")
	if rejoined != text {
		t.Fatal("rejoined chunks do not match original text")
	}
}

func TestIsMultipart(t *testing.T) {
	if IsMultipart([]string{"one"}) {
		t.Fatal("single element should not be multipart")
	}
	if !IsMultipart([]string{"one", "two"}) {
		t.Fatal("two elements should be multipart")
	}
	if IsMultipart(nil) {
		t.Fatal("nil should not be multipart")
	}
}
