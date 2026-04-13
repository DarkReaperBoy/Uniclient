package utils

import "strings"

// SplitMessage splits text into chunks of at most maxWords words,
// preserving word boundaries. Words are defined by strings.Fields.
// If the text has maxWords or fewer words, a single-element slice is returned.
func SplitMessage(text string, maxWords int) []string {
	words := strings.Fields(text)
	if len(words) == 0 {
		return []string{""}
	}
	if maxWords <= 0 {
		maxWords = 1
	}

	var chunks []string
	for i := 0; i < len(words); i += maxWords {
		end := i + maxWords
		if end > len(words) {
			end = len(words)
		}
		chunks = append(chunks, strings.Join(words[i:end], " "))
	}
	return chunks
}

// IsMultipart returns true if messages contains more than one part.
func IsMultipart(messages []string) bool {
	return len(messages) > 1
}
