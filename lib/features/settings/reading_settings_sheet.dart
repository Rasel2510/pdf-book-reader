import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/page_tint.dart';
import '../../core/widgets/retro_box.dart';
import 'keep_awake_controller.dart';
import 'page_tint_controller.dart';
import 'page_turn_controller.dart';

/// Bottom sheet with the reader preferences. Applies to every book.
Future<void> showReadingSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ReadingSettingsSheet(),
  );
}

class _ReadingSettingsSheet extends ConsumerWidget {
  const _ReadingSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = ref.watch(pageTintProvider);
    final turn = ref.watch(pageTurnProvider);
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Page color', style: text.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 20,
              children: [
                for (final t in PageTint.values)
                  _Swatch(
                    tint: t,
                    selected: t == tint,
                    onTap: () => ref.read(pageTintProvider.notifier).select(t),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text('Page turn', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              turn == PageTurn.flip
                  ? 'Pages curl over like a real book.'
                  : 'Pages slide sideways.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final t in PageTurn.values) ...[
                  Expanded(
                    child: _Choice(
                      label: t.label,
                      selected: t == turn,
                      onTap: () =>
                          ref.read(pageTurnProvider.notifier).select(t),
                    ),
                  ),
                  if (t != PageTurn.values.last) const SizedBox(width: 14),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text('Applies to every book.', style: text.bodySmall),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Keep screen on', style: text.titleLarge),
              subtitle: Text(
                'No dimming or lock while a book is open.',
                style: text.bodySmall,
              ),
              value: ref.watch(keepAwakeProvider),
              activeTrackColor: AppColors.terracotta,
              onChanged: (on) => ref.read(keepAwakeProvider.notifier).set(on),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RetroBox(
      color: selected ? AppColors.mustard : AppColors.card,
      shadow: selected ? 3 : 0,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  color: selected ? AppColors.onLight : AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final PageTint tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        children: [
          RetroBox(
            color: tint.swatch,
            radius: 4,
            shadow: selected ? 4 : 0,
            child: SizedBox(
              width: 64,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'Aa',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 24,
                      color: tint.textColor,
                    ),
                  ),
                  if (selected)
                    const Positioned(
                      right: 4,
                      bottom: 4,
                      child: Icon(
                        Icons.check_circle,
                        size: 20,
                        color: AppColors.terracotta,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(tint.label.toUpperCase(), style: text.bodySmall),
        ],
      ),
    );
  }
}
