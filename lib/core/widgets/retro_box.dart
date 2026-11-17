import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Ink-outlined box with a hard offset shadow (the core retro look).
class RetroBox extends StatelessWidget {
  const RetroBox({
    super.key,
    required this.child,
    this.color,
    this.radius = 6,
    this.shadow = 4,
    this.padding,
  });

  final Widget child;
  final Color? color;
  final double radius;
  final double shadow;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.ink, width: 2),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, offset: Offset(shadow, shadow)),
        ],
      ),
      child: child,
    );
  }
}

/// Flat, outlined button with a hard shadow.
class RetroButton extends StatelessWidget {
  const RetroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.mustard,
    this.foreground = AppColors.onLight,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color? color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return RetroBox(
      color: color,
      shadow: 3,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 13,
                    letterSpacing: 1.2,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
