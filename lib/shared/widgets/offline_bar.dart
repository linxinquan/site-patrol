import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';

/// 底部固定离线条（HTML demo 各页底部「离线模式 · ...」的等价组件）。
class OfflineBar extends StatelessWidget {
  final String text;
  const OfflineBar({super.key, required this.text});

  /// 默认图纸页文案：「离线模式 · N 张图纸已下载，未下载图纸需联网下载」
  factory OfflineBar.drawings(int count) => OfflineBar(
        text: '离线模式 · $count 张图纸已下载，未下载图纸需联网下载',
      );

  /// 缺陷页文案：「离线模式 · 缺陷数据本地存储，联网后回传」
  static const defects = OfflineBar(
    text: '离线模式 · 缺陷数据本地存储，联网后回传',
  );

  /// 工作台文案：「离线模式 · N 张图纸已下载，可正常看图 / 拍照 / 巡场」
  factory OfflineBar.home(int count) => OfflineBar(
        text: '离线模式 · $count 张图纸已下载，可正常看图 / 拍照 / 巡场',
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space4, vertical: AppTokens.space3),
      decoration: const BoxDecoration(
        color: AppTokens.surface2,
        border: Border(
            top: BorderSide(color: AppTokens.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(MingCuteIcons.wifiOffLine, size: 14, color: AppTokens.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppTokens.muted),
            ),
          ),
        ],
      ),
    );
  }
}