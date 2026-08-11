import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/design_tokens.dart';

/// 统一的 AsyncValue 渲染：loading / error / data。
class AsyncState<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  const AsyncState({super.key, required this.value, required this.builder});

  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        loading: () => const Center(
            child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
        error: (e, _) => Center(
          child: Text('加载失败：$e',
              style: const TextStyle(color: AppTokens.danger)),
        ),
      );
}
