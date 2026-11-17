import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_book_reader/core/theme/app_theme.dart';
import 'package:pdf_book_reader/data/models.dart';
import 'package:pdf_book_reader/data/repository.dart';
import 'package:pdf_book_reader/data/review_schedule.dart';
import 'package:pdf_book_reader/features/reader/selection_bar.dart';
import 'package:pdf_book_reader/features/review/review_screen.dart';

class _Words extends Repository {
  _Words(this.due, {this.counts});

  final List<ReviewWord> due;
  final ReviewCounts? counts;
  final answers = <int, ({int box, int due})>{};

  @override
  Future<List<ReviewWord>> wordsToReview(int now, {int limit = 30}) async => [
    ...due,
  ];

  @override
  Future<ReviewCounts> reviewCounts(int now) async =>
      counts ?? (due: due.length, resting: 0, withoutMeaning: 0, nextDue: null);

  @override
  Future<void> setWordReview(
    int id, {
    required int box,
    required int due,
  }) async {
    answers[id] = (box: box, due: due);
  }
}

ReviewWord _word(int id, String word, String meaning, {int box = 0}) =>
    ReviewWord(
      id: id,
      word: word,
      meaning: meaning,
      page: 7,
      box: box,
      bookTitle: 'The Alchemist',
    );

Future<void> _open(WidgetTester tester, Repository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.current, home: const ReviewScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('when a word comes back', () {
    final now = DateTime(2026, 11, 17, 22, 30);
    int day(int offset) =>
        DateTime(2026, 11, 17 + offset).millisecondsSinceEpoch;

    test('a known word rests longer each time', () {
      expect(nextReview(box: 0, knew: true, now: now), (box: 1, due: day(1)));
      expect(nextReview(box: 1, knew: true, now: now), (box: 2, due: day(3)));
      expect(nextReview(box: 2, knew: true, now: now), (box: 3, due: day(7)));
      expect(nextReview(box: 3, knew: true, now: now), (box: 4, due: day(16)));
      expect(nextReview(box: 4, knew: true, now: now), (box: 5, due: day(35)));
    });

    test('the last box is the longest rest, it does not run off the end', () {
      expect(nextReview(box: 5, knew: true, now: now), (box: 5, due: day(35)));
      expect(nextReview(box: 99, knew: true, now: now).box, 5);
    });

    test('a forgotten word starts over and is due at once', () {
      expect(nextReview(box: 4, knew: false, now: now), (
        box: 0,
        due: now.millisecondsSinceEpoch,
      ));
    });

    test('a word known late in the evening is due from the next morning', () {
      final next = nextReview(box: 0, knew: true, now: now);
      expect(
        next.due,
        lessThan(DateTime(2026, 11, 18, 6).millisecondsSinceEpoch),
      );
    });

    test('the day a word is due is said in plain words', () {
      expect(dueLabel(day(0), now), 'today');
      expect(dueLabel(day(1), now), 'tomorrow');
      expect(dueLabel(day(3), now), 'in 3 days');
      expect(dueLabel(day(-2), now), 'today');
    });
  });

  group('review screen', () {
    testWidgets('a word is asked, turned over and marked as known', (
      tester,
    ) async {
      final repo = _Words([
        _word(1, 'omen', '(noun) a sign of what is coming'),
      ]);
      await _open(tester, repo);

      expect(find.text('omen'), findsOneWidget);
      expect(find.textContaining('a sign of what is coming'), findsNothing);
      expect(find.text('I KNEW IT'), findsNothing);

      await tester.tap(find.text('SHOW MEANING'));
      await tester.pumpAndSettle();
      expect(find.textContaining('a sign of what is coming'), findsOneWidget);

      await tester.tap(find.text('I KNEW IT'));
      await tester.pumpAndSettle();

      expect(repo.answers[1]!.box, 1);
      expect(
        repo.answers[1]!.due,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
      expect(find.text('Done for now'), findsOneWidget);
      expect(find.text('You went through 1 word.'), findsOneWidget);
    });

    testWidgets('a word that was not known comes round again', (tester) async {
      final repo = _Words([
        _word(1, 'omen', 'a sign', box: 3),
        _word(2, 'levanter', 'an east wind'),
      ]);
      await _open(tester, repo);

      await tester.tap(find.text('SHOW MEANING'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NOT YET'));
      await tester.pumpAndSettle();

      // Sent back to the start, and the next card is up.
      expect(repo.answers[1]!.box, 0);
      expect(find.text('levanter'), findsOneWidget);
      expect(find.text('Done for now'), findsNothing);

      await tester.tap(find.text('SHOW MEANING'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I KNEW IT'));
      await tester.pumpAndSettle();

      // The first word is back before the sitting ends.
      expect(find.text('omen'), findsOneWidget);
      await tester.tap(find.text('SHOW MEANING'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I KNEW IT'));
      await tester.pumpAndSettle();

      // Known now, but from the start: one day, not the long rest it had.
      expect(repo.answers[1]!.box, 1);
      expect(find.text('Done for now'), findsOneWidget);
      expect(find.text('You went through 2 words.'), findsOneWidget);
    });

    testWidgets('with nothing due it says when the next word comes back', (
      tester,
    ) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await _open(
        tester,
        _Words(
          [],
          counts: (
            due: 0,
            resting: 4,
            withoutMeaning: 0,
            nextDue: tomorrow.millisecondsSinceEpoch,
          ),
        ),
      );

      expect(find.text('All caught up'), findsOneWidget);
      expect(find.textContaining('comes back tomorrow'), findsOneWidget);
    });

    testWidgets('with no saved words it says how to get some', (tester) async {
      await _open(tester, _Words([]));

      expect(find.text('No words to review yet'), findsOneWidget);
      expect(find.textContaining('Long-press a word'), findsOneWidget);
    });
  });

  group('selection bar', () {
    Future<void> show(WidgetTester tester, WordLookup? lookup) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.current,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SelectionBar(
                  color: Colors.orange,
                  onColor: (_) {},
                  lookup: lookup,
                  onHighlight: () {},
                  onSaveWord: () {},
                  onCopy: () {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        );

    testWidgets('one selected word shows its meaning by itself', (
      tester,
    ) async {
      await show(tester, (word: 'omen', meaning: null, loading: true));
      expect(find.text('omen'), findsOneWidget);
      expect(find.text('Looking up…'), findsOneWidget);

      await show(tester, (
        word: 'omen',
        meaning: '(noun) a sign',
        loading: false,
      ));
      expect(find.text('(noun) a sign'), findsOneWidget);
      expect(find.text('DEFINE'), findsNothing);

      await show(tester, (word: 'omen', meaning: null, loading: false));
      expect(find.textContaining('No meaning found'), findsOneWidget);
    });

    testWidgets('several selected words show no meaning', (tester) async {
      await show(tester, null);
      expect(find.text('Looking up…'), findsNothing);
      expect(find.text('HIGHLIGHT'), findsOneWidget);
      expect(find.text('SAVE'), findsOneWidget);
    });
  });
}
