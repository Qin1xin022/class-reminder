# -*- coding: utf-8 -*-
"""Batch migrate hardcoded text colors to theme-aware context getters."""
import re, os

ROOT = r"C:\Users\Administrator\class_reminder\lib"
MAP = {
    "Colors.black45": "context.sub",
    "Colors.black54": "context.sub",
    "Colors.black38": "context.faint",
    "Colors.black26": "context.faint",
    "Colors.black87": "context.text",
}

def find_close(s, i):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "(":
            depth += 1
        elif s[j] == ")":
            depth -= 1
            if depth == 0:
                return j
    return -1

def deconst_spans(s):
    """Return list of (start,end) spans of 'const' keywords to delete."""
    spans = []
    for m in re.finditer(r"const\s+(?=\w+\s*\()", s):
        open_idx = s.index("(", m.end() - 1)
        close_idx = find_close(s, open_idx)
        if close_idx == -1:
            continue
        if "context." in s[m.end():close_idx]:
            spans.append((m.start(), m.end()))
    return spans

def delete_spans(s, spans):
    out, last = [], 0
    for a, b in spans:
        out.append(s[last:a])
        last = b
    out.append(s[last:])
    return "".join(out)

changed = []
for dirpath, _, files in os.walk(ROOT):
    for fn in files:
        if not fn.endswith(".dart") or fn == "tokens.dart":
            continue
        path = os.path.join(dirpath, fn)
        with open(path, encoding="utf-8") as f:
            src = f.read()
        orig = src
        for k, v in MAP.items():
            src = src.replace(k, v)
        if src == orig:
            continue
        src = delete_spans(src, deconst_spans(src))
        if "theme/tokens.dart" not in src:
            rel = "../theme/tokens.dart" if any(
                p in path.replace("\\", "/") for p in ("/screens/", "/widgets/", "/services/", "/state/")
            ) else "theme/tokens.dart"
            lines = src.split("\n")
            last_imp = max(i for i, l in enumerate(lines) if l.startswith("import "))
            lines.insert(last_imp + 1, "import '%s';" % rel)
            src = "\n".join(lines)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(src)
        changed.append(os.path.relpath(path, ROOT))

print("Changed files:")
for c in changed:
    print(" ", c)
