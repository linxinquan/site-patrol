# -*- coding: utf-8 -*-
"""
生成 docs/index.html —— 蓝图落地 · 文档中心（离线单文件文档浏览器）

用法：
    python flutter_app/docs/_build_docs_browser.py      # 仓库根目录下
    python docs/_build_docs_browser.py                  # 或先 cd flutter_app

扫描范围（目录驱动，**文档有增删改后重跑一次即可，无需改本脚本**）：
    flutter_app/*.md              → 现行文档，按 ROOT_GROUPS 归组
    flutter_app/docs/<子目录>/*.md → 每个子目录自动成为一个分类 + 一个筛选 chip
    flutter_app/docs/*.md         → 「文档 · 未归类」
    flutter_app/server/*.md       → 现行文档
  · docs/archive/ 例外：按文件名前缀细分成 6 组（见 ARCHIVE_GROUPS）
  · docs/ 下新增文件夹（如 todo/）会自动出现，分类名默认取目录名；
    想换中文名就登记到 DOC_FOLDERS
  · 跑完会打印分类统计、无 H1 标题的文档、以及落到「其他」组的漏登记文件
"""
import base64
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # flutter_app/

# ---------------------------------------------------------------- 分类规则
# 设计原则（2026-09-21 重构）：**目录驱动，新增文件夹无需改脚本**。
#   · flutter_app 根目录的 *.md          → 现行文档，按 ROOT_GROUPS 归组
#   · docs/<任意子目录>/*.md             → 该子目录自成一个分类 + 一个筛选 chip
#   · 未在 DOC_FOLDERS 登记的子目录       → 分类名/标签直接用目录名兜底
#   · docs/archive/                      → 例外：按文件名前缀细分成 6 组
#
# (分组名, scope, 文件名集合)
ROOT_GROUPS = [
    ("用户手册", "current", ["USER_WORKFLOW.md"]),
    ("总览", "current", ["README.md"]),
    ("现状与事实源", "current", ["FEATURE_INVENTORY.md"]),
    ("后端与配套服务", "current", [
        "AI_VISION_INTEGRATION.md",
        "DXF_CALIBRATION_README.md",
    ]),
    ("设计规范", "current", ["DESIGN_TOKENS.md", "UI_PREFERENCES.md"]),
    ("功能实现", "current", [
        "ROOM_MEASURE_IMPL.md",
        "ROOM_MEASURE_IMPL_DETAIL.md",
        "CAD_OCF_INTEGRATION.md",
        "CAD_MIGRATION_BACKUP.md",
        "ANDROID_AR_RESEARCH.md",
    ]),
]

# docs/ 子目录 → (分类名, 筛选标签)
# 【筛选键 = 目录名本身】，所以没登记的子目录会自动兜底成 (目录名, 目录名)
DOC_FOLDERS = {
    "specs": ("流程规格", "规格"),
    "todo": ("待办 · 待落地", "待办"),
}
# docs/ 顶层散放的 md（不属于任何子目录）
DOCS_MISC = ("文档 · 未归类", "散篇")
MISC_SCOPE = "docsmisc"
# 归档目录例外处理（按前缀细分组）
ARCHIVE_DIR = "archive"
ARCHIVE_GROUPS = [
    ("归档 · 开发日志", ("DEVELOPMENT_LOG_", "ARCHIVE_")),
    ("归档 · 巡场", ("PATROL_",)),
    ("归档 · 量尺与 AR", ("MEASURE_", "AR_", "TEST_PLAN_MEASURE", "PHOTOCALIB_")),
    ("归档 · 拍照验收与报告", ("CAPTURE_", "WIDGET_TEST_ROOM", "VIDEO_PLAN")),
    ("归档 · 需求与汇报", ("REQUIREMENTS_", "REPLY_TO_", "PPT_OUTLINE")),
    ("归档 · 任务交接与上下文", ("PASTE_", "CODEBUDDY_", "SESSION_CONTEXT", "TASK_DASHBOARD")),
]

# 筛选 chip 的展示顺序（未登记的目录落在 MISC 与 archive 之间）
SCOPE_PREF = ["current", "specs", "todo", MISC_SCOPE, ARCHIVE_DIR]


def doc_folder(rel):
    """docs/xxx/yyy.md → 'xxx'；docs/yyy.md 或根目录文件 → None"""
    parts = rel.split("/")
    if len(parts) >= 3 and parts[0] == "docs":
        return parts[1]
    return None


def scope_of(rel):
    if rel.startswith("docs/"):
        return doc_folder(rel) or MISC_SCOPE
    return "current"


def folder_meta(folder):
    """子目录 → (分类名, 筛选标签)，未登记则用目录名兜底"""
    return DOC_FOLDERS.get(folder, (folder, folder))


def scope_label(scope):
    if scope == "current":
        return "现行"
    if scope == MISC_SCOPE:
        return DOCS_MISC[1]
    if scope == ARCHIVE_DIR:
        return "归档"
    return folder_meta(scope)[1]


def group_of(rel, base):
    folder = doc_folder(rel)
    if folder == ARCHIVE_DIR:
        for name, prefixes in ARCHIVE_GROUPS:
            if base.startswith(prefixes):
                return name
        return "归档 · 其他"
    if folder:
        return folder_meta(folder)[0]
    if rel.startswith("docs/"):
        return DOCS_MISC[0]
    for name, _s, names in ROOT_GROUPS:
        if base in names:
            return name
    return "根目录 · 其他"


def scope_meta(docs):
    """产出筛选 chip 列表：[{k,label,n}]，只含实际有文档的分类，按 SCOPE_PREF 排序"""
    uniq = {}
    for d in docs:
        uniq[d["scope"]] = d["scopeLabel"]

    def rank(k):
        return SCOPE_PREF.index(k) if k in SCOPE_PREF else 3.5

    keys = sorted(uniq, key=lambda k: (rank(k), k))
    return [{"k": k, "label": uniq[k],
             "n": sum(1 for d in docs if d["scope"] == k)} for k in keys]


def lead_of(text):
    """抽取一句话摘要：优先取标题后的第一条引用块，否则取首段。"""
    lines = [l.lstrip("\ufeff") for l in text.split("\n")]
    i = 0
    # 跳过标题
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and lines[i].lstrip().startswith("#"):
        i += 1
    # 跳过空行
    while i < len(lines) and not lines[i].strip():
        i += 1
    buf = []
    while i < len(lines):
        s = lines[i].strip()
        if not s or s == "---":
            break
        if s.startswith("|") or s.startswith("```"):
            break
        if s.startswith(">"):
            s = s.lstrip(">").strip()
        if not s:
            break
        buf.append(s)
        i += 1
        if len(" ".join(buf)) > 150:
            break
    s = " ".join(buf)
    s = re.sub(r"`([^`]*)`", r"\1", s)
    s = re.sub(r"\*\*([^*]*)\*\*", r"\1", s)
    s = re.sub(r"^\s*[-*+]\s+", "", s)
    return s[:160]


def date_from_name(base):
    m = re.search(r"(20\d{2})-(\d{2})-(\d{2})", base)
    if m:
        return "%s-%s-%s" % m.groups()
    return None


SCAN_TOP = {"docs", "server"}   # 只扫这些顶层目录；docs 下任意子目录自动纳入


