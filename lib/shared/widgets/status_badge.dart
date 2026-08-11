import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
}
