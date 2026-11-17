import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/retro_box.dart';
import '../../data/reading_stats.dart';
import '../../data/repository.dart';

final statsProvider = FutureProvider.autoDispose<ReadingStats>((ref) async {
  final days = await ref.watch(repositoryProvider).readingDays();
  return ReadingStats.compute(days, DateTime.now());
});

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Reading stats')),
      body: stats == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        color: AppColors.terracotta,
                        onColor: AppColors.onDark,
                        label: 'STREAK',
                        value: '${stats.streak}',
                        unit: stats.streak == 1 ? 'day' : 'days',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _Tile(
                        color: AppColors.mustard,
                        onColor: AppColors.onLight,
                        label: 'TODAY',
                        value: '${stats.today.pages}',
                        unit: 'pages · ${formatDuration(stats.today.seconds)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _WeekChart(days: stats.lastSeven),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        color: AppColors.teal,
                        onColor: AppColors.onDark,
                        label: 'ALL TIME',
                        value: '${stats.totalPages}',
                        unit: 'pages',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _Tile(
                        color: AppColors.navy,
                        onColor: AppColors.onDark,
                        label: 'TIME READ',
                        value: formatDuration(stats.totalSeconds),
                        unit: 'on ${stats.activeDays} days',
                        small: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'A page counts when you turn to the next one. Time counts '
                  'while you are turning pages, not while the book sits open.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.color,
    required this.onColor,
    required this.label,
    required this.value,
    required this.unit,
    this.small = false,
  });

  final Color color;
  final Color onColor;
  final String label;
  final String value;
  final String unit;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return RetroBox(
      color: color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(letterSpacing: 1.5, color: onColor),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: small ? 24 : 40,
              height: 1.1,
              color: onColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(unit, style: text.bodySmall?.copyWith(color: onColor)),
        ],
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days});

  final List<ReadingDay> days;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final most = days.fold<int>(0, (m, d) => d.pages > m ? d.pages : m);

    return RetroBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LAST 7 DAYS · PAGES',
            style: text.bodySmall?.copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${d.pages}', style: text.bodySmall),
                          const SizedBox(height: 4),
                          Container(
                            height: most == 0 ? 3 : 3 + 70 * d.pages / most,
                            decoration: BoxDecoration(
                              color: d.pages == 0
                                  ? AppColors.paperDark
                                  : AppColors.terracotta,
                              border: Border.all(
                                color: AppColors.ink,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _letters[d.day.weekday - 1],
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
