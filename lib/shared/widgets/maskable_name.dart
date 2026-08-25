import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// 可点击脱敏的姓名文本。
///
/// 默认显示全名（更真实，类似企业微信「责任到人」）；
/// 点击后切换为脱敏形式（如「林心荃 → 林**」），再次点击恢复全名。
class MaskableName extends StatefulWidget {
  /// 完整姓名。
  final String name;

  /// 文字样式。
  final TextStyle? style;

  /// 悬停 / 点击高亮颜色。
  final Color? accentColor;

  /// 是否只读（不可点击）。默认 false。
  final bool readOnly;

  const MaskableName({
    super.key,
    required this.name,
    this.style,
    this.accentColor,
    this.readOnly = false,
  });

  /// 复姓集合（脱敏时保留前 2 字）。
  static const List<String> _surnames = [
    '欧阳', '上官', '司马', '诸葛', '东方', '慕容', '端木', '南宫', '夏侯', '尉迟',
  ];

  /// 脱敏：复姓保留前 2 字，单姓保留第 1 字，其余字符以 * 替代。
  static String mask(String name) {
    if (name.isEmpty) return name;
    final first2 = name.length >= 2 ? name.substring(0, 2) : name;
    if (_surnames.contains(first2)) {
      return first2 + '*' * (name.length - 2);
    }
    return name.substring(0, 1) + '*' * (name.length - 1);
  }

  @override
  State<MaskableName> createState() => _MaskableNameState();
}

class _MaskableNameState extends State<MaskableName> {
  bool _hidden = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? AppTokens.fg;
    final color = _hidden
        ? (widget.style?.color ?? AppTokens.muted)
        : (widget.style?.color ?? AppTokens.fg);

    final nameWidget = Text(
      _hidden ? MaskableName.mask(widget.name) : widget.name,
      style: (widget.style ?? const TextStyle()).copyWith(
        color: _hover && !widget.readOnly ? accent : color,
        fontWeight: FontWeight.w600,
        decoration: widget.readOnly
            ? widget.style?.decoration
            : TextDecoration.underline,
        decorationColor: accent.withValues(alpha: 0.5),
        decorationStyle: TextDecorationStyle.dashed,
      ),
    );

    if (widget.readOnly) return nameWidget;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => setState(() => _hidden = !_hidden),
        child: Tooltip(
          message: '点击隐藏 / 显示姓名',
          child: nameWidget,
        ),
      ),
    );
  }
}
