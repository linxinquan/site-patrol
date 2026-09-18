import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

/// 「蓝色主按钮」——全 App 唯一的主操作按钮实现（Figma Frame 2147228056）。
///
/// 为什么单独拆一个组件：[AppButton] 是通用可配按钮（三档尺寸、圆角默认 12、
/// 字重按档位走），照设计稿写主按钮时必须手工覆写 `size / radius / fontWeight`，
/// 历史上因此反复出错：高度被 `visualDensity` 缩成 40、圆角误用 12、字重在
/// W500/W600 之间来回改。**最终规范（用户 2026-09-18 裁定）：字重 = W600。**
/// 本组件把主按钮规范**锁死在组件内部**，调用方只需给文案和回调，不再依赖记参数：
///
/// | 项 | 值 | 来源 |
/// |---|---|---|
/// | 底色 | `#0395FF` | `AppTokens.accent` |
/// | 高度 | **48（严格值）** | `AppTokens.buttonH_lg` |
/// | 圆角 | **8** | `AppTokens.radiusMd` |
/// | 左右内距 | 24 | `AppTokens.buttonPadX_lg` |
/// | 文字 | 16 / **W600** / `#FFFFFF` | 行高 24、字距 0、显式 MiSans |
/// | 宽度 | 默认满宽 | `width` 传 null 则由内容决定 |
///
/// 高度靠四重兜底保证恒定 48，任何主题/局部样式都改不动：
/// ① 外层 `SizedBox(height)` ② `minimumSize == maximumSize == 48`
/// ③ `tapTargetSize.shrinkWrap`（关掉 Material 默认 48 点击区扩张）
/// ④ `visualDensity.standard`（否则 web/桌面会被判为 compact 再缩 8px）。
///
/// 纯文字、不带图标（设计禁止「图标 + 文字」组合）；禁用态沿用主题禁用色，
/// 需要特定灰底时传 `disabledBgColor`。
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// 宽度：默认 `double.infinity`（满宽）；传 `null` 则由内容 + 内距决定（用于并排布局）。
  final double? width;

  /// 字重：默认 **W600**（主操作最终规范，用户 2026-09-18 裁定）。
  /// 非特殊设计稿不要改：调用方若传 w500 会让主按钮弱于卡片次级标题。
  final FontWeight fontWeight;

  /// 高度：默认 48。**仅当设计稿明确给出其它高度时才传**，避免再次把尺寸散落到各处。
  final double height;

  final Color? disabledBgColor;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.width = double.infinity,
    this.fontWeight = FontWeight.w600,
    this.height = AppTokens.buttonH_lg,
    this.disabledBgColor,
  });

  @override
  Widget build(BuildContext context) {
    const double fontSize = 16;
    return SizedBox(
      width: width,
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppTokens.accent,
          foregroundColor: AppTokens.onAccent,
          disabledBackgroundColor: disabledBgColor,
          // App 交互：悬停/按压不做浏览器式高亮浮层（styleFrom 会覆盖主题，
          // 必须在按钮样式里显式关掉）。
          overlayColor: Colors.transparent,
          // 高度严格锁定：min == max，且关闭 Material 默认点击区扩张。
          minimumSize: Size(width ?? 0, height),
          maximumSize: Size(width ?? double.infinity, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          // 兜底：不依赖主题密度（web/桌面 adaptive 会判 compact 缩 8px）。
          visualDensity: VisualDensity.standard,
          padding:
              const EdgeInsets.symmetric(horizontal: AppTokens.buttonPadX_lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          textStyle: const TextStyle(
            fontFamily: AppTokens.fontFamily,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            height: 24 / fontSize,
            leadingDistribution: TextLeadingDistribution.even,
            color: AppTokens.onAccent,
          ).copyWith(fontWeight: fontWeight),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
