import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

/// 统一按钮组件（对齐设计令牌「按钮三档」规范）。
///
/// - 三档尺寸：lg(高48) / md(高36) / sm(高32)，默认 md。高度为**严格值**：
///   通过 min/maxSize 锁定 + tapTargetSize.shrinkWrap（否则 Material 默认 48 点击区会把
///   md/sm 撑到 48，上下 padding 也会把 lg 撑到 56）。
/// - 三种形态：filled（实色品牌蓝底白字） / outlined（描边） / text（纯文字）。
/// - 纯文字按钮，不带图标：大按钮统一为文字按钮，禁止「图标 + 文字」组合（icon 参数已移除）。
/// - 颜色、圆角(AppTokens.radiusButton = 12)、字重(w700)、字距(0)、行高(字号+8) 全部复用全局 token。
/// - 宽度默认自适应（由内容与左右 padding 决定）；满宽大按钮传 `width: double.infinity`。
/// - 大按钮左右 padding 下限 24，中小按钮下限 12（见 AppTokens.buttonPadX_*）。
/// - [disabledBgColor]：filled 形态禁用态底色（onPressed 为 null 时生效），不传则用主题默认。
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonSize size;
  final bool outlined;
  final bool text;
  final double? width;
  final Color? disabledBgColor;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.md,
    this.outlined = false,
    this.text = false,
    this.width,
    this.disabledBgColor,
  });

  (double h, double px, double fs) _metrics() {
    switch (size) {
      case AppButtonSize.lg:
        return (AppTokens.buttonH_lg, AppTokens.buttonPadX_lg, 16);
      case AppButtonSize.md:
        return (AppTokens.buttonH_md, AppTokens.buttonPadX_md, 14);
      case AppButtonSize.sm:
        return (AppTokens.buttonH_sm, AppTokens.buttonPadX_sm, 12);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (h, px, fs) = _metrics();
    final fg = (text || outlined) ? AppTokens.accent : AppTokens.onAccent;
    final child = Text(label);

    final style = FilledButton.styleFrom(
      backgroundColor: text
          ? null
          : (outlined ? Colors.transparent : AppTokens.accent),
      foregroundColor: fg,
      disabledBackgroundColor:
          (text || outlined) ? null : disabledBgColor,
      // 高度严格锁定为档位值：min == max 高度，且关闭 Material 默认 48 点击区扩张
      minimumSize: Size(width ?? 0, h),
      maximumSize: Size(width ?? double.infinity, h),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.symmetric(horizontal: px),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusButton),
      ),
      textStyle: TextStyle(
        fontSize: fs,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: (fs + 8) / fs,
        color: fg,
      ),
      side: outlined ? const BorderSide(color: AppTokens.accent) : null,
    );

    if (text) return TextButton(onPressed: onPressed, style: style, child: child);
    if (outlined) {
      return OutlinedButton(onPressed: onPressed, style: style, child: child);
    }
    return FilledButton(onPressed: onPressed, style: style, child: child);
  }
}

/// 按钮尺寸档位。
enum AppButtonSize { lg, md, sm }
