# -*- coding: utf-8 -*-
"""核对工作区 vs GitHub 差异，确保迁移完整。运行需在能访问中文路径的环境（cmd）。"""
import os, sys

WS = r"F:\建筑验收工具\site-patrol"
GH = r"F:\GitHub\site-patrol"

SKIP_DIRS = {'.git', '.dart_tool', 'build', '.codebuddy', '__pycache__',
             'node_modules', '.gradle', '.kotlin', '.idea', 'android/.gradle',
             'android/.kotlin', '.widget_preview'}

def walk(root):
    out = {}
    for dp, dns, fns in os.walk(root):
        rel = os.path.relpath(dp, root).replace(os.sep, '/')
        dns[:] = [d for d in dns if rel + ('/' if rel != '.' else '') + d not in SKIP_DIRS
                  and d not in SKIP_DIRS]
        for f in fns:
            full = os.path.join(dp, f)
            key = os.path.relpath(full, root).replace(os.sep, '/')
            try:
                out[key] = os.path.getsize(full)
            except OSError:
                out[key] = -1
    return out

def main():
    if not os.path.exists(WS):
        print("ERROR: workspace missing", WS); sys.exit(1)
    if not os.path.exists(GH):
        print("INFO: GitHub already deleted, nothing to do"); sys.exit(0)
    w = walk(WS)
    g = walk(GH)
    only_gh = sorted(set(g) - set(w))
    only_ws = sorted(set(w) - set(g))
    print("== 工作区文件数:", len(w), " GitHub文件数:", len(g))
    print()
    print("== 【GitHub有但工作区没有】(共%d个) ==" % len(only_gh))
    for k in only_gh:
        print("  ", k, f"({g[k]}B)")
    print()
    print("== 【工作区有但GitHub没有】(共%d个, 仅提示) ==" % len(only_ws))
    for k in only_ws[:20]:
        print("  ", k)

if __name__ == "__main__":
    main()
