import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? radius;
  const AppCard(
      {super.key, required this.child, this.padding, this.onTap, this.radius});

  @override
  Widget build(BuildContext context) {
    final r = radius ?? AppTokens.radiusLg;
    final container = Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(r),
        boxShadow: AppTokens.elevationRaised,
      ),
      padding: padding ?? const EdgeInsets.all(AppTokens.space4),
      child: child,
    );
    if (onTap == null) return container;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(r),
        onTap: onTap,
        child: container,
      ),
    );
  }
}
