/// Reading totals for one calendar day (all books together).
final class ReadingDay {
  const ReadingDay({
    required this.day,
    required this.pages,
    required this.seconds,
  });

  /// Local midnight of that day.
  final DateTime day;
  final int pages;
  final int seconds;

  bool get active => pages > 0 || seconds > 0;
}

/// 'yyyy-MM-dd' in local time; the key of the reading_log table.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _midnight(DateTime d, [int minusDays = 0]) =>
    DateTime(d.year, d.month, d.day - minusDays);

final class ReadingStats {
  const ReadingStats({
    required this.today,
    required this.streak,
    required this.lastSeven,
    required this.totalPages,
    required this.totalSeconds,
    required this.activeDays,
  });

  factory ReadingStats.compute(List<ReadingDay> days, DateTime now) {
    final byKey = {for (final d in days) dayKey(d.day): d};
    ReadingDay on(DateTime date) =>
        byKey[dayKey(date)] ?? ReadingDay(day: date, pages: 0, seconds: 0);

    final today = _midnight(now);

    // Consecutive active days, ending today (or yesterday, so the streak is
    // not shown as lost before the reader has had a chance to read today).
    var cursor = on(today).active ? today : _midnight(today, 1);
    var streak = 0;
    while (on(cursor).active) {
      streak++;
      cursor = _midnight(cursor, 1);
    }

    return ReadingStats(
      today: on(today),
      streak: streak,
      lastSeven: [for (var i = 6; i >= 0; i--) on(_midnight(today, i))],
      totalPages: days.fold(0, (sum, d) => sum + d.pages),
      totalSeconds: days.fold(0, (sum, d) => sum + d.seconds),
      activeDays: days.where((d) => d.active).length,
    );
  }

  final ReadingDay today;
  final int streak;

  /// Oldest first, ending with today; days without reading are zeros.
  final List<ReadingDay> lastSeven;
  final int totalPages;
  final int totalSeconds;
  final int activeDays;
}

/// "42 min", "1 h 05 min", "0 min".
String formatDuration(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h h $m min';
}
