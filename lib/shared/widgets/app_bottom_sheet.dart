import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';

/// 统一底部弹窗壳（设计稿 Frame 2147228008）。
///
/// - 遮罩 #000 50%；sheet 背景 #F4F6F7、顶部圆角 24；
/// - 头部标题居中（W600/16/#202224）+ 关闭按钮（右上 24×24 `closeMediumLine`）；
/// - 内容区水平内缩 12、底部 24（LTRB(12,0,12,24)），头部与内容间距 12。
///
/// 用法：
/// ```dart
/// AppBottomSheet.show(
///   context: context,
///   title: '修改路线名称',
///   body: (ctx) => Column(children: [ /* 内容 + 可选 AppSheetFooter.cancelSave */ ]),
/// );
/// ```
class AppBottomSheet {
  /// 底部弹窗中的描述 / 辅助说明统一样式：14 / 22 / W400，颜色按调用处传入。
  static TextStyle helperStyle([Color color = AppTokens.muted]) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 22 / 14,
        color: color,
      );

  /// 底部弹窗输入框正文统一样式：14 / 22 / W400。
  static const TextStyle inputTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 22 / 14,
    color: AppTokens.fg,
  );

  /// 底部弹窗输入区统一装饰：
  /// 白底 + 1px 浅灰边框 + 8 圆角，聚焦时也不切成蓝色描边。
  static BoxDecoration inputBoxDecoration() => BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(color: AppTokens.border),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      );

  /// 底部弹窗输入框内部统一使用无边框 hint，外层容器负责边框和圆角。
  static InputDecoration inputDecoration({required String hintText}) =>
      InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: hintText,
        hintStyle: helperStyle(),
      );

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required WidgetBuilder body,
    bool useRootNavigator = true,
    // 统一默认开启，避免带输入框的底部弹窗遗漏键盘避让能力。
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      backgroundColor: AppTokens.bg,
      barrierColor: const Color(0x80000000), // 遮罩 #000 50%
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SheetScaffold(
        title: title,
        body: body(ctx),
        onClose: () => Navigator.pop(ctx),
      ),
    );
  }

  /// 自定义底部弹窗壳：
  /// 适用于内部已经自带拖拽区 / 自定义头部的弹窗，但仍需统一遮罩、圆角和底部安全区。
  static Future<T?> showCustom<T>({
    required BuildContext context,
    required Widget Function(BuildContext ctx, double bottomSafeInset) builder,
    bool useRootNavigator = true,
    // 自定义底部弹窗也统一默认开启，避免后续新增输入区时遗漏。
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      backgroundColor: AppTokens.bg,
      barrierColor: const Color(0x80000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bottomSafeInset = MediaQuery.paddingOf(ctx).bottom;
        return builder(ctx, bottomSafeInset);
      },
    );
  }
}

/// 统一弹窗骨架：
/// - 采用 Flutter 官方常见的键盘避让方式：
///   外层按键盘高度整体上移；
/// - 内容区只负责滚动，不做二次键盘补偿；
/// - 保留顶部呼吸空间，避免高内容弹窗贴住状态栏。
class _SheetScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final VoidCallback onClose;

  const _SheetScaffold({
    required this.title,
    required this.body,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 底部安全区始终保留，避免内容贴到系统手势条。
    final bottomSafeInset = media.padding.bottom;
    // Flutter 官方常见做法：用 viewInsets.bottom 让整张弹窗跟着键盘上移。
    final keyboardInset = media.viewInsets.bottom;
    // 顶部保留 24 的呼吸空间，避免高内容弹窗贴住状态栏。
    final maxSheetHeight = media.size.height - media.padding.top - 24;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          24 + bottomSafeInset,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SheetHeader(title: title, onClose: onClose),
              const SizedBox(height: 12),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  // 内容较多时在弹窗内部滚动，避免输入框被遮挡。
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹窗头部：高 48，标题水平居中；右侧 24×24 关闭按钮。
class _SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _SheetHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
                color: AppTokens.fg,
              ),
            ),
            Positioned(
              top: 12,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(MingCuteIcons.closeMediumLine,
                      size: 24, color: Color(0xFF09244B)),
                ),
              ),
            ),
          ],
        ),
      );
}

/// 底部「取消 / 保存」双按钮行（Frame 2147228056）：两按钮等宽、高 48、圆角 8、间距 12。
/// 取消：白底红字（#FF4444）；保存：蓝底白字。
class AppSheetFooter {
  static Widget cancelSave({
    required VoidCallback onCancel,
    required VoidCallback onSave,
    String cancelLabel = '取消',
    String saveLabel = '保存',
  }) =>
      Row(
        children: [
          Expanded(
            child: _SheetButton(
              label: cancelLabel,
              background: AppTokens.surface,
              foreground: const Color(0xFFFF4444),
              onTap: onCancel,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SheetButton(
              label: saveLabel,
              background: AppTokens.brand,
              foreground: AppTokens.onAccent,
              onTap: onSave,
            ),
          ),
        ],
      );
}

class _SheetButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  const _SheetButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  // 高度 48 的按钮统一使用 W600。
                  fontWeight: FontWeight.w600,
                  height: 24 / 16,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      );
}