def collect():
    docs = []
    paths = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace("\\", "/")
        if rel_dir == ".":
            # 仓库根：只收 *.md，且只往下进 docs / server
            dirnames[:] = [d for d in dirnames if d in SCAN_TOP]
        elif rel_dir == "server" or rel_dir.startswith("docs"):
            # docs 下任意深度的子目录都纳入（新增文件夹无需改脚本）
            dirnames[:] = [d for d in dirnames
                           if not d.startswith(".") and d not in {"build", "node_modules", "_tmp"}]
        else:
            dirnames[:] = []
            continue
        for fn in sorted(filenames):
            if fn.lower().endswith(".md"):
                paths.append(os.path.join(dirpath, fn))

    for p in paths:
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        if rel == "docs/index.html":
            continue
        try:
            with open(p, "r", encoding="utf-8") as f:
                raw = f.read()
        except UnicodeDecodeError:
            with open(p, "r", encoding="gbk", errors="replace") as f:
                raw = f.read()
        raw = raw.lstrip("\ufeff")
        base = os.path.basename(p)
        st = os.stat(p)
        fdate = date_from_name(base)
        mdate = __import__("datetime").datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d")
        title = base
        for line in raw.split("\n"):
            s = line.strip()
            if s.startswith("# "):
                title = re.sub(r"^#\s+", "", s).strip()
                break
        else:
            # 没有 H1 标题：退而用首行非空文本当标题（仅当它足够短、像标题）
            for line in raw.split("\n"):
                s = line.strip()
                if not s or s == "---":
                    continue
                if s.startswith(">"):
                    s = s.lstrip(">").strip()
                s = re.sub(r"[`*]", "", s)
                if 0 < len(s) <= 64:
                    title = s
                break
        scope = scope_of(rel)
        docs.append({
            "id": rel,
            "path": rel,
            "url": base64.b64encode(rel.encode("utf-8")).decode("ascii"),
            "base": base,
            "title": title,
            "group": group_of(rel, base),
            "scope": scope,
            "scopeLabel": scope_label(scope),
            "date": fdate or mdate,
            "mtime": mdate,
            "size": st.st_size,
            "chars": len(raw),
            "lines": raw.count("\n") + 1,
            "nhead": len(re.findall(r"^#{1,4}\s", raw, re.M)),
            "lead": lead_of(raw),
            "text": raw,
        })

    order = {}
    idx = 0
    for name, _s, _n in ROOT_GROUPS:
        order.setdefault(name, idx); idx += 1
    # docs 各子目录：登记过的按登记顺序，其余按目录名排序
    for folder in DOC_FOLDERS:
        order.setdefault(folder_meta(folder)[0], idx); idx += 1
    others = sorted({doc_folder(d["id"]) for d in docs if doc_folder(d["id"])}
                    - {ARCHIVE_DIR} - set(DOC_FOLDERS))
    for folder in others:
        order.setdefault(folder_meta(folder)[0], idx); idx += 1
    order.setdefault(DOCS_MISC[0], idx); idx += 1
    for name, _p in ARCHIVE_GROUPS:
        order.setdefault(name, idx); idx += 1
    order["根目录 · 其他"] = idx; idx += 1
    order["归档 · 其他"] = idx
    docs.sort(key=lambda d: (order.get(d["group"], 99), d["base"]))
    return docs


