import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/session_store.dart';
import '../auth/auth_controller.dart';

/// 开屏页（登录 / 欢迎入口）。
///
/// 按设计稿「开屏」帧还原（画布 390×844，背景 #F8F8F8）：
/// - 状态栏 47 + 导航栏 44（纯背景无内容），品牌块 top 139
/// - 品牌块 168×142：64×64 圆角 12 logo + gap16 + 「蓝图落地」24/W600 + gap8 + 「现场数据闭环与缺陷知识库」14/W400
/// - 价值四宫格 244×244（top 305）：2×2，单格 120×120、间距 4、品牌色 5% 渐变底
/// - 底部文案（top 561）「不只看「整改销项」，更沉淀设计经验」12/W400/#919499
/// - 主按钮（top 613）240×48 圆角 8 品牌蓝，「开始使用」16/W500/白
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  // —— 设计稿「开屏」帧专用色（与全局 token 有细微差异，按稿取精确值）——
  static const Color bg = Color(0xFFF8F8F8); // 开屏背景
  static const Color fg = Color(0xFF202224); // 标题-正文
  static const Color muted = Color(0xFF919499); // 辅助说明
  static const Color brand = Color(0xFF0395FF); // 品牌色

  Future<void> _login(WidgetRef ref) async {
    final store = ref.read(sessionStoreProvider);
    await store.save(UserSession(
      userId: 'demo',
      username: 'demo',
      displayName: '演示用户',
      loginAt: DateTime.now(),
    ));
    ref.read(authStateProvider.notifier).state = await store.read();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        // 内容整体垂直居中（设计稿为 390×844 上的绝对定位，实际屏高更高时靠上会显空）；
        // 用 minHeight 约束保证内容不足一屏时居中，超出一屏时仍可正常滚动。
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _BrandBlock(), // 142
                      const SizedBox(height: 24),
                      const _ValueGrid(), // 244
                      const SizedBox(height: 12),
                      const Text(
                        '不只看「整改销项」，更沉淀设计经验',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 20 / 12,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _StartButton(onPressed: () => _login(ref)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 品牌块（Frame 2147227977）：logo 64 圆角 12 + 标题 24/W600 + 副标 14/W400，总高 142。
class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 设计稿 Rectangle 1000003182 为 #D9D9D9 占位底，待替换为真实 logo 图
              color: const Color(0xFFD9D9D9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(MingCuteIcons.rulerLine,
                size: 30, color: Color(0xFF8A8F98)),
          ),
          const SizedBox(height: 16),
          const Text(
            '蓝图落地',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              height: 32 / 24,
              color: LoginPage.fg,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '现场数据闭环与缺陷知识库',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 22 / 14,
              color: LoginPage.muted,
            ),
          ),
        ],
      );
}

/// 价值四宫格（Frame 2147227990）：244×244，2×2，单格 120×120，间距 4。
class _ValueGrid extends StatelessWidget {
  const _ValueGrid();

  // 按稿配色：蓝 #0395FF / 红 #FF4444 / 绿 #00B84A / 橙 #FF9500
  static const _cells = [
    _CellData(
      icon: MingCuteIcons.cameraLine,
      title: '现场拍照',
      desc: '随手记录',
      bgBegin: Alignment.topLeft,
      bgEnd: Alignment.bottomRight,
      bgColors: [Color(0x000395FF), Color(0x0D0395FF)],
      iconBegin: Alignment.topLeft,
      iconEnd: Alignment.bottomRight,
      iconColors: [Color(0x000395FF), Color(0xFF0395FF)],
    ),
    _CellData(
      icon: MingCuteIcons.aiLine,
      title: 'AI分类关联',
      desc: '图纸+规范',
      bgBegin: Alignment.topRight,
      bgEnd: Alignment.bottomLeft,
      bgColors: [Color(0x00FF4444), Color(0x0DFF4444)],
      iconBegin: Alignment.topLeft,
      iconEnd: Alignment.bottomRight,
      iconColors: [Color(0x00FF4444), Color(0xFFFF4444)],
    ),
    _CellData(
      icon: MingCuteIcons.scaleLine,
      title: '责任判定',
      desc: '设计/施工',
      bgBegin: Alignment.topRight,
      bgEnd: Alignment.bottomLeft,
      bgColors: [Color(0x0D00B84A), Color(0x0000B84A)],
      iconBegin: Alignment.bottomRight,
      iconEnd: Alignment.topLeft,
      iconColors: [Color(0xFF00B84A), Color(0x0000B84A)],
    ),
    _CellData(
      icon: MingCuteIcons.storageLine,
      title: '知识库',
      desc: '反哺设计',
      bgBegin: Alignment.topLeft,
      bgEnd: Alignment.bottomRight,
      bgColors: [Color(0x0DFF9500), Color(0x00FF9500)],
      iconBegin: Alignment.bottomRight,
      iconEnd: Alignment.topLeft,
      iconColors: [Color(0xFFFF9500), Color(0x00FF9500)],
    ),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 244,
        height: 244,
        child: Column(
          children: [
            Row(
              children: [
                _ValueCell(data: _cells[0]),
                const SizedBox(width: 4),
                _ValueCell(data: _cells[1]),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _ValueCell(data: _cells[2]),
                const SizedBox(width: 4),
                _ValueCell(data: _cells[3]),
              ],
            ),
          ],
        ),
      );
}

class _CellData {
  final IconData icon;
  final String title;
  final String desc;
  final Alignment bgBegin;
  final Alignment bgEnd;
  final List<Color> bgColors;
  final Alignment iconBegin;
  final Alignment iconEnd;
  final List<Color> iconColors;

  const _CellData({
    required this.icon,
    required this.title,
    required this.desc,
    required this.bgBegin,
    required this.bgEnd,
    required this.bgColors,
    required this.iconBegin,
    required this.iconEnd,
    required this.iconColors,
  });
}

/// 单格 120×120：品牌色 5% 渐变底 + 内容 80×68（icon 20 + gap4 + 标题 22 + gap2 + 副标 20）。
class _ValueCell extends StatelessWidget {
  final _CellData data;
  const _ValueCell({required this.data});

  @override
  Widget build(BuildContext context) => Container(
        width: 120,
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: data.bgBegin,
            end: data.bgEnd,
            colors: data.bgColors,
          ),
        ),
        child: SizedBox(
          width: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 设计稿 icon 的 Vector 用 linear-gradient 填充，这里用 ShaderMask 上渐变色
              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  begin: data.iconBegin,
                  end: data.iconEnd,
                  colors: data.iconColors,
                ).createShader(b),
                blendMode: BlendMode.srcIn,
                child: Icon(data.icon, size: 20, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                data.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 22 / 14,
                  color: LoginPage.fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.desc,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 20 / 12,
                  color: LoginPage.muted,
                ),
              ),
            ],
          ),
        ),
      );
}

/// 主按钮（大按钮）：240×48 圆角 8 品牌蓝，「开始使用」16/W500/白 行高 24。
/// 未复用 AppButton 是因为本帧按稿为圆角 8 / 字重 500，与全局 token（圆角 12 / W700）不同。
class _StartButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _StartButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 240,
        height: 48,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: LoginPage.brand,
            foregroundColor: Colors.white,
            // 关闭 Material 默认 48 点击区扩张，避免高度被撑开
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 24 / 16,
              letterSpacing: 0,
            ),
          ),
          child: const Text('开始使用', textAlign: TextAlign.center),
        ),
      );
}
