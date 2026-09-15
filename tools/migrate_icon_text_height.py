#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""一次性迁移：把「Row 内图标+文字横排」的 Text 的 height 表达式
统一替换为 AppTokens.heightCalibrated（MiSans 校准值 1.34）。
定位逻辑与 scan_icon_text_align.py 完全一致。"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scan_icon_text_align as S  # noqa: E402

ROOT = S.ROOT
CALIBRATED = 'AppTokens.heightCalibrated'


def find_heights_in_text(tb_clean: str, base: int):
    """在 Text( 块内找 height 表达式（排除 StrutStyle 块内），返回 (start,end)。"""
    # StrutStyle 块范围
    strut_ranges = []
    for m in re.finditer(r'\bStrutStyle\s*\(', tb_clean):
        oi = m.end() - 1
        e = S.match_block(tb_clean, oi)
        if e != -1:
            strut_ranges.append((oi, e))
    res = []
    for m in re.finditer(r'\bheight\s*:\s*[0-9.][0-9.\s/*+-]*', tb_clean):
        seg = m.group(0)
        colon = seg.index(':')
        val = seg[colon + 1:].strip()
        if not val:
            continue
        # 已是校准值（数值形式 1.33~1.35）则跳过
        try:
            if 1.33 <= float(eval(val)) <= 1.35:
                continue
        except Exception:
            pass
        if any(a <= m.start() < b for a, b in strut_ranges):
            continue
        # 只替换数值部分，保留 'height: ' 前缀
        ws = len(val) - len(val.lstrip())
        res.append((base + m.start() + colon + 1 + ws, base + m.end()))
    return res


def main():
    apply = '--apply' in sys.argv
    edits, files_needing_import = {}, set()
    for dirpath, _, files in os.walk(ROOT):
        for fn in sorted(files):
            if not fn.endswith('.dart'):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT)
            src = open(path, encoding='utf-8').read()
            clean = S.blank_out(src)
            containers = S.find_containers(clean)
            managed = []
            for m in S.SELF_MANAGED.finditer(clean):
                oi = m.end() - 1
                e = S.match_block(clean, oi)
                if e != -1:
                    managed.append((oi, e))
            spans = []
            for m in S.TEXT_PAT.finditer(clean):
                topen = m.end() - 1
                tend = S.match_block(clean, topen)
                if tend == -1:
                    continue
                best = None
                for (s, e, name) in containers:
                    if s < topen and tend < e:
                        if best is None or (e - s) < (best[1] - best[0]):
                            best = (s, e, name)
                if best is None or best[2] != 'Row':
                    continue
                s, e, _ = best
                row_body = clean[s:e]
                cm = re.search(r'crossAxisAlignment\s*:\s*CrossAxisAlignment\.(\w+)', row_body)
                if cm and cm.group(1) != 'center':
                    continue
                if any(a < topen and tend < b for a, b in managed):
                    continue
                if not re.search(r'(?<![\w.])Icon\s*\(', row_body):
                    continue
                tb = clean[topen:tend]
                # 只处理已有显式 height 的（本批 77 处均有）
                if not re.search(r'\bheight\s*:', tb):
                    continue
                spans += find_heights_in_text(tb, topen)
            if not spans:
                continue
            edits[rel] = (path, src, spans)
            if 'AppTokens' not in src:
                files_needing_import.add(rel)

    total = sum(len(v[2]) for v in edits.values())
    print(f"共 {len(edits)} 文件 {total} 处待替换；需补 import: {sorted(files_needing_import)}")

    for rel, (path, src, spans) in sorted(edits.items()):
        out = src
        for a, b in sorted(spans, reverse=True):
            out = out[:a] + CALIBRATED + out[b:]
        if rel in files_needing_import:
            depth = rel.count('/')
            rel_imp = '../' * depth + 'core/theme/design_tokens.dart'
            out = out.replace("import 'package:flutter/material.dart';",
                              f"import 'package:flutter/material.dart';\n\nimport '{rel_imp}';", 1)
        if apply:
            open(path, 'w', encoding='utf-8').write(out)
        print(f"  {rel}: {len(spans)} 处")
    print("DRY-RUN" if not apply else "APPLIED")


if __name__ == '__main__':
    main()
