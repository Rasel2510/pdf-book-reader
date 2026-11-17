import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_book_reader/features/reader/toc.dart';

void main() {
  test('chapterForPage returns the closest preceding bookmark', () {
    final entries = [
      const TocEntry(
        title: 'Chapter One',
        depth: 0,
        bookmark: Object(),
        pageNumber: 1,
      ),
      const TocEntry(
        title: 'Section',
        depth: 1,
        bookmark: Object(),
        pageNumber: 4,
      ),
      const TocEntry(
        title: 'Chapter Two',
        depth: 0,
        bookmark: Object(),
        pageNumber: 8,
      ),
    ];

    expect(chapterForPage(entries, 6)?.title, 'Section');
    expect(chapterForPage(entries, 8)?.title, 'Chapter Two');
  });

  test('chapterForPage returns null before the first bookmark', () {
    const entries = [
      TocEntry(
        title: 'Chapter One',
        depth: 0,
        bookmark: Object(),
        pageNumber: 3,
      ),
    ];

    expect(chapterForPage(entries, 1), isNull);
  });
}
