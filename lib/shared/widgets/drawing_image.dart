import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// 图纸底图统一渲染：http(s) 开头走网络（本地转换上传图），否则按 asset（预置图）。
/// 上传图纸为网络底图 PNG；预置图纸仍为 assets，协议向后兼容。
class DrawingImage extends StatelessWidget {
  final String src;
  final BoxFit fit;
  /// 加载失败自定义兜底（如查看器的 _CadPlaceholder）；空则显示默认错误提示。
  final Widget? errorWidget;
  const DrawingImage(this.src,
      {super.key, this.fit = BoxFit.contain, this.errorWidget});

  @override
  Widget build(BuildContext context) {
    final ImageProvider provider =
        src.startsWith('http') ? NetworkImage(src) : AssetImage(src);
    return Image(
      image: provider,
      fit: fit,
      loadingBuilder: (ctx, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (_, __, ___) =>
          errorWidget ??
          Center(
            child: Text('底图加载失败\n请确认 CAD 服务(8800)已启动',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTokens.muted)),
          ),
    );
  }
}
