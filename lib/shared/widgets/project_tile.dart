import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models.dart';

/// 项目选择卡（共用组件）：选择项目页与首页切换项目底部弹层共用。
/// 白底圆角 12、padding 12、48 建筑图标圆头像 + 名称 16/W600 + 地址 14/#666。
/// 选中：1px 蓝边框 #428BF7（透明边框占位防位移）；地址可两行，卡片高度自适应。
class ProjectTile extends StatelessWidget {
  final Project project;
  final bool selected;
  final VoidCallback onTap;
  const ProjectTile({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTokens.brand : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 48×48 建筑图标圆头像（Group 2131330414）
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppTokens.surface2,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                MingCuteIcons.building6Line,
                size: 24,
                color: AppTokens.fg,
              ),
            ),
            const SizedBox(width: 8),

            // 文本列：名称 + 地址
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    project.location,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTokens.fg2,
                      height: 22 / 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
