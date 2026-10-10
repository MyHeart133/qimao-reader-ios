# -*- coding: utf-8 -*-
"""改良版 Swift 粗检:先剥离三引号字符串再查括号平衡。可传目录参数。"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else r"D:\Pro\QiMao\QimaoReader-iOS"

def strip_swift(src: str) -> str:
    # 1) 剥离三引号字符串(含插值一起丢)
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    # 2) 状态机剥离普通字符串与注释
    out = []
    i, n = 0, len(src)
    in_str = in_line = in_block = False
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            i += 1
            continue
        if in_block:
            if c == "*" and nxt == "/":
                in_block = False
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
            in_line = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)

for root, dirs, fs in os.walk(ROOT):
    for f in sorted(fs):
        if not f.endswith(".swift"):
            continue
        p = os.path.join(root, f)
        src = open(p, encoding="utf-8").read()
        code = strip_swift(src)
        counts = {c: code.count(c) for c in "{}()[]"}
        balanced = counts["{"] == counts["}"] and counts["("] == counts[")"] and counts["["] == counts["]"]
        print(f"{'OK ' if balanced else '!! '}{f:28s} {{}}={counts['{']}/{counts['}']}  ()={counts['(']}/{counts[')']}  []={counts['[']}/{counts[']']}")
        if not balanced:
            # 打印最后 20 行帮助定位(通常是文件尾部多/少闭合)
            lines = src.splitlines()
            print("   ---- last 25 lines ----")
            for j, l in enumerate(lines[-25:], len(lines) - 24):
                print(f"   {j:4d}| {l}")
