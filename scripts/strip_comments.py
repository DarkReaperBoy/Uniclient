#!/usr/bin/env python3
import os
import re
import sys

DIRECTIVE = re.compile(rb"\Ago:[A-Za-z]")
SLASH = 0x2F
STAR = 0x2A
QUOTE = 0x22
APOS = 0x27
BACKTICK = 0x60
BACKSLASH = 0x5C
NEWLINE = 0x0A
SPACE = 0x20
TAB = 0x09
CR = 0x0D


def lex_quoted(src, i):
    q = src[i]
    n = len(src)
    j = i + 1
    while j < n:
        c = src[j]
        if q != BACKTICK and c == BACKSLASH:
            j += 2
            continue
        if c == q:
            return j + 1
        if q != BACKTICK and c == NEWLINE:
            raise ValueError("newline inside quoted literal")
        j += 1
    raise ValueError("unterminated literal")


def line_directive(body):
    if DIRECTIVE.match(body):
        return True
    if body.startswith(b" +build"):
        return True
    if body.startswith(b"line "):
        return True
    if body.startswith(b"Output:") or body.startswith(b"Unordered output:"):
        return True
    return False


def cgo_preamble(src, end):
    k = end
    n = len(src)
    while k < n and src[k] in (SPACE, TAB, NEWLINE, CR):
        k += 1
    return src[k:k + 10] == b'import "C"'


def transform(src):
    out = bytearray()
    i = 0
    n = len(src)
    dropped = 0
    kept = 0
    while i < n:
        c = src[i]
        if c == QUOTE or c == APOS or c == BACKTICK:
            j = lex_quoted(src, i)
            out += src[i:j]
            i = j
            continue
        if c == SLASH and i + 1 < n and src[i + 1] == SLASH:
            k = src.find(b"\n", i + 2)
            if k < 0:
                k = n
            body = src[i + 2:k]
            if line_directive(body):
                out += src[i:k]
                kept += 1
            else:
                dropped += 1
                while out and out[-1] in (SPACE, TAB):
                    out.pop()
                last = out.rfind(b"\n")
                if bytes(out[last + 1:]).strip() == b"":
                    out = out[:last + 1]
                    if k < n:
                        k += 1
            i = k
            continue
        if c == SLASH and i + 1 < n and src[i + 1] == STAR:
            k = src.find(b"*/", i + 2)
            if k < 0:
                raise ValueError("unterminated block comment")
            if cgo_preamble(src, k + 2):
                out += src[i:k + 2]
                kept += 1
            else:
                dropped += 1
            i = k + 2
            continue
        out.append(c)
        i += 1
    return bytes(out), dropped, kept


def go_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "vendor", "node_modules", "third_party")]
        for name in filenames:
            if name.endswith(".go"):
                yield os.path.join(dirpath, name)


def main():
    check = "--check" in sys.argv[1:]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    total = 0
    changed = 0
    dropped_total = 0
    kept_total = 0
    failures = []
    for path in go_files(root):
        total += 1
        with open(path, "rb") as f:
            src = f.read()
        try:
            dst, dropped, kept = transform(src)
        except ValueError as e:
            failures.append((path, str(e)))
            continue
        kept_total += kept
        if dst != src:
            changed += 1
            dropped_total += dropped
            if check:
                print("WOULD STRIP %s (%d comments)" % (path, dropped))
            else:
                with open(path, "wb") as f:
                    f.write(dst)
    for path, err in failures:
        print("LEXFAIL %s: %s" % (path, err))
    print("go files=%d changed=%d comments_dropped=%d directive_lines_kept=%d"
          % (total, changed, dropped_total, kept_total))
    if failures:
        print("ERROR: %d files failed to lex" % len(failures))
        return 2
    if check and changed:
        print("ERROR: comments present — run: python3 scripts/strip_comments.py")
        return 1
    if check:
        print("comment check clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
