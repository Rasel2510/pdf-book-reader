import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/retro_box.dart';
import '../../data/models.dart';
import '../notes/notes_screen.dart';
import '../reader/reader_screen.dart';
import '../settings/reading_settings_sheet.dart';
import '../stats/stats_screen.dart';
import 'book_card.dart';
import 'library_controller.dart';
import 'library_sort.dart';

enum _Menu { stats, sortRecent, sortTitle, sortProgress, backup, restore }

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    if (ref.read(importingProvider)) return; // one import at a time
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    try {
      final file = await FilePicker.pickFile(
        type: .custom,
        allowedExtensions: ['pdf'],
      );
      if (file == null) return;

      await ref.read(libraryProvider.notifier).add(file);
    } on NotAPdfException {
      say('That file is not a PDF, or it is damaged.');
    } catch (error, stackTrace) {
      debugPrint('Could not add book: $error\n$stackTrace');
      say('Could not add the book.');
    }
  }

  /// Saves every book with its notes into one file the user keeps
  /// somewhere safe (the app's own storage is erased on uninstall).
  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final busy = ref.read(importingProvider.notifier);
    if (ref.read(importingProvider)) return;
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    busy.set(true);
    File? zip;
    try {
      zip = await ref.read(backupProvider).create();
      if (zip == null) {
        say('There are no books to back up yet.');
        return;
      }
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final saved = await FilePicker.saveFile(
        fileName:
            'paperleaf-backup-${now.year}-${two(now.month)}-'
            '${two(now.day)}.zip',
        bytes: await zip.readAsBytes(),
        mimeType: 'application/zip',
        dialogTitle: 'Save library backup',
      );
      if (saved != null) say('Backup saved.');
    } catch (error, stackTrace) {
      debugPrint('Could not back up: $error\n$stackTrace');
      say('Could not create the backup.');
    } finally {
      busy.set(false);
      try {
        await zip?.delete();
      } catch (_) {}
    }
  }

  /// Adds the books of a backup file that are not on the shelf yet.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final busy = ref.read(importingProvider.notifier);
    if (ref.read(importingProvider)) return;
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    try {
      final file = await FilePicker.pickFile(
        type: .custom,
        allowedExtensions: ['zip'],
      );
      final path = file?.path;
      if (file == null) return;
      if (path == null) {
        say('Could not read that file.');
        return;
      }

      busy.set(true);
      final result = await ref.read(backupProvider).restore(path);
      await ref.read(libraryProvider.notifier).reload();
      say(switch (result) {
        (added: 0, skipped: 0) => 'That backup has no books in it.',
        (added: 0, skipped: _) => 'Every book of that backup is on the shelf.',
        (added: 1, skipped: _) => 'Restored 1 book.',
        (added: final n, skipped: _) => 'Restored $n books.',
      });
    } on BadBackupException {
      say('That file is not a Paperleaf backup, or it is damaged.');
    } catch (error, stackTrace) {
      debugPrint('Could not restore: $error\n$stackTrace');
      // Books restored before the failure are on the shelf.
      await ref.read(libraryProvider.notifier).reload();
      say('Could not restore the backup.');
    } finally {
      busy.set(false);
    }
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Book book, {
    int? startPage,
  }) async {
    // The reader pushes its final progress into the library state on exit.
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(book: book, startPage: startPage),
      ),
    );
  }

  /// Highlights, bookmarks and words of one book; tapping an item opens
  /// the reader on that page.
  Future<void> _openNotes(
    BuildContext context,
    WidgetRef ref,
    Book book,
  ) async {
    final page = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => NotesScreen(book: book)),
    );
    if (page != null && context.mounted) {
      await _open(context, ref, book, startPage: page);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Book book) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: book.title),
    );
    if (title != null) {
      await ref.read(libraryProvider.notifier).rename(book, title);
    }
  }

  void _onMenu(BuildContext context, WidgetRef ref, _Menu item) {
    final sort = ref.read(librarySortProvider.notifier);
    switch (item) {
      case _Menu.stats:
        Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const StatsScreen()),
        );
      case _Menu.backup:
        unawaited(_backup(context, ref));
      case _Menu.restore:
        unawaited(_restore(context, ref));
      case _Menu.sortRecent:
        sort.select(LibrarySort.recent);
      case _Menu.sortTitle:
        sort.select(LibrarySort.title);
      case _Menu.sortProgress:
        sort.select(LibrarySort.progress);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.ink, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        title: const Text('Delete book?'),
        content: Text('"${book.title}" and its notes will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (!(ok ?? false) || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(libraryProvider.notifier).remove(book);
    } catch (error, stackTrace) {
      debugPrint('Could not delete book: $error\n$stackTrace');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not delete the book.')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider);
    final sort = ref.watch(librarySortProvider);
    final text = Theme.of(context).textTheme;
    final count = books.value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 84,
        actions: [
          IconButton(
            tooltip: 'Reading settings',
            icon: const Icon(Icons.tune),
            onPressed: () => showReadingSettingsSheet(context),
          ),
          PopupMenuButton<_Menu>(
            tooltip: 'More',
            onSelected: (item) => _onMenu(context, ref, item),
            itemBuilder: (_) {
              final sort = ref.read(librarySortProvider);
              return [
                const PopupMenuItem(
                  value: _Menu.stats,
                  child: Text('Reading stats'),
                ),
                const PopupMenuItem(
                  value: _Menu.backup,
                  child: Text('Back up library'),
                ),
                const PopupMenuItem(
                  value: _Menu.restore,
                  child: Text('Restore a backup'),
                ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: _Menu.sortRecent,
                  checked: sort == LibrarySort.recent,
                  child: Text(LibrarySort.recent.label),
                ),
                CheckedPopupMenuItem(
                  value: _Menu.sortTitle,
                  checked: sort == LibrarySort.title,
                  child: Text(LibrarySort.title.label),
                ),
                CheckedPopupMenuItem(
                  value: _Menu.sortProgress,
                  checked: sort == LibrarySort.progress,
                  child: Text(LibrarySort.progress.label),
                ),
              ];
            },
          ),
          const SizedBox(width: 4),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Library', style: text.headlineSmall),
            const SizedBox(height: 2),
            Text(
              '$count ${count == 1 ? 'BOOK' : 'BOOKS'} ON THE SHELF',
              style: text.bodySmall?.copyWith(letterSpacing: 1.5),
            ),
          ],
        ),
      ),
      floatingActionButton: RetroButton(
        label: 'Add PDF',
        icon: Icons.add,
        onPressed: () => _import(context, ref),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _shelf(context, ref, books, sort)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Consumer(
              builder: (context, ref, _) => ref.watch(importingProvider)
                  ? LinearProgressIndicator(
                      color: AppColors.terracotta,
                      backgroundColor: AppColors.paperDark,
                      minHeight: 4,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shelf(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Book>> books,
    LibrarySort sort,
  ) {
    return switch (books) {
      AsyncData(:final value) when value.isEmpty => const _EmptyShelf(),
      AsyncData(:final value) => _grid(context, ref, sortBooks(value, sort)),
      AsyncError(:final error) => Center(child: Text('Error: $error')),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _grid(BuildContext context, WidgetRef ref, List<Book> value) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 110),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 26,
        crossAxisSpacing: 20,
        childAspectRatio: 0.5,
      ),
      itemCount: value.length,
      itemBuilder: (context, i) {
        final book = value[i];
        return BookCard(
          key: ValueKey(book.id),
          book: book,
          onOpen: () => _open(context, ref, book),
          onAction: (action) => switch (action) {
            BookAction.highlights => _openNotes(context, ref, book),
            BookAction.rename => _rename(context, ref, book),
            BookAction.delete => _delete(context, ref, book),
          },
        );
      },
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.ink, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      title: const Text('Rename book'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(onPressed: _submit, child: const Text('SAVE')),
      ],
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RetroBox(
              color: AppColors.mustard,
              radius: 40,
              padding: EdgeInsets.all(20),
              child: Icon(
                Icons.auto_stories,
                size: 48,
                color: AppColors.onLight,
              ),
            ),
            const SizedBox(height: 28),
            Text('Your shelf is empty', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Add a PDF to start reading.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
