# -*- coding: utf-8 -*-
"""诊断脚本：检查 B01.dxf 实体构成（用于评估 ODA 转换后 DIMENSION 等是否保留）。

背景：B01 是天正 DWG，ODA 直转会丢失 TAuthor 自定义对象（轴网/标注等），
剩余的全是 ACAD_PROXY_OBJECT 不可读。本脚本用 ezdxf 统计各实体类型，
辅助判断当前 DXF 是否能用于尺寸标注自动校准。

用法：python _inspect_b01.py
输出：模型空间/各布局的实体计数、模型空间 extents、ACAD_PROXY_OBJECT 警告数。
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ezdxf
from collections import Counter

path = r"dwg_cache/B01.dxf"
print("读取:", os.path.abspath(path))
doc = ezdxf.readfile(path)
msp = doc.modelspace()
c = Counter(e.dxftype() for e in msp)
print("MODELSPACE 实体统计:", dict(c))

for l in doc.layouts:
    if l.name.lower().startswith("model"):
        continue
    print("布局:", l.name, dict(Counter(e.dxftype() for e in l)))

# 若存在 DIMENSION，列出前 10 个的 defpoint 与文字
dims = list(msp.query("DIMENSION"))
print("MODELSPACE DIMENSION 数量:", len(dims))
for d in dims[:10]:
    try:
        defpt = d.dxf.defpoint
        print("  defpoint=({:.3f},{:.3f})".format(defpt.x, defpt.y),
              "text=", d.dxf.get("text", ""))
    except Exception as e:
        print("  err", e)

# 检查 modelspace 中所有实体的 bbox 范围
from ezdxf import bbox as ezbbox
try:
    b = ezbbox.extents(msp)
    if b.has_data:
        print("模型空间 extents: min=({:.3f},{:.3f}) max=({:.3f},{:.3f}) w={:.3f} h={:.3f}".format(
            b.extmin.x, b.extmin.y, b.extmax.x, b.extmax.y,
            b.extmax.x - b.extmin.x, b.extmax.y - b.extmin.y))
except Exception as e:
    print("extents err", e)
