# -*- coding: utf-8 -*-
"""Migrate hardcoded brand blue + light gray dividers to theme-aware colors."""
import os, re

ROOT = r"C:\Users\Administrator\class_reminder\lib"
TARGETS = os.path.join(ROOT, "screens"), os.path.join(ROOT, "widgets")

RULES = [
    ("const Color(0xFF4C6FFF)", "Theme.of(context).colorScheme.primary"),
    ("Color(0xFF4C6FFF)", "Theme.of(context).colorScheme.primary"),
    ("const Color(0xFFF1F3F5)", "context.divider"),
    ("Color(0xFFF1F3F5)", "context.divider"),
    ("Color(0xFFEDEFF5)", "context.divider"),
]

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

def deconst(s):
    spans = []
    for m in re.finditer(r"const\s+(?=\w+\s*\()", s):
        open_idx = s.index("(", m.end() - 1)
        close_idx = find_close(s, open_idx)
        if close_idx == -1:
            continue
        if "context." in s[m.end():close_idx]:
            spans.append((m.start(), m.end()))
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
        rel = path.replace("\\", "/")
        if "/screens/" not in rel and "/widgets/" not in rel:
            continue
        lines = open(path, encoding="utf-8").read().split("\n")
        changed_flag = False
        for i, l in enumerate(lines):
            if "kBrandFallback" in l or "_Meta(" in l or "kCourseColors" in l:
                continue
            for old, new in RULES:
                if old in l:
                    l = l.replace(old, new)
                    changed_flag = True
            lines[i] = l
        if not changed_flag:
            continue
        src = deconst("\n".join(lines))
        if "theme/tokens.dart" not in src and "context.divider" in src:
            lines = src.split("\n")
            last_imp = max(i for i, l in enumerate(lines) if l.startswith("import "))
            lines.insert(last_imp + 1, "import '../theme/tokens.dart';")
            src = "\n".join(lines)
        open(path, "w", encoding="utf-8", newline="\n").write(src)
        changed.append(os.path.relpath(path, ROOT))

for c in changed:
    print(" ", c)
print("total:", len(changed))
