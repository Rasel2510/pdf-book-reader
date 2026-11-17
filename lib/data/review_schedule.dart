/// When a saved word comes back for review.
///
/// A word sits in a box, 0 to [lastReviewBox]. Knowing it moves it one box
/// up, and each box waits longer than the one before: a word that keeps
/// being known is asked about ever more rarely. Not knowing it sends it back
/// to box 0, where it is due at once.
library;

/// Days a word rests after it reaches each box.
const reviewIntervals = [0, 1, 3, 7, 16, 35];

final lastReviewBox = reviewIntervals.length - 1;

/// The box and the due time (milliseconds since the epoch) of a word that
/// was in [box] and was just answered.
({int box, int due}) nextReview({
  required int box,
  required bool knew,
  required DateTime now,
}) {
  if (!knew) return (box: 0, due: now.millisecondsSinceEpoch);

  final next = (box + 1).clamp(1, lastReviewBox);
  // Due from the start of that day: a word reviewed late in the evening is
  // not held back until late in the evening.
  final day = DateTime(now.year, now.month, now.day + reviewIntervals[next]);
  return (box: next, due: day.millisecondsSinceEpoch);
}

/// "today", "tomorrow", "in 3 days", for the day a word is due.
String dueLabel(int due, DateTime now) {
  final dueDay = DateTime.fromMillisecondsSinceEpoch(due);
  final days = DateTime(
    dueDay.year,
    dueDay.month,
    dueDay.day,
  ).difference(DateTime(now.year, now.month, now.day)).inHours;
  // Hours, rounded: a day is 23 or 25 hours long when the clocks change.
  final whole = (days / 24).round();
  if (whole <= 0) return 'today';
  if (whole == 1) return 'tomorrow';
  return 'in $whole days';
}
