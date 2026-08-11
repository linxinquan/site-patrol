import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/di/providers.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return child;

    final phoneMode = ref.watch(devicePhoneModeProvider);

    return Stack(
      children: [
        Positioned.fill(
          child: phoneMode ? _buildPhoneShell(child) : _buildFullScreen(child),
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
    );
  }

  /// 手机尺寸壳：深色底 + 居中 FittedBox 等比缩放。
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
                borderRadius: BorderRadius.circular(44),
                border: Border.all(color: const Color(0xFF334155), width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 40,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: child,
              ),
            ),
          ),
        ),
      );

  /// 桌面全屏。
  Widget _buildFullScreen(Widget child) =>
      ColoredBox(color: const Color(0xFF0B1220), child: child);
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
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
}