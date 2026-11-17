import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/highlight_colors.dart';
import '../../core/widgets/retro_box.dart';

/// Shown while text is selected: pick a color, highlight, save the word,
/// or look up its meaning.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.color,
    required this.onColor,
    required this.canDefine,
    required this.onHighlight,
    required this.onSaveWord,
    required this.onDefine,
    required this.onCopy,
    required this.onClose,
  });

  final Color color;
  final ValueChanged<Color> onColor;

  /// Only a single word can be looked up.
  final bool canDefine;
  final VoidCallback onHighlight;
  final VoidCallback onSaveWord;
  final VoidCallback onDefine;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final c in highlightColors)
                    _Dot(
                      color: c,
                      selected: c.toARGB32() == color.toARGB32(),
                      onTap: () => onColor(c),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: onCopy,
                    icon: const Icon(Icons.content_copy, size: 22),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _BarButton(
                        label: 'Highlight',
                        icon: Icons.highlight,
                        color: color,
                        foreground: AppColors.onLight,
                        onPressed: onHighlight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BarButton(
                        label: 'Save',
                        icon: Icons.star,
                        color: AppColors.teal,
                        foreground: AppColors.onDark,
                        onPressed: onSaveWord,
                      ),
                    ),
                    if (canDefine) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BarButton(
                          label: 'Define',
                          icon: Icons.menu_book,
                          color: AppColors.card,
                          onPressed: onDefine,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.ink,
              width: selected ? 3.5 : 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Like RetroButton, but scales its content down instead of overflowing:
/// three of them share one row on a narrow phone.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.color,
    this.foreground,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final foreground = this.foreground ?? AppColors.ink;
    return RetroBox(
      color: color,
      shadow: 3,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 4),
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 12,
                      letterSpacing: 1,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