CSS = r"""
*{box-sizing:border-box}
:root{
  --bg:#f6f7f9; --panel:#ffffff; --panel2:#fbfbfc; --border:#e5e7eb; --border2:#eef0f3;
  --text:#1b1f24; --text2:#3d444d; --muted:#6d7680; --faint:#98a1ab;
  --accent:#2c6bed; --accent2:#eaf1fe; --code-bg:#f4f5f7; --code-bd:#e8eaed;
  --warn-bg:#fff8ec; --warn-bd:#f0d9a8; --ok:#1a7f4b;
  --r:9px; --fs:15px; --shadow:0 1px 2px rgba(16,24,40,.04),0 6px 20px rgba(16,24,40,.05);
}
html,body{margin:0;height:100%}
body{
  background:var(--bg);color:var(--text);
  font:var(--fs)/1.68 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
  -webkit-font-smoothing:antialiased;
}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
code,pre,.mono{font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace}

/* ---------- 布局 ---------- */
.shell{display:grid;grid-template-columns:296px minmax(0,1fr);height:100vh;overflow:hidden}
.sidebar{background:var(--panel);border-right:1px solid var(--border);display:flex;flex-direction:column;min-height:0}
.brand{padding:16px 16px 12px;border-bottom:1px solid var(--border2)}
.brand h1{margin:0;font-size:15px;letter-spacing:.2px;display:flex;align-items:center;gap:8px}
.brand h1 span.dot{width:8px;height:8px;border-radius:50%;background:var(--accent);flex:none}
.brand .sub{margin-top:5px;font-size:11.5px;color:var(--faint);display:flex;gap:10px;flex-wrap:wrap}
.searchwrap{padding:10px 12px 8px;position:relative}
.searchwrap .ico{position:absolute;left:22px;top:50%;transform:translateY(-50%);color:var(--faint);font-size:12px;pointer-events:none}
#q{width:100%;padding:7px 28px 7px 30px;border:1px solid var(--border);background:var(--panel2);
   border-radius:8px;font-size:13px;color:var(--text);outline:none}
#q:focus{border-color:var(--accent);background:#fff;box-shadow:0 0 0 3px var(--accent2)}
.searchwrap .clr{position:absolute;right:20px;top:50%;transform:translateY(-50%);border:0;background:none;
   color:var(--faint);cursor:pointer;font-size:14px;line-height:1;padding:2px;display:none}
.chips{display:flex;gap:6px;padding:2px 12px 10px;flex-wrap:wrap}
.chip{border:1px solid var(--border);background:var(--panel2);color:var(--text2);border-radius:20px;
   padding:3px 10px;font-size:11.5px;cursor:pointer;user-select:none}
.chip:hover{border-color:#cfd6e0}
.chip.on{background:var(--accent);border-color:var(--accent);color:#fff}
.chip .cn{font-style:normal;margin-left:5px;font-size:10.5px;opacity:.55}
.chip.on .cn{opacity:.85}
.tree{overflow-y:auto;flex:1;padding:0 8px 28px;min-height:0}
.tree::-webkit-scrollbar,.content::-webkit-scrollbar,.toc::-webkit-scrollbar{width:9px}
.tree::-webkit-scrollbar-thumb,.content::-webkit-scrollbar-thumb,.toc::-webkit-scrollbar-thumb{
   background:#d8dce2;border-radius:9px;border:2px solid var(--panel)}
.grp{margin-top:10px}
.grp>.gh{display:flex;align-items:center;gap:6px;padding:5px 8px;font-size:11.5px;font-weight:600;
   color:var(--muted);letter-spacing:.4px;cursor:pointer;user-select:none;border-radius:6px}
.grp>.gh:hover{background:var(--panel2)}
.grp>.gh .cnt{color:var(--faint);font-weight:400;margin-left:auto;font-size:11px}
.grp>.gh .cv{color:var(--faint);font-size:9px;transition:transform .15s}
.grp.closed>.gh .cv{transform:rotate(-90deg)}
.grp.closed>.gi{display:none}
.gi{display:block;padding:5px 9px 5px 14px;border-radius:6px;color:var(--text2);font-size:13px;
   cursor:pointer;border-left:2px solid transparent;line-height:1.45}
.gi:hover{background:var(--panel2);color:var(--text)}
.gi.on{background:var(--accent2);color:var(--accent);border-left-color:var(--accent);font-weight:600}
.gi .meta{display:block;font-size:10.5px;color:var(--faint);margin-top:1px;font-weight:400}
.gi.on .meta{color:#7b9bd8}
.empty-tip{padding:18px 14px;color:var(--faint);font-size:12.5px;line-height:1.7}

/* ---------- 主体 ---------- */
.main{display:grid;grid-template-columns:minmax(0,1fr) 226px;
  grid-template-rows:auto minmax(0,1fr);min-height:0;overflow:hidden}
.content{grid-column:1;grid-row:2;overflow-y:auto;padding:0 0 80px;min-height:0;position:relative}
.cbar{grid-column:1;grid-row:1;z-index:5;background:rgba(246,247,249,.92);backdrop-filter:blur(8px);
   border-bottom:1px solid var(--border);padding:9px 34px;display:flex;align-items:center;gap:10px;
   font-size:11.5px;color:var(--muted);min-height:42px}
.cbar .path{font-family:ui-monospace,Menlo,Consolas,monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cbar .sp{flex:1}
.btn{border:1px solid var(--border);background:var(--panel);color:var(--text2);border-radius:6px;
   padding:3px 9px;font-size:11.5px;cursor:pointer;white-space:nowrap}
.btn:hover{border-color:#cfd6e0;background:#fff;color:var(--text)}
.btn.on{background:var(--accent);border-color:var(--accent);color:#fff}
.inner{max-width:820px;margin:0 auto;padding:30px 34px 0}
.hero{padding:34px 34px 6px;max-width:1000px;margin:0 auto}
.hero h2{margin:0 0 6px;font-size:26px;letter-spacing:-.2px}
.hero p.lead{margin:0;color:var(--muted);font-size:13.5px;max-width:640px;line-height:1.8}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(148px,1fr));gap:12px;margin:24px 0 4px}
.card{background:var(--panel);border:1px solid var(--border);border-radius:var(--r);padding:14px 16px;box-shadow:var(--shadow)}
.card .n{font-size:22px;font-weight:700;letter-spacing:-.5px}
.card .l{font-size:11.5px;color:var(--muted);margin-top:3px}
.card.accent .n{color:var(--accent)}
.cmdbar{margin:18px 0 4px;background:var(--panel);border:1px solid var(--border);
   border-left:3px solid var(--accent);border-radius:var(--r);padding:13px 17px 14px}
.cmdbar .cb-t{font-size:12.5px;color:var(--text2);font-weight:600;margin-bottom:9px}
.cmdbar .cb-line{display:flex;align-items:center;gap:9px;flex-wrap:wrap}
.cmdbar code.cmd{background:var(--code-bg);border:1px solid var(--code-bd);border-radius:6px;
   padding:5px 11px;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
   font-size:12.5px;color:var(--text);cursor:pointer;white-space:nowrap}
.cmdbar code.cmd:hover{border-color:var(--accent);background:var(--accent2)}
.cmdbar .cp{cursor:pointer;font:inherit;font-size:11.5px;color:var(--accent);background:var(--accent2);
   border:1px solid #cfe0fd;border-radius:6px;padding:4px 10px}
.cmdbar .cp:hover{background:#dfeafd}
.cmdbar .cb-n{font-size:11.5px;color:var(--faint);margin-top:9px;line-height:1.95}
.cmdbar .cb-n code{background:var(--code-bg);border:1px solid var(--code-bd);border-radius:4px;
   padding:1px 5px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px}
h2.sec{font-size:13px;font-weight:600;color:var(--muted);letter-spacing:.6px;margin:34px 0 12px;
   padding-bottom:7px;border-bottom:1px solid var(--border)}
ul.recents{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:minmax(0,1fr);gap:8px}
ul.recents li{min-width:0;background:var(--panel);border:1px solid var(--border);border-radius:var(--r);
   padding:10px 15px;cursor:pointer;transition:.12s}
ul.recents li:hover{border-color:#c9d4e6;box-shadow:var(--shadow);transform:translateY(-1px)}
ul.recents .r1{display:flex;align-items:baseline;gap:10px}
ul.recents .t{font-size:13.5px;font-weight:600;flex:1 1 auto;min-width:0;line-height:1.5}
ul.recents .dt{font-size:11px;color:var(--faint);flex:none;font-family:ui-monospace,monospace;
   max-width:32%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
ul.recents .d{font-size:12px;color:var(--muted);margin-top:2px;overflow:hidden;
   text-overflow:ellipsis;white-space:nowrap}
.hints{margin-top:26px;background:var(--panel);border:1px solid var(--border);border-radius:var(--r);padding:14px 18px;font-size:12.5px;color:var(--muted);line-height:1.9}
.hints b{color:var(--text2)}
kbd{background:var(--code-bg);border:1px solid var(--code-bd);border-bottom-width:2px;border-radius:4px;
   padding:0 5px;font-size:11px;font-family:ui-monospace,monospace;color:var(--text2)}

/* ---------- 正文排版 ---------- */
.doc-h{max-width:820px;margin:0 auto;padding:0 34px}
.doc-title{margin:26px 0 4px;font-size:25px;line-height:1.35;letter-spacing:-.3px}
.doc-sub{color:var(--faint);font-size:11.5px;display:flex;gap:12px;flex-wrap:wrap;padding-bottom:16px;
   border-bottom:1px solid var(--border);font-family:ui-monospace,Menlo,monospace}
.md{max-width:820px;margin:0 auto;padding:0 34px}
.md h1{font-size:21px;margin:32px 0 12px;padding-bottom:7px;border-bottom:1px solid var(--border2)}
.md h2{font-size:18px;margin:32px 0 12px;padding-bottom:6px;border-bottom:1px solid var(--border2)}
.md h3{font-size:15.5px;margin:26px 0 10px}
.md h4{font-size:14px;margin:20px 0 8px;color:var(--text2)}
.md h5,.md h6{font-size:13px;margin:16px 0 6px;color:var(--muted)}
.md p{margin:11px 0}
.md ul,.md ol{margin:10px 0;padding-left:24px}
.md li{margin:5px 0}
.md li>ul,.md li>ol{margin:4px 0}
.md hr{border:0;border-top:1px solid var(--border);margin:26px 0}
.md blockquote{margin:14px 0;padding:10px 16px;background:#f8fafc;border-left:3px solid #cdd8e8;
   border-radius:0 7px 7px 0;color:var(--text2)}
.md blockquote p{margin:5px 0}
.md blockquote blockquote{background:#f2f5f9}
.md code.ic{background:var(--code-bg);border:1px solid var(--code-bd);border-radius:4px;padding:1px 5px;
   font-size:.88em;color:#9c3d1e;cursor:pointer}
.md code.ic:hover{background:#efe1da;border-color:#e2c9bd}
.md a.doclink{background:var(--accent2);border:1px solid #cfe0fd;border-radius:4px;padding:1px 6px;
   font-size:.88em;font-family:ui-monospace,monospace;color:#1c56c9;white-space:nowrap}
.md a.doclink:hover{background:#dbe8fe;text-decoration:none}
.md a.doclink::after{content:" →";font-size:.85em;opacity:.65}
.md pre.code{background:#fbfbfc;border:1px solid var(--code-bd);border-radius:8px;margin:14px 0;
   overflow:hidden;position:relative}
.md pre.code .cbar2{display:flex;align-items:center;gap:8px;padding:5px 10px;background:#f4f5f7;
   border-bottom:1px solid var(--code-bd);font-size:10.5px;color:var(--faint);letter-spacing:.4px}
.md pre.code .cbar2 .cp{margin-left:auto;cursor:pointer;color:var(--faint)}
.md pre.code .cbar2 .cp:hover{color:var(--accent)}
.md pre.code code{display:block;padding:12px 14px;overflow-x:auto;font-size:12.5px;line-height:1.62;
   color:#2f3742;white-space:pre;tab-size:2}
.md table{border-collapse:separate;border-spacing:0;width:100%;margin:15px 0;font-size:12.8px;
   display:block;overflow-x:auto;max-width:100%}
.md table th,.md table td{border:1px solid var(--border);padding:7px 11px;text-align:left;vertical-align:top}
.md table th{background:#f4f6f9;font-weight:600;color:var(--text2);white-space:nowrap}
.md table tr:nth-child(even) td{background:#fcfcfd}
.md strong{font-weight:650;color:#11151a}
.md del{color:var(--faint)}
.md .task li{list-style:none;margin-left:-18px}
.md .task input{margin-right:6px}
.md .h-anchor{scroll-margin-top:14px}
.headmark{opacity:0;margin-left:8px;font-size:.62em;color:var(--faint);text-decoration:none;font-weight:400}
.md h1:hover .headmark,.md h2:hover .headmark,.md h3:hover .headmark,.md h4:hover .headmark{opacity:1}

/* ---------- 右侧目录 ---------- */
.toc{grid-column:2;grid-row:1/3;border-left:1px solid var(--border);background:var(--panel);
   overflow-y:auto;padding:20px 10px 40px 14px;min-height:0}
.toc .th{font-size:11px;font-weight:600;color:var(--faint);letter-spacing:.6px;margin:0 0 8px;padding-left:8px}
.toc a{display:block;font-size:11.8px;color:var(--muted);padding:3px 8px;border-radius:5px;
   border-left:2px solid transparent;line-height:1.45;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.toc a:hover{background:var(--panel2);color:var(--text);text-decoration:none}
.toc a.lv2{padding-left:8px}
.toc a.lv3{padding-left:20px;font-size:11.4px}
.toc a.lv4{padding-left:32px;font-size:11px;color:var(--faint)}
.toc a.on{color:var(--accent);border-left-color:var(--accent);background:var(--accent2);font-weight:600}
.toc .none{font-size:11.5px;color:var(--faint);padding-left:8px}

/* ---------- 搜索结果 ---------- */
.sres{max-width:900px;margin:0 auto;padding:26px 34px 0}
.sres .sh{font-size:13px;color:var(--muted);margin-bottom:14px}
.sres .sh b{color:var(--text);font-size:15px}
.hit{background:var(--panel);border:1px solid var(--border);border-radius:var(--r);padding:14px 17px;
   margin-bottom:10px;cursor:pointer}
.hit:hover{border-color:#c9d4e6;box-shadow:var(--shadow)}
.hit .ht{font-size:14px;font-weight:650;margin-bottom:3px}
.hit .hp{font-size:11px;color:var(--faint);font-family:ui-monospace,monospace;margin-bottom:8px}
.hit .hs{font-size:12.5px;color:var(--text2);background:var(--panel2);border-radius:6px;padding:7px 10px;
   line-height:1.7;word-break:break-word}
.hit mark{background:#fff2ba;color:#7a4a00;border-radius:3px;padding:0 2px}
.progress{position:sticky;top:0;height:2px;background:transparent;z-index:9}
.progress i{display:block;height:2px;background:var(--accent);width:0}
.toast{position:fixed;left:50%;bottom:34px;transform:translateX(-50%) translateY(14px);background:#1b1f24;
   color:#fff;font-size:12.5px;padding:8px 16px;border-radius:20px;opacity:0;transition:.2s;
   pointer-events:none;z-index:99}
.toast.on{opacity:1;transform:translateX(-50%) translateY(0)}
.menubtn{display:none;border:1px solid var(--border);background:var(--panel);border-radius:6px;
   padding:3px 9px;font-size:11.5px;cursor:pointer}
.scrim{display:none}
.note{background:var(--warn-bg);border:1px solid var(--warn-bd);border-radius:8px;padding:11px 14px;
   font-size:12.3px;color:#8a5a12;margin:16px 0;line-height:1.75}

@media(max-width:1240px){ .main{grid-template-columns:minmax(0,1fr)} .toc{display:none} }
@media(max-width:900px){
  .shell{grid-template-columns:minmax(0,1fr)}
  .sidebar{position:fixed;inset:0 auto 0 0;width:296px;z-index:40;transform:translateX(-100%);
     transition:transform .18s;box-shadow:0 0 40px rgba(0,0,0,.14)}
  body.menu .sidebar{transform:none}
  body.menu .scrim{display:block;position:fixed;inset:0;background:rgba(16,24,40,.28);z-index:39}
  .menubtn{display:inline-block}
  .inner,.md,.doc-h,.hero,.sres{padding-left:18px;padding-right:18px}
}
@media print{
  .sidebar,.toc,.cbar,.menubtn,.progress{display:none!important}
  .shell,.main{display:block!important;height:auto!important;overflow:visible!important}
  .content{overflow:visible!important}
  body{background:#fff}
}
"""

