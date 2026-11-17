import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/retro_box.dart';

/// Bottom sheet with a slider over all pages. Pops with the chosen page.
Future<int?> showGoToPageSheet(
  BuildContext context, {
  required int current,
  required int count,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GoToPageSheet(current: current, count: count),
  );
}

class _GoToPageSheet extends StatefulWidget {
  const _GoToPageSheet({required this.current, required this.count});

  final int current;
  final int count;

  @override
  State<_GoToPageSheet> createState() => _GoToPageSheetState();
}

class _GoToPageSheetState extends State<_GoToPageSheet> {
  late double _value = widget.current.clamp(1, widget.count).toDouble();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final page = _value.round();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Go to page', style: text.titleLarge),
            const SizedBox(height: 4),
            Text('Page $page of ${widget.count}', style: text.bodyMedium),
            Slider(
              value: _value,
              min: 1,
              max: widget.count.toDouble(),
              divisions: widget.count > 1 ? widget.count - 1 : null,
              label: '$page',
              activeColor: AppColors.terracotta,
              onChanged: (v) => setState(() => _value = v),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: RetroButton(
                label: 'Go',
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.pop(context, page),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
