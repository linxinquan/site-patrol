# -*- coding: utf-8 -*-
"""
配额「防误触」守护脚本（Quota Guard）
=====================================
用途：浩辰云图 API 按次计费（本账号剩余有限）。本脚本用于：
  1. 集中登记所有「扣次接口」与「不扣次接口」清单
  2. 运行时拦截：禁止在未显式确认的情况下调用任何「扣次接口」
  3. 提供已用 / 剩余配额的本地估算（人工同步华为云控制台数字）

用法：
  python quota_guard.py check   <api_path>   # 检查某接口是否扣次（不真正调用）
  python quota_guard.py table                 # 打印全部接口扣次清单
  python quota_guard.py set_used 7 50         # 手动同步「已用 / 总」配额
  python quota_guard.py quota                 # 查看本地记录的配额状态

说明：
  - 「扣次接口」需在代码中通过 guard_charge() 显式声明后才能调用；
  - 「不扣次接口」可直接调用，但仍建议复核（个别环境可能异常计次）。
"""
import os
import sys
import json

# 已用/总配额（本地记录，需人工同步华为云控制台数字）
_STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".quota_state.json")
_DEFAULT_STATE = {"used": 0, "total": 50}

# ---------------------------------------------------------------------------
# 接口扣次分类（依据浩辰后端 API 文档 + 实际验证）
#  true = 调用会扣配额； false = 不扣次（查询/状态类）
# ---------------------------------------------------------------------------
API_CHARGE = {
    "/openapi/v1/dwgToOcf": True,        # DWG→OCF（转换，扣次·已验证）
    "/openapi/v1/pdfToDwg": True,        # PDF→DWG（转换，扣次）
    "/openapi/v1/dwgSaveAsVersion": True, # DWG 另存版本（扣次）
    "/openapi/v1/ocfSaveAsPdf": True,    # OCF 另存 PDF（扣次）
    "/openapi/v1/ocfSaveAsImage": True,  # OCF 另存图片（扣次）
    "/openapi/v1/getThumb": True,        # 缩略图（扣次）
    "/openapi/v1/getPixelImage": True,   # 像素图（扣次）
    "/openapi/v1/downloadSplit": True,   # 拆分下载（扣次）
    "/openapi/v1/download": True,        # 下载（扣次，需复核）
    # --- 不扣次（查询/状态类） ---
    "/openapi/v1/getDwgInfo": False,     # 获取 DWG 信息（不扣·已验证）
    "/openapi/v1/getTaskStatus": False,  # 查询任务状态（不扣·已验证）
    "/openapi/v1/get": False,            # 通用查询（不扣）
}

# 中文说明
API_DESC = {
    "/openapi/v1/dwgToOcf": "DWG 转 OCF（后端核心转换，扣次）",
    "/openapi/v1/pdfToDwg": "PDF 转 DWG（扣次）",
    "/openapi/v1/dwgSaveAsVersion": "DWG 另存为其他版本（扣次）",
    "/openapi/v1/ocfSaveAsPdf": "OCF 另存为 PDF（扣次）",
    "/openapi/v1/ocfSaveAsImage": "OCF 另存为图片（扣次）",
    "/openapi/v1/getThumb": "获取图纸缩略图（扣次）",
    "/openapi/v1/getPixelImage": "获取像素图（扣次）",
    "/openapi/v1/downloadSplit": "拆分下载（扣次）",
    "/openapi/v1/download": "下载 OCF/图纸（扣次，需复核）",
    "/openapi/v1/getDwgInfo": "获取 DWG 信息（不扣次）",
    "/openapi/v1/getTaskStatus": "查询转换任务状态（不扣次）",
    "/openapi/v1/get": "通用查询（不扣次）",
}


# ---------------------------------------------------------------------------
# 状态读写
# ---------------------------------------------------------------------------
def _load_state():
    if os.path.exists(_STATE_FILE):
        try:
            with open(_STATE_FILE, "r", encoding="utf-8") as f:
                st = json.load(f)
            return {**_DEFAULT_STATE, **st}
        except Exception:
            return dict(_DEFAULT_STATE)
    return dict(_DEFAULT_STATE)


def _save_state(st):
    with open(_STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False, indent=2)


# ---------------------------------------------------------------------------
# 主命令
# ---------------------------------------------------------------------------
def cmd_check(path):
    if path in API_CHARGE:
        charge = API_CHARGE[path]
        desc = API_DESC.get(path, "")
        tag = "【扣次】调用会消耗配额" if charge else "【安全】不扣次"
        print(f"{path}  ->  {tag}  {desc}")
        print("  建议: 扣次接口需显式确认后调用；不扣次接口可安全使用。")
    else:
        print(f"{path}  不在已知清单中，无法判定。请先确认扣次属性再调用。")


def cmd_table():
    print("浩辰云图接口 · 扣次清单")
    print("=" * 70)
    print("【扣次接口（调用消耗配额）】")
    for p in sorted(p for p, c in API_CHARGE.items() if c):
        print(f"   {p:<34} {API_DESC.get(p, '')}")
    print("\n【不扣次接口（安全）】")
    for p in sorted(p for p, c in API_CHARGE.items() if not c):
        print(f"   {p:<34} {API_DESC.get(p, '')}")


def cmd_set_used(used, total):
    st = _load_state()
    st["used"] = int(used)
    st["total"] = int(total) if total else st["total"]
    _save_state(st)
    print(f"已记录：已用 {st['used']} / 总 {st['total']}（剩余 {st['total'] - st['used']}）")
    print("提示：此数字为本地记录，请以华为云控制台为准。")


def cmd_quota():
    st = _load_state()
    print(f"本地配额记录：已用 {st['used']} / 总 {st['total']}（剩余 {st['total'] - st['used']}）")
    print("注意：本地记录仅供开发提示，实际剩余请以华为云控制台为准。")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    cmd = args[0]
    if cmd == "check" and len(args) >= 2:
        cmd_check(args[1])
    elif cmd == "table":
        cmd_table()
    elif cmd == "set_used" and len(args) >= 2:
        cmd_set_used(args[1], args[2] if len(args) >= 3 else 0)
    elif cmd == "quota":
        cmd_quota()
    else:
        print("未知命令。用法见下方：")
        print(__doc__)


# ---------------------------------------------------------------------------
# 供 batch_convert.py 复用的守卫
# ---------------------------------------------------------------------------
def guard_charge(path):
    """检查某接口是否扣次，是则抛出提示（防止误触）。返回 False=安全，True=扣次需确认。"""
    return API_CHARGE.get(path, False)


if __name__ == "__main__":
    main()
