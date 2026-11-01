package cores

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

func TestLockOrderIsAcyclic(t *testing.T) {
	type edge struct{ from, to string }
	edges := map[edge]map[string]bool{}

	files, err := filepath.Glob("../*/[a-z]*.go")
	if err != nil {
		t.Fatalf("glob: %v", err)
	}
	for _, path := range files {
		if strings.HasSuffix(path, "_test.go") {
			continue
		}
		data, err := readFileLines(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		curFn, held := "", map[string]bool{}
		for _, l := range data {
			if label, ok := funcLabel(l); ok {
				curFn, held = label, map[string]bool{}
				continue
			}
			if curFn == "" {
				continue
			}
			code := l
			if i := strings.Index(code, "//"); i >= 0 {
				code = code[:i]
			}
			isDefer := strings.HasPrefix(strings.TrimLeft(l, " \t"), "defer ")
			for _, lk := range lockCalls(code, "Lock", "RLock") {
				for h := range held {
					if h != lk {
						k := edge{h, lk}
						if edges[k] == nil {
							edges[k] = map[string]bool{}
						}
						edges[k][curFn] = true
					}
				}
				delete(held, lk)
				held[lk] = true
			}
			if !isDefer {
				for _, lk := range lockCalls(code, "Unlock", "RUnlock") {
					delete(held, lk)
				}
			}
		}
	}

	t.Logf("scanned %d files, %d ordered edges", len(files), len(edges))
	var cycles []string
	seen := map[string]bool{}
	for e := range edges {
		if e.from == e.to {
			continue
		}
		back := edge{e.to, e.from}
		if _, ok := edges[back]; !ok {
			continue
		}
		key := e.from + "|" + e.to
		if e.to+"|"+e.from < key {
			key = e.to + "|" + e.from
		}
		if seen[key] {
			continue
		}
		seen[key] = true
		cycles = append(cycles, "lock-order cycle: "+e.from+" <-> "+e.to+
			"\n   "+e.from+" -> "+e.to+": "+sortedJoin(edges[e])+
			"\n   "+e.to+" -> "+e.from+": "+sortedJoin(edges[back]))
	}
	sort.Strings(cycles)
	if len(cycles) > 0 {
		t.Errorf("opposite lock orders = two-party deadlock (B-41):\n%s",
			strings.Join(cycles, "\n"))
	}
}

func readFileLines(path string) ([]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return strings.Split(string(b), "\n"), nil
}

func sortedJoin(set map[string]bool) string {
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	if len(out) > 3 {
		out = append(out[:3], "…")
	}
	return strings.Join(out, "; ")
}

func funcLabel(line string) (string, bool) {
	if !strings.HasPrefix(line, "func ") {
		return "", false
	}
	rest := strings.TrimPrefix(line, "func ")
	recv, name := "", ""
	if strings.HasPrefix(rest, "(") {
		end := strings.Index(rest, ")")
		if end < 0 {
			return "", false
		}
		recv = strings.Fields(rest[1:end])[0]
		rest = strings.TrimSpace(rest[end+1:])
	}
	sp := strings.IndexAny(rest, "( ")
	if sp < 0 {
		return "", false
	}
	name = rest[:sp]
	if strings.Contains(name, ".") {
		return "", false
	}
	return name + "@" + recv, true
}

func lockCalls(code string, suffixes ...string) []string {
	var out []string
	for i := 0; i < len(code); i++ {
		if code[i] != '.' {
			continue
		}
		for _, s := range suffixes {
			if strings.HasPrefix(code[i+1:], s+"(") {
				end := strings.IndexAny(code[i+1+len(s)+1:], ")")
				if end != 0 {
					continue
				}
				j := i
				for j > 0 && (isIdent(code[j-1])) {
					j--
				}
				out = append(out, code[j:i])
				break
			}
		}
	}
	return out
}

func isIdent(c byte) bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}
