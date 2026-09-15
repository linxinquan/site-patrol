#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
图标 + 文字横排对齐回归检查。

背景：Row 的 crossAxisAlignment: center 居中的是「子组件占的盒子」，不是
盒子里的墨迹。Text 的盒子 = 字号 × 行高，MiSans 的行高由字体度量决定
（hhea ascent 1.044 / descent 0.282，严重不对称），字形的墨迹中心并不在
盒子的几何中心上，而是偏上 —— 所以光写 center 不够，必须锁 height。

关键（易错）：TextStyle.height 是「对字体度量行高的等比缩放」，height 越小
墨迹越偏上、越大越偏下。MiSans 墨迹真正居中对应的 height ≈ 1.34，
而不是 1.0（height: 1 反而让字形偏上约 0.1 字号，14px 字约偏 1.4px）。

规则：凡是 Row 内裸 Icon 与 Text 横排，Text 的 TextStyle 必须写
height: AppTokens.heightCalibrated（= 1.34）。

用法：
    python3 tools/scan_icon_text_align.py            # 只报告
    python3 tools/scan_icon_text_align.py --strict    # 有命中则退出码 1（CI 用）

已排除（这些组件自管布局，无需外部锁行高）：
    ElevatedButton.icon / FilledButton / OutlinedButton / TextButton /
    IconButton / Chip / ListTile / AppButton / Tab / MenuItemButton / DropdownMenuItem
"""
import os
import re
import sys

ROOT = os.path.expanduser("~/Desktop/site-patrol/lib")
STRICT = "--strict" in sys.argv

# MiSans 墨迹居中的校准行高（见 AppTokens.heightCalibrated），容差 ±0.01
CALIBRATED = 1.34
CALIBRATED_TOL = 0.01


def blank_out(src: str) -> str:
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                if src[k] != '\n':
                    out[k] = ' '
            i = j
            continue
        if c in ('"', "'"):
            quote = c
            if src[i:i + 3] == quote * 3:
                j = src.find(quote * 3, i + 3)
                j = n if j == -1 else j + 3
                for k in range(i, j):
                    if src[k] != '\n':
                        out[k] = ' '
                i = j
                continue
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == quote:
                    j += 1
                    break
                if src[j] == '\n':
                    break
                j += 1
            for k in range(i, j):
                if src[k] != '\n':
                    out[k] = ' '
            i = j
            continue
        i += 1
    return ''.join(out)


def match_block(src: str, open_idx: int) -> int:
    pairs = {'(': ')', '[': ']', '{': '}'}
    stack = [src[open_idx]]
    i = open_idx + 1
    n = len(src)
    while i < n and stack:
        c = src[i]
        if c in pairs:
            stack.append(c)
        elif c in (')', ']', '}'):
            if pairs.get(stack[-1]) != c:
                return -1
            stack.pop()
        i += 1
    return i - 1 if not stack else -1


def find_containers(clean: str):
    """返回所有 Row(/Column(/Wrap(/Stack( 的 (start, end, name)。"""
    res = []
    for m in re.finditer(r'\b(Row|Column|Wrap|Stack)\s*\(', clean):
        open_idx = m.end() - 1
        end = match_block(clean, open_idx)
        if end == -1:
            continue
        res.append((open_idx, end, m.group(1)))
    return res


TEXT_PAT = re.compile(r'(?<![\w.])Text\s*\(')
# 自管布局、无需外部锁 height 的组件
SELF_MANAGED = re.compile(
    r'(ElevatedButton|FilledButton|OutlinedButton|TextButton|IconButton|Chip|'
    r'ListTile|AppButton|NavigationDestination|Tab|MenuItemButton|DropdownMenuItem)\s*(\.icon)?\s*\(')


def main():
    findings = {}
    for dirpath, _, files in os.walk(ROOT):
        for fn in files:
            if not fn.endswith('.dart'):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT)
            with open(path, encoding='utf-8') as f:
                src = f.read()
            clean = blank_out(src)
            containers = find_containers(clean)
            # 自管布局组件的范围
            managed = []
            for m in SELF_MANAGED.finditer(clean):
                oi = m.end() - 1
                e = match_block(clean, oi)
                if e != -1:
                    managed.append((oi, e))

            for m in TEXT_PAT.finditer(clean):
                topen = m.end() - 1
                tend = match_block(clean, topen)
                if tend == -1:
                    continue
                # 最小包含容器
                best = None
                for (s, e, name) in containers:
                    if s < topen and tend < e:
                        if best is None or (e - s) < (best[1] - best[0]):
                            best = (s, e, name)
                if best is None or best[2] != 'Row':
                    continue
                s, e, _ = best
                row_body = clean[s:e]
                # Row 必须居中（显式 center 或省略）
                cm = re.search(r'crossAxisAlignment\s*:\s*CrossAxisAlignment\.(\w+)', row_body)
                if cm and cm.group(1) != 'center':
                    continue
                # 排除位于自管布局组件内部的 Text
                if any(a < topen and tend < b for a, b in managed):
                    continue
                # Row 内必须有「直接子级」的裸 Icon(...)：
                # 嵌套子 Row 里的图标与本级文字不同层，不构成横排对齐关系
                nested = []
                for nm in re.finditer(r'(?<![\w.])Row\s*\(', clean[s + 1:e]):
                    oi = s + 1 + nm.end() - 1
                    ne = match_block(clean, oi)
                    if ne != -1:
                        nested.append((oi, ne))
                has_direct_icon = False
                for im in re.finditer(r'(?<![\w.])Icon\s*\(', row_body):
                    ipos = s + im.start()
                    if not any(a < ipos < b for a, b in nested):
                        has_direct_icon = True
                        break
                if not has_direct_icon:
                    continue
                # 该 Text 的 height 是否为校准值
                tb = clean[topen:tend]
                hm = re.search(r'\bheight\s*:\s*([^,\n)]+)', tb)
                hval = hm.group(1).strip() if hm else None
                if hval is not None:
                    if 'heightCalibrated' in hval:
                        continue
                    try:
                        v = float(hval)
                        if abs(v - CALIBRATED) <= CALIBRATED_TOL:
                            continue
                    except ValueError:
                        # 表达式（如 22 / 14）：算出数值再判
                        try:
                            v = float(eval(hval))
                            if abs(v - CALIBRATED) <= CALIBRATED_TOL:
                                continue
                        except Exception:
                            pass
                line = clean[:topen].count('\n') + 1
                # 原文片段
                seg = src[clean.rfind('\n', 0, s) + 1:tend + 1]
                preview = ' '.join(seg.split())
                findings.setdefault(rel, []).append(
                    (line, f"[height={hval}] {preview[:96]}"))

    total = sum(len(v) for v in findings.values())
    if total == 0:
        print(f"通过：所有 Row 内横排文字均已使用校准行高 {CALIBRATED}。")
        return 0
    print(f"=== Row 内裸 Icon + Text，但 Text 的 height 未取校准值 "
          f"{CALIBRATED}：{total} 处 ===\n")
    for f, hits in sorted(findings.items(), key=lambda x: -len(x[1])):
        print(f"### {f} ({len(hits)})")
        for ln, p in hits:
            print(f"  L{ln}: {p}")
        print()
    print(f"修法：把该 Text 的 TextStyle 的 height 改为 "
          f"AppTokens.heightCalibrated（= {CALIBRATED}）。")
    return 1 if STRICT else 0


if __name__ == '__main__':
    sys.exit(main())
