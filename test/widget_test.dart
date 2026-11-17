import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_book_reader/data/models.dart';

void main() {
  test('Book.progress is clamped between 0 and 1', () {
    const book = Book(
      id: 1,
      title: 't',
      filePath: '/tmp/a.pdf',
      lastPage: 5,
      pageCount: 10,
    );
    expect(book.progress, 0.5);
    expect(book.coverPath, '/tmp/a.jpg');
  });

  test('Book value equality and copyWith', () {
    const a = Book(
      id: 1,
      title: 't',
      filePath: '/tmp/a.pdf',
      lastPage: 5,
      pageCount: 10,
    );
    expect(a, a.copyWith());
    expect(a.copyWith(lastPage: 6), isNot(a));
    expect(a.copyWith(lastPage: 6).pageCount, 10);
  });
}
