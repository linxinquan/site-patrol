import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/di/providers.dart';
import '../../core/theme/design_tokens.dart';

/// Web 调试专用「设备视口外壳」：
/// - 仅在 Web 端渲染；移动端（iOS/Android）直接返回 child，零侵入。
/// - 点击右上角悬浮按钮，在「手机尺寸壳（390×844）」与「桌面全屏」间切换。
/// - 手机模式下的 MediaQuery 由 App.builder 显式注入（避免 FittedBox 在 web
///   release 下推断尺寸导致的 Provider 初始化问题）。
class DeviceFrame extends ConsumerWidget {
  final Widget child;
  const DeviceFrame({super.key, required this.child});

  static const double phoneWidth = 390;
  static const double phoneHeight = 844;
  // 真机（iPhone 12/13/14）安全区：顶部状态栏 47pt、底部 home indicator 34pt。
  static const double statusbarH = 47;
  static const double homeIndicatorH = 34;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return child;

    final phoneMode = ref.watch(devicePhoneModeProvider);

    // DeviceFrame 位于 MaterialApp 之外，需显式提供 Directionality，
    // 否则 Stack 的默认 alignment（AlignmentDirectional）会报错：
    // "No Directionality widget found."
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(
            child:
                phoneMode ? _buildPhoneShell(child) : _buildFullScreen(child),
          ),
          // 悬浮切换按钮（右上角，半透明小药丸）
          Positioned(
            top: 12,
            right: 12,
            child: _ToggleButton(
              phoneMode: phoneMode,
              onTap: () => ref
                  .read(devicePhoneModeProvider.notifier)
                  .state = !phoneMode,
            ),
          ),
        ],
      ),
    );
  }

  /// 手机尺寸壳：真机形态（iPhone 12/13/14，390×844）——
  /// 深色底 + 居中 FittedBox 等比缩放，内嵌 模拟状态栏(时间/信号/电量) + 底部 home indicator（无刘海）。
  Widget _buildPhoneShell(Widget child) => Container(
        color: const Color(0xFF0B1220),
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: Container(
              width: phoneWidth,
              height: phoneHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF334155), width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 40,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // App 内容（顶部状态栏 / 底部 home 区域由 MediaQuery padding 避让）
                  Positioned.fill(child: child),
                  // 状态栏（时间 / 信号 / WiFi / 电量）
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: statusbarH,
                    child: _StatusBar(),
                  ),
                  // 底部 home indicator
                  Positioned(
                    bottom: 8,
                    left: (phoneWidth - 134) / 2,
                    child: Container(
                      width: 134,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// 桌面全屏。
  Widget _buildFullScreen(Widget child) =>
      ColoredBox(color: const Color(0xFF0B1220), child: child);
}

/// 模拟 iOS 状态栏：左侧显示时间，右侧显示 信号 / WiFi / 电量。
/// 适用于浅色页面（元素为深色 #222222）。
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            time,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppTokens.fg,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              _SignalBars(),
              SizedBox(width: 6),
              Icon(MingCuteIcons.wifiLine, size: 14, color: AppTokens.fg),
              SizedBox(width: 6),
              _Battery(),
            ],
          ),
        ],
      ),
    );
  }
}

/// 信号条（4 根递增竖线，底部对齐）。
class _SignalBars extends StatelessWidget {
  const _SignalBars();
  static const _heights = [4.0, 6.0, 8.0, 10.0];

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in _heights)
            Padding(
              padding: const EdgeInsets.only(right: 1.5),
              child: Container(
                width: 2.5,
                height: h,
                decoration: BoxDecoration(
                  color: AppTokens.fg,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      );
}

/// 电量图标（边框 + 内芯 + 右侧凸头）。
class _Battery extends StatelessWidget {
  const _Battery();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 21,
            height: 10.5,
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              border: Border.all(color: AppTokens.fg, width: 1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppTokens.fg,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Container(
            width: 1.5,
            height: 4,
            margin: const EdgeInsets.only(left: 1),
            decoration: BoxDecoration(
              color: AppTokens.fg,
              borderRadius: BorderRadius.circular(0.75),
            ),
          ),
        ],
      );
}

class _ToggleButton extends StatelessWidget {
  final bool phoneMode;
  final VoidCallback onTap;
  const _ToggleButton({required this.phoneMode, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xDD111827),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 12),
            ],
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  phoneMode ? Icons.smartphone : Icons.desktop_windows,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  phoneMode ? '手机' : '桌面',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
}