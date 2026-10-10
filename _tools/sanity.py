# -*- coding: utf-8 -*-
"""Swift 源码粗检:括号/引号平衡 + 文件树清单(在无 swiftc 环境下做最低限度 sanity)。"""
import os

ROOT = r"D:\Pro\QiMao\QimaoReader-iOS"
files = []
for root, dirs, fs in os.walk(ROOT):
    for f in fs:
        p = os.path.join(root, f)
        rel = os.path.relpath(p, ROOT)
        files.append((rel, os.path.getsize(p)))

print("=== 项目文件树 ===")
for rel, size in sorted(files):
    print(f"  {rel:70s} {size:>8}")

print()
print("=== Swift 括号平衡粗检 ===")
ok = True
for rel, _ in sorted(files):
    if not rel.endswith(".swift"):
        continue
    src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    # 去掉字符串字面量做粗检(处理 \" 转义)
    out = []
    i, n = 0, len(src)
    in_str = in_line_comment = in_block_comment = False
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
                out.append(c)
            i += 1
            continue
        if in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        out.append(c)
        i += 1

    code = "".join(out)
    counts = {c: code.count(c) for c in "{}()[]"}
    balanced = counts["{"] == counts["}"] and counts["("] == counts[")"] and counts["["] == counts["]"]
    flag = "OK " if balanced else "!! "
    if not balanced:
        ok = False
    print(f"  {flag}{rel:50s} {{}}={counts['{']}/{counts['}']}  ()={counts['(']}/{counts[')']}  []={counts['[']}/{counts[']']}")

print()
print("RESULT:", "ALL BALANCED" if ok else "HAS IMBALANCE — check the ! rows")