JS = r"""
/* ============================ 数据 ============================ */
const DOCS = /*__DATA__*/;
const META = /*__META__*/;
const BY_ID = {}; DOCS.forEach(d=>BY_ID[d.id]=d);
const BY_BASE = {}; DOCS.forEach(d=>{ (BY_BASE[d.base]=BY_BASE[d.base]||[]).push(d); });

function resolveDoc(ref){
  if(!ref) return null;
  ref = ref.trim().replace(/^\.\//,'');
  if(BY_ID[ref]) return BY_ID[ref];
  const one = BY_BASE[ref.split('/').pop()];
  if(one && one.length===1) return one[0];
  if(one && one.length>1){ // 同名取路径后缀最匹配的
    const hit = one.find(d=>d.path.endsWith(ref)) || one[0];
    return hit;
  }
  const suf = DOCS.filter(d=>d.path.endsWith('/'+ref)||d.path===ref);
  return suf.length===1?suf[0]:null;
}

/* ============================ 工具 ============================ */
const $ = s=>document.querySelector(s);
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function toast(msg){
  let t=$('#toast'); t.textContent=msg; t.classList.add('on');
  clearTimeout(t._tm); t._tm=setTimeout(()=>t.classList.remove('on'),1500);
}
function fmtSize(n){ return n<1024 ? n+' B' : (n/1024).toFixed(n<10240?1:0)+' KB'; }
function fmtChars(n){ return n<10000 ? n.toLocaleString() : (n/10000).toFixed(1)+' 万'; }
function copy(text,label){
  const done=()=>toast(label||'已复制');
  if(navigator.clipboard && window.isSecureContext){ navigator.clipboard.writeText(text).then(done).catch(()=>fallback()); }
  else fallback();
  function fallback(){
    const ta=document.createElement('textarea'); ta.value=text; ta.style.position='fixed'; ta.style.opacity='0';
    document.body.appendChild(ta); ta.select();
    try{document.execCommand('copy');done();}catch(e){toast('复制失败');}
    document.body.removeChild(ta);
  }
}

/* ======================= Markdown 渲染 ======================= */
const RE_BULLET = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
function isListLine(s){ return RE_BULLET.test(s); }
function isSepRow(s){ return /^\s*\|?[\s:\-|]+\|[\s:\-|]*$/.test(s) && s.indexOf('-')>=0; }
function isTableStart(lines,i){
  return lines[i]!=null && lines[i].indexOf('|')>=0 && isSepRow(lines[i+1]||'');
}
function isBlockStart(lines, i){
  const s = lines[i];
  if(!s || !s.trim()) return true;
  if(/^\s*(```|~~~)/.test(s)) return true;
  if(/^#{1,6}\s/.test(s)) return true;
  if(/^\s*>/.test(s)) return true;
  if(/^\s*([-*_])(\s*\1){2,}\s*$/.test(s)) return true;
  if(isListLine(s)) return true;
  if(isTableStart(lines, i)) return true;
  if(/^ {0,3}(<[a-zA-Z\/!])/.test(s)) return true;
  return false;
}

function inline(s){
  s = esc(s);
  const codes = [];
  s = s.replace(/`([^`]+)`/g, (m,c)=>{ codes.push(c); return '\u0001'+(codes.length-1)+'\u0001'; });
  s = s.replace(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, (m,a,u)=>'<img alt="'+a+'" src="'+u+'" style="max-width:100%">');
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, (m,t,u)=>{
    const ext = /^[a-z]+:\/\//i.test(u);
    return '<a href="'+u+'"'+(ext?' target="_blank" rel="noopener"':'')+'>'+t+'</a>';
  });
  s = s.replace(/\*\*\*([^*]+)\*\*\*/g,'<strong><em>$1</em></strong>');
  s = s.replace(/\*\*([^*]+)\*\*/g,'<strong>$1</strong>');
  s = s.replace(/(^|[\s(\u3000])\*([^*\n]+)\*/g,'$1<em>$2</em>');
  s = s.replace(/__([^_]+)__/g,'<strong>$1</strong>');
  s = s.replace(/~~([^~]+)~~/g,'<del>$1</del>');
  s = s.replace(/\u0001(\d+)\u0001/g, (m,i)=> codeHtml(codes[+i]));
  return s;
}
function codeHtml(c){
  if(/\.(md|markdown)$/i.test(c)){
    const d = resolveDoc(c);
    if(d) return '<a class="doclink" href="#/doc/'+d.id+'" data-doc="'+d.id+'">'+c+'</a>';
  }
  return '<code class="ic" title="点击复制">'+c+'</code>';
}

function slug(s){ return String(s).toLowerCase().replace(/[^\w\u4e00-\u9fa5]+/g,'-').replace(/^-|-$/g,'').slice(0,48); }

function renderMarkdown(src){
  const lines = String(src).replace(/\r\n?/g,'\n').split('\n');
  const out = [];
  const toc = [];
  let i = 0, hIdx = 0;
  const usedSlug = {};

  while(i < lines.length){
    const line = lines[i];

    // 围栏代码块
    const fence = line.match(/^\s*(```+|~~~+)\s*([\w+#-]*)\s*$/);
    if(fence){
      const mark = fence[1][0].repeat(3), lang = fence[2]||'';
      i++;
      const buf = [];
      while(i < lines.length && !new RegExp('^\\s*'+mark+'\\s*$').test(lines[i])){ buf.push(lines[i]); i++; }
      i++;
      const code = buf.join('\n');
      out.push('<pre class="code"><div class="cbar2"><span>'+(lang||'text')+'</span>'+
        '<span class="cp" data-copy="'+esc(code)+'" title="复制代码">复制</span></div>'+
        '<code>'+esc(code)+'</code></pre>');
      continue;
    }

    // 空行
    if(!line.trim()){ i++; continue; }

    // 标题
    const h = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/);
    if(h){
      const lv = h[1].length, txt = h[2];
      let s = slug(txt) || ('h'+hIdx);
      usedSlug[s] = (usedSlug[s]||0)+1;
      if(usedSlug[s]>1) s = s+'-'+usedSlug[s];
      const id = 'h'+(hIdx++)+'-'+s;
      if(lv<=4) toc.push({id:id, lv:lv, text:txt.replace(/[*`]/g,'')});
      out.push('<h'+lv+' id="'+id+'" class="h-anchor">'+inline(txt)+
        '<a class="headmark" href="#'+id+'" title="锚点">#</a></h'+lv+'>');
      i++;
      continue;
    }

    // 分隔线
    if(/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)){ out.push('<hr>'); i++; continue; }

    // 引用块
    if(/^\s*>/.test(line)){
      const buf = [];
      while(i < lines.length && (/^\s*>/.test(lines[i]) || (lines[i].trim()==='' && /^\s*>/.test(lines[i+1]||'')))){
        buf.push(lines[i].replace(/^\s*>\s?/,'')); i++;
      }
      out.push('<blockquote>'+renderMarkdown(buf.join('\n')).html+'</blockquote>');
      continue;
    }

    // 表格
    if(isTableStart(lines, i)){
      const head = splitRow(lines[i]);
      i += 2;
      const rows = [];
      while(i < lines.length && lines[i].indexOf('|')>=0 && lines[i].trim()){ rows.push(splitRow(lines[i])); i++; }
      let t = '<table><thead><tr>';
      head.forEach(c=> t += '<th>'+inline(c)+'</th>');
      t += '</tr></thead><tbody>';
      rows.forEach(r=>{
        t += '<tr>';
        for(let k=0;k<head.length;k++) t += '<td>'+inline(r[k]||'')+'</td>';
        t += '</tr>';
      });
      out.push(t+'</tbody></table>');
      continue;
    }

    // 列表
    if(isListLine(line)){
      const r = parseList(lines, i);
      out.push(r.html); i = r.next; continue;
    }

    // 段落
    const buf = [];
    while(i < lines.length && !isBlockStart(lines, i)){ buf.push(lines[i]); i++; }
    if(!buf.length){ buf.push(lines[i]); i++; }   // 兜底：保证指针一定前进
    out.push('<p>'+buf.map(l=>inline(l.trim())).join('<br>')+'</p>');
  }
  return {html: out.join('\n'), toc: toc};
}

function splitRow(line){
  let s = line.trim();
  if(s.startsWith('|')) s = s.slice(1);
  if(s.endsWith('|')) s = s.slice(0,-1);
  const cells = []; let cur = '';
  // 逐字符切分，保留被转义的 \|
  for(let k=0;k<s.length;k++){
    if(s[k]==='\\' && s[k+1]==='|'){ cur += '|'; k++; continue; }
    if(s[k]==='|'){ cells.push(cur.trim()); cur=''; continue; }
    cur += s[k];
  }
  cells.push(cur.trim());
  return cells;
}

function parseList(lines, start){
  const first = RE_BULLET.exec(lines[start]);
  const indent = first[1].length;
  const ordered = /\d/.test(first[2]);
  const items = [];
  let i = start;
  const out = [];
  while(i < lines.length){
    const m = RE_BULLET.exec(lines[i]);
    if(m && m[1].length === indent){
      const isOrd = /\d/.test(m[2]);
      if(isOrd !== ordered && items.length) break;
      items.push({raw:[m[3]], sub:[]});
      i++;
      continue;
    }
    if(m && m[1].length > indent){
      const r = parseList(lines, i);
      if(items.length) items[items.length-1].sub.push(r.html);
      i = r.next;
      continue;
    }
    if(!lines[i].trim()){
      let j = i;
      while(j < lines.length && !lines[j].trim()) j++;
      const nm = RE_BULLET.exec(lines[j]||'');
      if(nm && nm[1].length >= indent){ i = j; continue; }
      break;
    }
    if(m && m[1].length < indent) break;
    if(/^ {2,}/.test(lines[i]) && items.length){
      items[items.length-1].raw.push(lines[i].trim()); i++; continue;
    }
    break;
  }
  const tag = ordered ? 'ol' : 'ul';
  items.forEach(it=>{
    const txt = it.raw.join('\n');
    const task = txt.match(/^\[([ xX])\]\s*([\s\S]*)$/);
    let body;
    if(task){
      body = '<input type="checkbox" disabled'+(task[1].toLowerCase()==='x'?' checked':'')+'> '+inline(task[2]);
    } else {
      body = inline(txt).replace(/\n/g,'<br>');
    }
    out.push('<li>'+body+it.sub.join('')+'</li>');
  });
  const cls = items.some(it=>/^\[[ xX]\]/.test(it.raw.join('')))?' class="task"':'';
  return {html:'<'+tag+cls+'>'+out.join('')+'</'+tag+'>', next:i};
}

/* ============================ 状态 ============================ */
const S = {
  view:'home', id:null, q:'', filter:'all',
  closed:{}, done:{}
};
try{
  const saved = JSON.parse(localStorage.getItem('bp-docs')||'{}');
  if(saved.closed) S.closed = saved.closed;
  if(saved.fs) document.documentElement.style.setProperty('--fs', saved.fs+'px');
  S.fs = saved.fs||15;
  S.last = saved.last;
}catch(e){ S.fs = 15; }
function persist(){
  try{ localStorage.setItem('bp-docs', JSON.stringify({closed:S.closed, fs:S.fs, last:S.last})); }catch(e){}
}

/* ============================ 侧栏 ============================ */
function passFilter(d){
  if(S.filter==='all') return true;
  return d.scope === S.filter;
}
function buildSidebar(){
  const tree = $('#tree');
  const q = S.q.trim().toLowerCase();
  const groups = [];
  DOCS.forEach(d=>{
    if(!passFilter(d)) return;
    if(q && !(d.title.toLowerCase().includes(q) || d.path.toLowerCase().includes(q) || d.text.toLowerCase().includes(q))) return;
    let g = groups.find(x=>x.name===d.group);
    if(!g){ g = {name:d.group, items:[]}; groups.push(g); }
    g.items.push(d);
  });
  if(!groups.length){ tree.innerHTML = '<div class="empty-tip">没有匹配的文档。<br>试试清空搜索或切换筛选。</div>'; return; }
  let html = '';
  if(q){
    const n = groups.reduce((a,g)=>a+g.items.length,0);
    html += '<div class="empty-tip" style="padding:6px 10px 2px">目录已按搜索过滤：命中 <b>'+n+'</b> 篇，清空搜索可恢复完整分类。</div>';
  }
  groups.forEach(g=>{
    const closed = S.closed[g.name] ? ' closed' : '';
    html += '<div class="grp'+closed+'" data-grp="'+esc(g.name)+'">'+
      '<div class="gh"><span class="cv">▼</span><span>'+esc(g.name)+'</span><span class="cnt">'+g.items.length+'</span></div>';
    g.items.forEach(d=>{
      const on = (S.view==='doc' && S.id===d.id) ? ' on' : '';
      html += '<div class="gi'+on+'" data-doc="'+d.id+'" title="'+esc(d.lead||d.path)+'">'+
        esc(d.title)+'<span class="meta">'+d.date+' · '+fmtSize(d.size)+'</span></div>';
    });
    html += '</div>';
  });
  tree.innerHTML = html;
}

/* ============================ 渲染 ============================ */
function homeView(){
  const chars = DOCS.reduce((a,d)=>a+d.chars,0);
  const pool = DOCS.filter(passFilter);
  const recent = pool.slice().sort((a,b)=> (b.date<a.date?-1:1)).slice(0,7);
  const scopes = META.scopes || [];
  const labelOf = k => { const s = scopes.find(x=>x.k===k); return s ? s.label : k; };
  const title = S.filter==='all' ? '最近更新的文档' : '全部「'+labelOf(S.filter)+'」';
  let h = '<div class="hero"><h2>蓝图落地 · 文档中心</h2>'+
    '<p class="lead">设计-施工一体化数字管控平台 ｜ Flutter 客户端 + 后端网关的全部设计与生产文档。左侧按「'+
      scopes.map(s=>s.label).join(' / ')+'」分类，支持全文搜索。</p>'+
    '<div class="cards">'+
      scopes.map(s=>'<div class="card'+(s.k==='current'?' accent':'')+'"><div class="n">'+s.n+'</div>'+
        '<div class="l">'+esc(s.label)+'</div></div>').join('')+
      '<div class="card"><div class="n">'+fmtChars(chars)+'</div><div class="l">总字数（字符）</div></div>'+
    '</div>';
  /* 刷新命令：文档一变这个页面就该重新生成，命令放在最显眼处 */
  h += '<div class="cmdbar">'+
    '<div class="cb-t">📌 文档更新后，重新生成本页只需一条命令</div>'+
    '<div class="cb-line">'+
      '<code class="ic cmd" title="点击复制">python flutter_app/docs/_build_docs_browser.py</code>'+
      '<button class="cp" data-copy="python flutter_app/docs/_build_docs_browser.py">复制命令</button>'+
    '</div>'+
    '<div class="cb-n">在仓库根目录 <code>D:/code/gongdi</code> 下运行；也可以先 <code>cd flutter_app</code>，再跑 <code>python docs/_build_docs_browser.py</code>。'+
    '脚本会重扫 <code>flutter_app/</code> 根目录 + <code>docs/</code> 里的全部 Markdown，重新生成 <code>docs/index.html</code>，并打印分类统计与异常项。'+
    '新增、改名、删除文档后都跑一次，本页的分类树、搜索索引和跨文档链接会自动跟着更新。</div>'+
    '</div>';
  h += '<h2 class="sec">'+title+'</h2><ul class="recents">';
  if(!recent.length) h += '<li><div class="d">当前筛选下没有文档</div></li>';
  recent.forEach(d=>{
    h += '<li data-doc="'+d.id+'"><div class="r1"><span class="t">'+esc(d.title)+'</span>'+
      '<span class="dt">'+d.date+'</span></div>'+
      '<div class="d">'+esc(d.lead||'')+'</div></li>';
  });
  h += '</ul>';
  if(S.filter === 'all'){
    h += '<h2 class="sec">关键入口</h2><ul class="recents">';
    ['USER_WORKFLOW.md','FEATURE_INVENTORY.md','docs/todo/蓝图落地_数据与录入入口（团队说明）.md','docs/todo/蓝图落地_管理后台产品设计.md','docs/todo/BACKEND_ARCHITECTURE.md','docs/todo/蓝图落地_后端技术选型参考（讨论稿）.md','docs/specs/CAPTURE_FLOW.md','docs/specs/DEFECTS_FLOW.md','DESIGN_TOKENS.md']
      .forEach(p=>{
        const d = resolveDoc(p); if(!d) return;
        h += '<li data-doc="'+d.id+'"><div class="r1"><span class="t">'+esc(d.title)+'</span>'+
          '<span class="dt">'+d.path+'</span></div><div class="d">'+esc(d.lead||'')+'</div></li>';
      });
    h += '</ul>';
  }
  h += '<div class="hints"><b>快捷键</b>　<kbd>/</kbd> 聚焦搜索　<kbd>Esc</kbd> 清空/返回　<kbd>←</kbd> <kbd>→</kbd> 上一篇/下一篇<br>'+
    '<b>小技巧</b>　正文里的 <code class="ic">行内代码</code> 点击即复制；写法为 <code class="ic">xxx.md</code> 的跨文档引用会变成可点击跳转。<br>'+
    '<b>数据来源</b>　本页内嵌了 '+DOCS.length+' 篇 Markdown 快照（'+META.built+' 生成），双击即可离线打开；文档更新后按上方那条命令重新生成即可刷新本页。</div>';
  h += '<div class="note">⚠️ 归档文档仅作历史溯源，结论可能已过期 —— 与本页「现行文档」冲突时，以 <b>FEATURE_INVENTORY.md</b> 与 <b>docs/todo/BACKEND_ARCHITECTURE.md</b> 为准。</div>';
  h += '</div>';
  return h;
}

/* 去掉正文开头的一级标题：标题已在页头展示，避免重复 */
function stripLeadingH1(text){
  return String(text).replace(/^[\s\uFEFF]*#\s+[^\n]*\n?/, '');
}

function docView(){
  const d = BY_ID[S.id];
  if(!d) return '<div class="sres"><div class="sh">文档不存在，可能已被移动或改名。</div></div>';
  const r = renderMarkdown(stripLeadingH1(d.text));
  d._toc = r.toc;
  const badge = '<span style="color:'+(d.scope==='archive' ? '#b45309' : (d.scope==='current' ? '#1a7f4b' : '#2c6bed'))+'">'+
    esc(d.scopeLabel || '')+'</span>';
  const mins = Math.max(1, Math.round(d.chars/550));
  return '<div class="progress"><i></i></div>'+
    '<div class="doc-h"><h1 class="doc-title">'+esc(d.title)+'</h1>'+
    '<div class="doc-sub"><span>'+d.path+'</span><span>'+badge+'</span><span>'+d.date+'</span>'+
    '<span>'+fmtSize(d.size)+'</span><span>'+d.chars.toLocaleString()+' 字符</span><span>约 '+mins+' 分钟</span>'+
    '<span>'+d.nhead+' 个小节</span></div></div>'+
    '<div class="md" id="md">'+r.html+'</div>';
}

function searchView(){
  const q = S.q.trim().toLowerCase();
  if(!q) return '<div class="sres"><div class="sh">输入关键词开始全文搜索</div></div>';
  const res = [];
  DOCS.forEach(d=>{
    if(!passFilter(d)) return;
    const cl = d.text.toLowerCase(), inT = d.title.toLowerCase().includes(q),
          inP = d.path.toLowerCase().includes(q);
    const idx = cl.indexOf(q);
    if(idx < 0 && !inT && !inP) return;
    let cnt = 0, p = idx;
    while(p >= 0){ cnt++; p = cl.indexOf(q, p+q.length); }
    res.push({d:d, score:cnt+(inT?50:0)+(inP?20:0), pos:Math.max(idx,0)});
  });
  res.sort((a,b)=> b.score-a.score);
  let h = '<div class="sres"><div class="sh">关键词 <b>'+esc(S.q)+'</b> 命中 <b>'+res.length+'</b> 篇文档</div>';
  if(!res.length) h += '<div class="hit">没有命中。换个词试试，或把筛选切到「全部」。</div>';
  const re = new RegExp('('+S.q.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+')','ig');
  res.slice(0,60).forEach(x=>{
    const d = x.d, txt = d.text, p = x.pos;
    const start = Math.max(0, p-70), end = Math.min(txt.length, p+130);
    let snip = (start>0?'…':'') + txt.slice(start,end).replace(/[#>*`]/g,' ') + (end<txt.length?'…':'');
    snip = esc(snip).replace(re,'<mark>$1</mark>');
    h += '<div class="hit" data-doc="'+d.id+'"><div class="ht">'+esc(d.title)+'</div>'+
      '<div class="hp">'+d.path+' · '+d.date+' · 命中 '+x.score+' 次</div>'+
      '<div class="hs">'+snip+'</div></div>';
  });
  h += '</div>';
  return h;
}

const TOC_IDLE = '<div class="th">目录</div><div class="none">打开一篇文档后显示</div>';

function tocView(){
  const d = BY_ID[S.id];
  if(!d || !d._toc || !d._toc.length) return '<div class="th">目录</div><div class="none">本文没有小节标题</div>';
  let h = '<div class="th">目录 · '+d._toc.length+' 节</div>';
  d._toc.forEach(t=>{
    h += '<a class="lv'+Math.min(t.lv,4)+'" href="#'+t.id+'" data-anchor="'+t.id+'">'+esc(t.text)+'</a>';
  });
  return h;
}

function render(){
  const c = $('#content');
  if(S.view==='doc'){ c.innerHTML = docView(); }
  else if(S.view==='search'){ c.innerHTML = searchView(); }
  else { c.innerHTML = homeView(); }
  c.scrollTop = 0;
  $('#tocwrap').innerHTML = (S.view==='doc') ? tocView() : TOC_IDLE;
  buildChips();
  buildSidebar();
  updateBar();
  bindContent();
  updateSpy();
}

function updateBar(){
  const c = $('#cbar');
  const cur = (S.view==='doc'&&BY_ID[S.id]) ? BY_ID[S.id] : null;
  c.innerHTML = '<button class="menubtn" id="menubtn">☰</button>'+
    '<span class="path">'+ (cur ? esc(cur.path) : (S.view==='search' ? '搜索：'+esc(S.q) : '首页')) +'</span>'+
    '<span class="sp"></span>'+
    (cur ? '<button class="btn" id="bcopy">复制 Markdown</button>'+
           '<button class="btn" id="bpath">复制路径</button>' : '')+
    '<button class="btn" id="bfont-dec">A-</button><button class="btn" id="bfont-inc">A+</button>';
  const mb = $('#menubtn'); if(mb) mb.onclick = ()=>document.body.classList.toggle('menu');
  const bcopy = $('#bcopy'); if(bcopy) bcopy.onclick = ()=>copy(BY_ID[S.id].text, '已复制全文 Markdown');
  const bpath = $('#bpath'); if(bpath) bpath.onclick = ()=>copy('flutter_app/'+BY_ID[S.id].path, '已复制文件路径');
  $('#bfont-dec').onclick = ()=>{ S.fs=Math.max(13,S.fs-1); document.documentElement.style.setProperty('--fs',S.fs+'px'); persist(); };
  $('#bfont-inc').onclick = ()=>{ S.fs=Math.min(19,S.fs+1); document.documentElement.style.setProperty('--fs',S.fs+'px'); persist(); };
}

function bindContent(){
  document.querySelectorAll('#content [data-doc]').forEach(el=>{
    el.addEventListener('click', ev=>{
      if(ev.target.closest('a[href^="http"]')) return;
      ev.preventDefault();
      go(el.getAttribute('data-doc'));
    });
  });
  document.querySelectorAll('#content code.ic').forEach(el=>{
    el.addEventListener('click', ()=>copy(el.textContent,'已复制：'+el.textContent.slice(0,26)));
  });
  document.querySelectorAll('#content .cp').forEach(el=>{
    el.addEventListener('click', ()=>copy(el.getAttribute('data-copy'),'代码已复制'));
  });
  /* 目录 / 标题锚点：只滚动，不污染 URL（否则会被当成路由跳转） */
  document.querySelectorAll('#tocwrap a[data-anchor], #content a.headmark').forEach(a=>{
    a.addEventListener('click', ev=>{
      const id = a.getAttribute('data-anchor') || (a.getAttribute('href')||'').slice(1);
      const target = id && document.getElementById(id);
      if(!target) return;
      ev.preventDefault();
      target.scrollIntoView({block:'start', behavior:'smooth'});
      updateSpy();
    });
  });
  document.querySelectorAll('#content table').forEach(t=>{
    t.querySelectorAll('td').forEach(td=>{
      if(td.textContent.trim()==='—'||td.textContent.trim()==='-') td.style.color='#b9c0c9';
    });
  });
}

/* 滚动高亮 + 阅读进度 */
function updateSpy(){
  const links = [].slice.call(document.querySelectorAll('#tocwrap a[data-anchor]'));
  if(!links.length) return;
  const y = $('#content').scrollTop + 96;
  let cur = links[0];
  links.forEach(l=>{
    const h = document.getElementById(l.getAttribute('data-anchor'));
    if(h && h.offsetTop <= y) cur = l;
  });
  links.forEach(l=>l.classList.toggle('on', l===cur));
}
$('#content').addEventListener('scroll', ()=>{
  const el = $('#content');
  const bar = el.querySelector('.progress i');
  if(bar){
    const max = el.scrollHeight - el.clientHeight;
    bar.style.width = (max>0 ? (el.scrollTop/max*100) : 0) + '%';
  }
  if(S.view === 'doc') updateSpy();
}, true);

/* ============================ 路由 ============================ */
const HASH_DOC = '#/doc/';
function go(id){
  S.id = id; S.view = 'doc'; S.last = id; persist();
  document.body.classList.remove('menu');
  try{ if(location.hash !== HASH_DOC+id) history.replaceState(null, '', HASH_DOC+id); }
  catch(e){ location.hash = HASH_DOC+id; }
  render();
}
function route(){
  const h = location.hash || '#/home';
  if(h.indexOf(HASH_DOC) === 0){
    const id = decodeURIComponent(h.slice(HASH_DOC.length));
    if(BY_ID[id]){ S.id = id; S.view = 'doc'; S.last = id; persist(); render(); return true; }
    S.id = id; S.view = 'doc'; render(); return true;
  }
  if(S.q.trim()){ S.view = 'search'; render(); return true; }
  S.view = 'home'; S.id = null; render();
  return false;
}
/* 浏览器前进/后退：只有 hash 与当前状态不一致时才重绘；页内锚点不当作路由 */
window.addEventListener('hashchange', ()=>{
  const h = location.hash || '';
  if(h && h.indexOf('#/') !== 0) return;
  if(S.view === 'doc' && h === HASH_DOC + S.id) return;
  if(S.view === 'home' && h === '#/home') return;
  route();
});

/* ============================ 事件 ============================ */
const qi = $('#q');
qi.addEventListener('input', ()=>{
  S.q = qi.value;
  $('#qclr').style.display = S.q ? 'block':'none';
  if(S.q.trim()){ S.view='search'; render(); }
  else if(location.hash.startsWith('#/doc/')) { route(); }
  else { S.view='home'; render(); }
});
qi.addEventListener('keydown', e=>{
  if(e.key==='Enter'){
    const first = document.querySelector('.hit');
    if(first) go(first.getAttribute('data-doc'));
  }
});
$('#qclr').addEventListener('click', ()=>{ qi.value=''; S.q=''; $('#qclr').style.display='none'; route(); qi.focus(); });
/* 筛选 chip 完全由 META.scopes 生成：docs 下新增一个目录就自动多一个 chip */
function buildChips(){
  const box = $('#chips'); if(!box) return;
  const items = [{k:'all', label:'全部', n:DOCS.length}].concat(META.scopes || []);
  box.innerHTML = items.map(s=>
    '<span class="chip'+(S.filter===s.k?' on':'')+'" data-f="'+esc(s.k)+'" title="'+s.n+' 篇">'+
      esc(s.label)+'<i class="cn">'+s.n+'</i></span>').join('');
}
$('#chips').addEventListener('click', e=>{
  const c = e.target.closest('.chip'); if(!c) return;
  S.filter = c.getAttribute('data-f');
  render();
});
$('#tree').addEventListener('click', e=>{
  const gh = e.target.closest('.gh');
  if(gh){
    const grp = gh.parentElement, name = grp.getAttribute('data-grp');
    grp.classList.toggle('closed');
    S.closed[name] = grp.classList.contains('closed');
    persist(); return;
  }
  const gi = e.target.closest('.gi');
  if(gi) go(gi.getAttribute('data-doc'));
});
document.addEventListener('keydown', e=>{
  if(e.key==='/' && !/input|textarea/i.test((e.target.tagName||''))){
    e.preventDefault(); qi.focus(); qi.select(); return;
  }
  if(e.key==='Escape'){
    if(document.activeElement===qi){ qi.value=''; S.q=''; $('#qclr').style.display='none'; qi.blur(); route(); }
    else document.body.classList.remove('menu');
  }
  if((e.key==='ArrowRight'||e.key==='ArrowLeft') && S.view==='doc' && !/input|textarea/i.test(e.target.tagName||'')){
    const list = DOCS.filter(passFilter);
    const k = list.findIndex(d=>d.id===S.id);
    if(k>=0){
      const n = e.key==='ArrowRight' ? Math.min(list.length-1,k+1) : Math.max(0,k-1);
      if(n!==k) go(list[n].id);
    }
  }
});

/* 启动 */
if(location.hash){ route(); }
else if(S.last && BY_ID[S.last]){
  S.id = S.last; S.view = 'doc';
  try{ history.replaceState(null, '', HASH_DOC + S.last); }catch(e){}
  render();
}
else { render(); }
"""

HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>蓝图落地 · 文档中心</title>
<style>/*__CSS__*/</style>
</head>
<body>
<div class="shell">
  <aside class="sidebar">
    <div class="brand">
      <h1><span class="dot"></span>文档中心</h1>
      <div class="sub"><span>蓝图落地 · 设计-施工一体化</span></div>
    </div>
    <div class="searchwrap">
      <span class="ico">⌕</span>
      <input id="q" placeholder="搜索标题 / 正文（按 / 聚焦）" autocomplete="off">
      <button class="clr" id="qclr" title="清空">✕</button>
    </div>
    <div class="chips" id="chips"></div>
    <div class="tree" id="tree"></div>
  </aside>
  <div class="main" id="main">
    <div class="cbar" id="cbar"></div>
    <section class="content" id="content"></section>
    <div class="toc" id="tocwrap"></div>
  </div>
</div>
<div class="scrim" id="scrim"></div>
<div class="toast" id="toast"></div>
<script>
/*__JS__*/
</script>
</body>
</html>
"""


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    docs = collect()
    missing = [d["id"] for d in docs if not d["text"].strip()]
    scopes = scope_meta(docs)

    import datetime
    meta = {
        "built": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "total": len(docs),
        "chars": sum(d["chars"] for d in docs),
        "scopes": scopes,
    }

    data_json = json.dumps(docs, ensure_ascii=False, separators=(",", ":"))
    meta_json = json.dumps(meta, ensure_ascii=False, separators=(",", ":"))
    for ch in ("<", ">", "&", "\u2028", "\u2029"):
        repl = {"<": "\\u003c", ">": "\\u003e", "&": "\\u0026",
                "\u2028": "\\u2028", "\u2029": "\\u2029"}[ch]
        data_json = data_json.replace(ch, repl)
        meta_json = meta_json.replace(ch, repl)

    js = JS.replace("/*__DATA__*/", data_json).replace("/*__META__*/", meta_json)
    out = HTML.replace("/*__CSS__*/", CSS).replace("/*__JS__*/", js)

    dst = os.path.join(HERE, "index.html")
    with open(dst, "w", encoding="utf-8") as f:
        f.write(out)

    print("生成:", dst)
    print("  文档 %d 篇（%s）" % (len(docs), " / ".join("%s %d" % (s["label"], s["n"]) for s in scopes)))
    print("  正文字符 %s" % format(meta["chars"], ","))
    print("  产物大小 %.0f KB" % (len(out.encode("utf-8")) / 1024))
    if missing:
        print("  ! 空文件:", ", ".join(missing))
    for d in docs:
        if not d["title"] or d["title"] == d["base"]:
            print("  · 无 H1 标题，回退用文件名:", d["path"])

    groups = {}
    for d in docs:
        groups[d["group"]] = groups.get(d["group"], 0) + 1
    print("  分类 %d 组:" % len(groups))
    for name, n in groups.items():
        print("      %-24s %d" % (name, n))

    loose = [d["path"] for d in docs if "其他" in d["group"]]
    if loose:
        print("  ! 未归类（建议补进 ROOT_GROUPS / DOC_FOLDERS）:")
        for p in loose:
            print("      -", p)

    # 反向检查：ROOT_GROUPS 里登记了但文件已不在（改名/搬家/删除）→ 提醒同步
    bases = {d["base"] for d in docs}
    for name, _s, names in ROOT_GROUPS:
        gone = [n for n in names if n not in bases]
        if gone:
            print("  · 「%s」里登记的这些文件已不存在，可从 ROOT_GROUPS 删掉: %s"
                  % (name, ", ".join(gone)))


if __name__ == "__main__":
    sys.exit(main())
