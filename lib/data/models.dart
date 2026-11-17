import 'package:path/path.dart' as p;

final class Book {
  const Book({
    required this.id,
    required this.title,
    required this.filePath,
    required this.lastPage,
    required this.pageCount,
  });

  factory Book.fromMap(Map<String, Object?> m) => Book(
    id: m['id'] as int,
    title: m['title'] as String,
    filePath: m['file_path'] as String,
    lastPage: m['last_page'] as int,
    pageCount: m['page_count'] as int,
  );

  final int id;
  final String title;
  final String filePath;
  final int lastPage;
  final int pageCount;

  Book copyWith({String? title, int? lastPage, int? pageCount}) => Book(
    id: id,
    title: title ?? this.title,
    filePath: filePath,
    lastPage: lastPage ?? this.lastPage,
    pageCount: pageCount ?? this.pageCount,
  );

  // Value equality: unchanged books keep their widgets out of the rebuild.
  @override
  bool operator ==(Object other) =>
      other is Book &&
      other.id == id &&
      other.title == title &&
      other.filePath == filePath &&
      other.lastPage == lastPage &&
      other.pageCount == pageCount;

  @override
  int get hashCode => Object.hash(id, title, filePath, lastPage, pageCount);

  /// Cover image generated at import time, next to the PDF copy.
  String get coverPath => '${p.withoutExtension(filePath)}.jpg';

  double get progress =>
      pageCount == 0 ? 0 : (lastPage / pageCount).clamp(0.0, 1.0);
}

final class Highlight {
  const Highlight({
    required this.id,
    required this.page,
    required this.text,
    this.color,
    this.annotationMarker,
  });

  factory Highlight.fromMap(Map<String, Object?> m) => Highlight(
    id: m['id'] as int,
    page: m['page'] as int,
    text: m['text'] as String,
    color: m['color'] as int?,
    annotationMarker: m['annotation_marker'] as String?,
  );

  final int id;
  final int page;
  final String text;

  /// ARGB value of the highlight color; null for highlights made before
  /// colors existed.
  final int? color;
  final String? annotationMarker;
}

/// A saved word as a flashcard: the word of any book, with its meaning.
final class ReviewWord {
  const ReviewWord({
    required this.id,
    required this.word,
    required this.meaning,
    required this.page,
    required this.box,
    required this.bookTitle,
  });

  factory ReviewWord.fromMap(Map<String, Object?> m) => ReviewWord(
    id: m['id'] as int,
    word: m['word'] as String,
    meaning: m['meaning'] as String,
    page: m['page'] as int,
    box: m['box'] as int,
    bookTitle: m['title'] as String,
  );

  final int id;
  final String word;
  final String meaning;
  final int page;

  /// How well the word is known, 0 (new or forgotten) upwards; see
  /// `review_schedule.dart`.
  final int box;
  final String bookTitle;

  ReviewWord inBox(int box) => ReviewWord(
    id: id,
    word: word,
    meaning: meaning,
    page: page,
    box: box,
    bookTitle: bookTitle,
  );
}

/// Where the saved words stand: [due] can be reviewed now, [resting] come
/// back later (the first of them at [nextDue], milliseconds since the
/// epoch), [withoutMeaning] cannot be reviewed until they are looked up.
typedef ReviewCounts = ({
  int due,
  int resting,
  int withoutMeaning,
  int? nextDue,
});

final class SavedWord {
  const SavedWord({
    required this.id,
    required this.page,
    required this.word,
    this.meaning,
  });

  factory SavedWord.fromMap(Map<String, Object?> m) => SavedWord(
    id: m['id'] as int,
    page: m['page'] as int,
    word: m['word'] as String,
    meaning: m['meaning'] as String?,
  );

  final int id;
  final int page;
  final String word;

  /// Short dictionary meaning; null until looked up (needs internet).
  final String? meaning;
}
