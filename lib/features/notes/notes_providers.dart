import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/repository.dart';

/// Bookmarked pages per book id, kept in memory.
///
/// The reader and the notes screen watch the same state, so a bookmark
/// removed in Notes updates the reader's icon with no query and no refresh.
/// Toggling is optimistic: the UI changes first, the DB write follows.
/// (Plain NotifierProvider on purpose: same API in Riverpod 2 and 3.)
final bookmarksProvider =
    NotifierProvider<BookmarksController, Map<int, Set<int>>>(
      BookmarksController.new,
    );

class BookmarksController extends Notifier<Map<int, Set<int>>> {
  final _loading = <int, Future<void>>{};

  @override
  Map<int, Set<int>> build() => const {};

  /// Loads one book's bookmarks once; later calls return at once.
  Future<void> load(int bookId) {
    if (state.containsKey(bookId)) return Future<void>.value();
    return _loading[bookId] ??= _load(bookId).whenComplete(() {
      _loading.remove(bookId);
    });
  }

  Future<void> _load(int bookId) async {
    final pages = await ref.read(repositoryProvider).bookmarkPages(bookId);
    state = {...state, bookId: pages};
  }

  Future<void> toggle(int bookId, int page) async {
    await load(bookId); // never write on top of an unloaded set
    final marked = state[bookId]?.contains(page) ?? false;
    await _set(bookId, page, on: !marked);
  }

  Future<void> remove(int bookId, int page) => _set(bookId, page, on: false);

  Future<void> _set(int bookId, int page, {required bool on}) async {
    final next = {...?state[bookId]};
    if (on) {
      next.add(page);
    } else {
      next.remove(page);
    }
    state = {...state, bookId: next};
    await ref.read(repositoryProvider).setBookmark(bookId, page, on: on);
  }
}

final highlightsProvider = FutureProvider.autoDispose
    .family<List<Highlight>, int>(
      (ref, bookId) => ref.watch(repositoryProvider).highlights(bookId),
    );

final wordsProvider = FutureProvider.autoDispose.family<List<SavedWord>, int>(
  (ref, bookId) => ref.watch(repositoryProvider).words(bookId),
);
