import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_book_reader/app.dart';
import 'package:pdf_book_reader/core/file_utils.dart';
import 'package:pdf_book_reader/core/preferences.dart';
import 'package:pdf_book_reader/core/theme/app_colors.dart';
import 'package:pdf_book_reader/core/theme/page_tint.dart';
import 'package:pdf_book_reader/data/models.dart';
import 'package:pdf_book_reader/data/repository.dart';
import 'package:pdf_book_reader/features/library/library_controller.dart';
import 'package:pdf_book_reader/features/settings/page_tint_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Shelf extends Repository {
  _Shelf(this.shelf);

  final List<Book> shelf;
  final renamed = <int, String>{};

  @override
  Future<List<Book>> books() async => shelf;

  @override
  Future<void> renameBook(int bookId, String title) async {
    renamed[bookId] = title;
  }
}

Book _book(int id, String title) => Book(
  id: id,
  title: title,
  filePath: '/nowhere/$id.pdf',
  lastPage: 1,
  pageCount: 10,
);

void main() {
  group('book title from a file name', () {
    test('a date and time on the front is dropped', () {
      expect(
        cleanBookTitle('15-05-2021-084550The-Alchemist-Paulo-Coelho'),
        'The Alchemist Paulo Coelho',
      );
    });

    test('a few digits may be the title itself', () {
      expect(cleanBookTitle('1984'), '1984');
      expect(cleanBookTitle('2001 A Space Odyssey'), '2001 A Space Odyssey');
    });

    test('underscores and lone dashes stand for spaces', () {
      expect(cleanBookTitle('my_book_final'), 'my book final');
      expect(cleanBookTitle('Deep-Work'), 'Deep Work');
      expect(cleanBookTitle('Spider-Man 2'), 'Spider-Man 2');
    });

    test('a copy number on the end is dropped', () {
      expect(cleanBookTitle('Atomic Habits (1)'), 'Atomic Habits');
    });

    test('a name with nothing but numbers is kept as it is', () {
      expect(cleanBookTitle('20240101_123456'), '20240101_123456');
    });
  });

  group('with the app open', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      AppColors.useNight(false);
    });

    tearDown(() => AppColors.useNight(false));

    testWidgets('the Night page turns the whole app dark, and back', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(
            _Shelf([_book(1, 'The Alchemist')]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const App()),
      );
      await tester.pumpAndSettle();
      expect(find.text('The Alchemist'), findsOneWidget);

      Color background() => Theme.of(
        tester.element(find.text('My Library')),
      ).scaffoldBackgroundColor;
      Color titleColor() =>
          tester.widget<Text>(find.text('The Alchemist')).style!.color!;

      final dayPaper = background();
      final dayInk = titleColor();
      expect(dayPaper.computeLuminance(), greaterThan(0.5));

      await container.read(pageTintProvider.notifier).select(PageTint.night);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(AppColors.night, isTrue);
      expect(background().computeLuminance(), lessThan(0.05));
      // Text that was built before the change is light now.
      expect(titleColor().computeLuminance(), greaterThan(0.5));
      // The shelf is still open: nothing was reset.
      expect(find.text('The Alchemist'), findsOneWidget);

      await container.read(pageTintProvider.notifier).select(PageTint.sepia);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(background(), dayPaper);
      expect(titleColor(), dayInk);
    });

    test('old file-name titles on the shelf are tidied once', () async {
      final shelf = _Shelf([
        _book(1, '15-05-2021-084550The-Alchemist-Paulo-Coelho'),
        _book(2, 'Already Fine'),
        _book(3, 'OneWord'),
      ]);
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(shelf),
        ],
      );
      addTearDown(container.dispose);

      final books = await container.read(libraryProvider.future);
      expect(books.map((b) => b.title), [
        'The Alchemist Paulo Coelho',
        'Already Fine',
        'OneWord',
      ]);
      expect(shelf.renamed, {1: 'The Alchemist Paulo Coelho'});

      // A title the reader gives a book later is never changed again.
      shelf.renamed.clear();
      container.invalidate(libraryProvider);
      await container.read(libraryProvider.future);
      expect(shelf.renamed, isEmpty);
    });
  });
}
