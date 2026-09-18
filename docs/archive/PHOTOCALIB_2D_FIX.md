# P0-1 修复：PhotoCalib 升级为 2D 坐标（含序列化兼容）— 交付 CodeBuddy

> 只改 4 个文件，共 6 处替换。按下面顺序操作，每处都是"找到旧代码 → 整段替换为新代码"。
> 前置：先读 `lib/data/models.dart`（PhotoCalib 约 511~534 行、MeasureSession.toJson/fromJson 约 612~664 行）、`lib/core/storage/measure_store.dart`（约 36~88 行）、`lib/features/measure/measure_page.dart`（`_applyRefCalib` 约 198~220 行）。
> 注意：`models.dart` 已 `import 'dart:math' as math;`（第 1 行），新代码直接用 `math.sqrt`，不要重复导入。

---

## ① `lib/data/models.dart` — 整段替换 PhotoCalib 类（原 511~534 行）

```dart
/// 照片侧量距的一次标定：以已知尺寸参考物（卷尺/标准块）标定照片上的像素比例。
/// 存储参考物两端点完整像素坐标（2D），mm/px 用 2D 欧氏距离计算。
class PhotoCalib {
  final double refMm; // 参考物真实尺寸（mm）
  final double ax; // 起点像素 x（整图坐标系，0..imgW）
  final double ay; // 起点像素 y（整图坐标系，0..imgH）
  final double bx; // 终点像素 x
  final double by; // 终点像素 y
  final double imgW; // 照片整图像素宽
  final double imgH; // 照片整图像素高
  const PhotoCalib({
    required this.refMm,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    required this.imgW,
    this.imgH = 0,
  });

  /// 参考物像素跨度（2D 欧氏距离，px）。
  double get spanPx => math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));

  /// 照片像素比例（mm/px）：参考物尺寸 / 像素跨度（2D）。
  double get mmPerPx => spanPx <= 1e-6 ? 0 : refMm / spanPx;

  PhotoCalib copyWith({
    double? refMm,
    double? ax,
    double? ay,
    double? bx,
    double? by,
    double? imgW,
    double? imgH,
  }) =>
      PhotoCalib(
        refMm: refMm ?? this.refMm,
        ax: ax ?? this.ax,
        ay: ay ?? this.ay,
        bx: bx ?? this.bx,
        by: by ?? this.by,
        imgW: imgW ?? this.imgW,
        imgH: imgH ?? this.imgH,
      );

  /// 新格式序列化。
  Map<String, dynamic> toJson() => {
        'refMm': refMm,
        'ax': ax,
        'ay': ay,
        'bx': bx,
        'by': by,
        'imgW': imgW,
        'imgH': imgH,
      };

  /// 兼容旧格式（仅 {refMm, pixA, pixB, imgW}）：旧数据 ay=by=0，
  /// 退化为水平距离计算，与旧版行为一致，不抛异常。
  factory PhotoCalib.fromJson(Map<String, dynamic> m) {
    final pixA = (m['pixA'] as num?)?.toDouble();
    final pixB = (m['pixB'] as num?)?.toDouble();
    return PhotoCalib(
      refMm: (m['refMm'] as num?)?.toDouble() ?? 0,
      ax: (m['ax'] as num?)?.toDouble() ?? pixA ?? 0,
      ay: (m['ay'] as num?)?.toDouble() ?? 0,
      bx: (m['bx'] as num?)?.toDouble() ?? pixB ?? 0,
      by: (m['by'] as num?)?.toDouble() ?? 0,
      imgW: (m['imgW'] as num?)?.toDouble() ?? 0,
      imgH: (m['imgH'] as num?)?.toDouble() ?? 0,
    );
  }
}
```

---

## ② `lib/data/models.dart` — MeasureSession.toJson 中 photoCalib 段（原 619~626 行）

**旧代码**（整段删除）：
```dart
        'photoCalib': photoCalib == null
            ? null
            : {
                'refMm': photoCalib!.refMm,
                'pixA': photoCalib!.pixA,
                'pixB': photoCalib!.pixB,
                'imgW': photoCalib!.imgW,
              },
```
**替换为**：
```dart
        'photoCalib': photoCalib?.toJson(),
```

