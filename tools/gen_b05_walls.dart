import 'dart:convert';
import 'dart:io';

void main() {
  // 与 providers.dart seedDefaultCalibrations 完全一致
  const a = 0.3308888888888889;
  const d = -0.3308888888888889;
  const c = -359.3091448275862;
  const f = 852.4496763746746;
  const viewW = 4500.0;
  const viewH = 2551.0;

  // 相对坐标 0-100 的墙段（演示用）
  final segs = <List<List<double>>>[
    [
      [15.0, 25.0],
      [40.0, 25.0]
    ],
    [
      [40.0, 25.0],
      [40.0, 75.0]
    ],
    [
      [40.0, 75.0],
      [15.0, 75.0]
    ],
    [
      [15.0, 75.0],
      [15.0, 25.0]
    ],
    [
      [55.0, 15.0],
      [55.0, 50.0]
    ],
    [
      [55.0, 50.0],
      [85.0, 50.0]
    ],
  ];

  List<double> screenToWorld(double px, double py) =>
      [(px - c) / a, (py - f) / d];

  final lines = <Map<String, dynamic>>[];
  for (final s in segs) {
    final p1 = [s[0][0] / 100 * viewW, s[0][1] / 100 * viewH];
    final p2 = [s[1][0] / 100 * viewW, s[1][1] / 100 * viewH];
    final w1 = screenToWorld(p1[0], p1[1]);
    final w2 = screenToWorld(p2[0], p2[1]);
    lines.add({
      'layer': 'WALL',
      'pts': [
        [double.parse(w1[0].toStringAsFixed(1)),
            double.parse(w1[1].toStringAsFixed(1))],
        [double.parse(w2[0].toStringAsFixed(1)),
            double.parse(w2[1].toStringAsFixed(1))],
      ],
    });
  }

  final json = {
    'key': 'dy04_7_B05',
    'wall_lines': lines,
  };

  // 用正斜杠绝对路径（避免中文路径在 PowerShell 沙箱编码错位）
  final outPath = 'F:/建筑验收工具/site-patrol/assets/walls/dy04_7_B05_walls.json';
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(json));
  print('wrote ${lines.length} segments to $outPath');
}