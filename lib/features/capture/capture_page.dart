import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/design_tokens.dart';

/// 拍照验收占位页（P3 承接：图钉选点 / 快门 / VL 识别 / 保存记录）。
class CapturePage extends StatelessWidget {
  final String? anchorLabel;
  const CapturePage({super.key, this.anchorLabel});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(anchorLabel == null ? '拍照验收' : '拍照验收 · $anchorLabel'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppTokens.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.camera,
                    size: 30, color: AppTokens.accent),
              ),
              const SizedBox(height: 16),
              const Text('拍照验收',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.fg)),
              const SizedBox(height: 8),
              const Text('P3 实现：图钉选点 · 快门 · VL 识别 · 保存记录',
                  style: TextStyle(fontSize: 13, color: AppTokens.muted)),
            ],
          ),
        ),
      );
}