## ③ `lib/data/models.dart` — MeasureSession.fromJson 中 photoCalib 段（原 646~653 行）

**旧代码**（整段删除）：
```dart
      photoCalib: calib == null
          ? null
          : PhotoCalib(
              refMm: (calib['refMm'] as num).toDouble(),
              pixA: (calib['pixA'] as num).toDouble(),
              pixB: (calib['pixB'] as num).toDouble(),
              imgW: (calib['imgW'] as num).toDouble(),
            ),
```
**替换为**：
```dart
      photoCalib: calib == null ? null : PhotoCalib.fromJson(calib),
```

## ④ `lib/core/storage/measure_store.dart` — _toJson 中 photoCalib 段（原 43~50 行）

**旧代码**（整段删除）：
```dart
        'photoCalib': s.photoCalib == null
            ? null
            : {
                'refMm': s.photoCalib!.refMm,
                'pixA': s.photoCalib!.pixA,
                'pixB': s.photoCalib!.pixB,
                'imgW': s.photoCalib!.imgW,
              },
```
**替换为**：
```dart
        'photoCalib': s.photoCalib?.toJson(),
```

## ⑤ `lib/core/storage/measure_store.dart` — _fromJson 中 photoCalib 段（原 70~77 行）

**旧代码**（整段删除）：
```dart
      photoCalib: calib == null
          ? null
          : PhotoCalib(
              refMm: (calib['refMm'] as num).toDouble(),
              pixA: (calib['pixA'] as num).toDouble(),
              pixB: (calib['pixB'] as num).toDouble(),
              imgW: (calib['imgW'] as num).toDouble(),
            ),
```
**替换为**：
```dart
      photoCalib: calib == null ? null : PhotoCalib.fromJson(calib),
```

## ⑥ `lib/features/measure/measure_page.dart` — _applyRefCalib 构造处（原 208~213 行）

**旧代码**：
```dart
    final calib = PhotoCalib(
      refMm: refMm,
      pixA: _refPicks[0].dx,
      pixB: _refPicks[1].dx,
      imgW: _photoSize!.width,
    );
```
**替换为**：
```dart
    final calib = PhotoCalib(
      refMm: refMm,
      ax: _refPicks[0].dx,
      ay: _refPicks[0].dy,
      bx: _refPicks[1].dx,
      by: _refPicks[1].dy,
      imgW: _photoSize!.width,
      imgH: _photoSize!.height,
    );
    if (calib.spanPx <= 1e-3) {
      AppSnack.show(context, '参考物两点过近，请重新点选', kind: AppSnackKind.danger);
      return;
    }
```

---

## 不需要改的文件

- `lib/core/utils/measure_math.dart`：`photoMeasuredMm` / `photoDistancePx` / `photoMmPerPx` 都基于 `calib.mmPerPx`，新模型 getter 已兼容，无需改动。
- `server/measure_server.py`：服务端只存原始 JSON，字段透传，无需改动。
- `_test_measure.ps1`：POST body 里 photoCalib 仍是旧格式 {refMm,pixA,pixB,imgW}——**有意保留**，正好验证向后兼容。

---

## 验证清单

1. `flutter analyze` 无新增 error（两处 toJson 替换后无未使用变量告警）
2. **兼容验证**：用 `_test_measure.ps1` 的旧格式 JSON 走一遍 MeasureStore.load → 会话能读出、photoCalib 非空、mmPerPx = refMm/|pixB-pixA|（水平退化行为与旧版一致）
3. **新格式验证**：照片上竖着标定参考物（如门高 1000mm，两点 dy 差大、dx 差≈0）→ Chip 显示 mm/px 为合理值（≈1000/竖跨距），量同方向线段数值合理；修复前此场景会爆出天文数字
4. **全流程**：标定（斜线/竖线各一次）→ 量距 → 加入校对 → 判定 → 保存 → 重进页面会话恢复，数值一致
