import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';
import '../../data/models.dart';

enum LibrarySort {
  recent('Recently read'),
  title('Title A–Z'),
  progress('Most read');

  const LibrarySort(this.label);

  final String label;
}

final librarySortProvider =
    NotifierProvider<LibrarySortController, LibrarySort>(
      LibrarySortController.new,
    );

class LibrarySortController extends Notifier<LibrarySort> {
  static const _key = 'library_sort';

  @override
  LibrarySort build() {
    final saved = ref.read(sharedPrefsProvider).getString(_key);
    return LibrarySort.values.asNameMap()[saved] ?? LibrarySort.recent;
  }

  Future<void> select(LibrarySort sort) async {
    state = sort;
    await ref.read(sharedPrefsProvider).setString(_key, sort.name);
  }
}

/// [books] arrive newest-read first (that is what the database returns).
List<Book> sortBooks(List<Book> books, LibrarySort sort) => switch (sort) {
  LibrarySort.recent => books,
  LibrarySort.title => [
    ...books,
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
  LibrarySort.progress => [
    ...books,
  ]..sort((a, b) => b.progress.compareTo(a.progress)),
};
