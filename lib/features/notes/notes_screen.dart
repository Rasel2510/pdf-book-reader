import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dictionary_service.dart';
import '../../core/export_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/retro_box.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'notes_providers.dart';

typedef _Entry = ({
  int page,
  String title,
  String? subtitle,
  Color? accent,
  VoidCallback? onDelete,
  VoidCallback? onLookup,
});

/// One extra way to copy a tab's list (shown in the "more" menu).
typedef _CopyOption = ({String label, String Function() text, String message});

/// Pops with a page number when the user taps an item.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key, required this.book, this.onDeleteHighlight});

  final Book book;

  /// Removes a highlight's mark from the open PDF; true if it was found.
  /// Only the reader can do that, so highlights can be deleted here only
  /// when the notes were opened from the reader.
  final Future<bool> Function(Highlight highlight)? onDeleteHighlight;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  @override
  void initState() {
    super.initState();
    // No-op when the reader already loaded this book's bookmarks.
    unawaited(ref.read(bookmarksProvider.notifier).load(widget.book.id));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _lookup(SavedWord word) async {
    final repo = ref.read(repositoryProvider);
    final id = widget.book.id;
    _toast('Looking up “${word.word}”…');

    final meaning = await ref.read(dictionaryProvider).lookup(word.word);
    if (meaning == null) {
      _toast('No meaning found. Check your internet connection.');
      return;
    }
    await repo.setWordMeaning(word.id, meaning);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ref.invalidate(wordsProvider(id));
  }

  Future<void> _deleteHighlight(Highlight highlight) async {
    final removeFromPdf = widget.onDeleteHighlight;
    if (removeFromPdf == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.ink, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        title: const Text('Delete highlight?'),
        content: const Text('It is removed from the list and from the page.'),
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
    if (ok != true) return;

    final repo = ref.read(repositoryProvider);
    final id = widget.book.id;
    var fromPdf = false;
    try {
      fromPdf = await removeFromPdf(highlight);
      await repo.deleteHighlight(highlight.id);
    } catch (error, stackTrace) {
      debugPrint('Could not delete highlight: $error\n$stackTrace');
      _toast('Could not delete the highlight.');
      return;
    }
    if (!mounted) return;
    ref.invalidate(highlightsProvider(id));
    if (!fromPdf) {
      _toast('Removed from the list. The mark may still show on the page.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.book.id;
    final highlights = ref.watch(highlightsProvider(id)).value;
    final words = ref.watch(wordsProvider(id)).value;
    final bookmarks = ref.watch(bookmarksProvider.select((all) => all[id]));
    final canDeleteHighlights = widget.onDeleteHighlight != null;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notes'),
          bottom: TabBar(
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.ink.withValues(alpha: 0.55),
            labelStyle: const TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 14,
              letterSpacing: 1,
            ),
            indicatorColor: AppColors.terracotta,
            indicatorWeight: 4,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'HIGHLIGHTS'),
              Tab(text: 'BOOKMARKS'),
              Tab(text: 'WORDS'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _EntryList(
              empty: 'No highlights yet',
              accent: AppColors.mustard,
              copyUnit: 'highlight',
              copySeparator: '\n\n',
              entries: highlights == null
                  ? null
                  : [
                      for (final h in highlights)
                        (
                          page: h.page,
                          title: h.text,
                          subtitle: null,
                          accent: h.color == null ? null : Color(h.color!),
                          onDelete: canDeleteHighlights
                              ? () => _deleteHighlight(h)
                              : null,
                          onLookup: null,
                        ),
                    ],
            ),
            _EntryList(
              empty: 'No bookmarks yet',
              accent: AppColors.terracotta,
              entries: bookmarks == null
                  ? null
                  : [
                      for (final page in bookmarks.toList()..sort())
                        (
                          page: page,
                          title: 'Page $page',
                          subtitle: null,
                          accent: null,
                          onDelete: () => ref
                              .read(bookmarksProvider.notifier)
                              .remove(id, page),
                          onLookup: null,
                        ),
                    ],
            ),
            _EntryList(
              empty: 'No saved words yet',
              accent: AppColors.teal,
              copyUnit: 'word',
              copyOptions: words == null
                  ? const []
                  : [
                      (
                        label: 'Copy words + meanings',
                        text: () => wordsWithMeanings(words),
                        message: 'Copied words with meanings',
                      ),
                      (
                        label: 'Copy as CSV (word, meaning, page)',
                        text: () => wordsToCsv(words),
                        message: 'Copied CSV',
                      ),
                    ],
              entries: words == null
                  ? null
                  : [
                      for (final w in words)
                        (
                          page: w.page,
                          title: w.word,
                          subtitle: w.meaning,
                          accent: null,
                          onDelete: () async {
                            try {
                              await ref
                                  .read(repositoryProvider)
                                  .deleteWord(w.id);
                            } catch (_) {
                              _toast('Could not delete the word.');
                              return;
                            }
                            if (mounted) ref.invalidate(wordsProvider(id));
                          },
                          onLookup:
                              w.meaning == null &&
                                  DictionaryService.canLookUp(w.word)
                              ? () => _lookup(w)
                              : null,
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.empty,
    required this.entries,
    required this.accent,
    this.copyUnit,
    this.copySeparator = '\n',
    this.copyOptions = const [],
  });

  final String empty;

  /// Null while the first load is running (nothing is drawn, no "empty" flash).
  final List<_Entry>? entries;

  /// Bar color for rows that have no color of their own.
  final Color accent;

  /// Singular name of what a row holds ("word"). Null turns copying off
  /// (bookmarks are only page numbers).
  final String? copyUnit;

  /// Put between rows by "Copy all": one word per line, a blank line
  /// between highlights (they can span several lines).
  final String copySeparator;

  /// Other formats offered next to "Copy all".
  final List<_CopyOption> copyOptions;

  @override
  Widget build(BuildContext context) {
    final items = entries;
    if (items == null) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return Center(child: Text(empty, style: text.bodyMedium));
    }

    final unit = copyUnit;
    final list = ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, i) {
        final e = items[i];

        return RetroBox(
          shadow: 3,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => Navigator.pop(context, e.page),
              onLongPress: unit == null
                  ? null
                  : () => _copy(context, e.title, 'Copied'),
              // Two stacked left borders draw the accent bar and the ink line
              // without IntrinsicHeight (which lays every row out twice).
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: e.accent ?? accent, width: 10),
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AppColors.ink, width: 2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium,
                              ),
                              if (e.subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  e.subtitle!,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                'PAGE ${e.page}',
                                style: text.titleSmall?.copyWith(
                                  fontSize: 12,
                                  color: AppColors.terracotta,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (e.onLookup != null)
                        IconButton(
                          tooltip: 'Look up meaning',
                          icon: const Icon(Icons.manage_search),
                          onPressed: e.onLookup,
                        ),
                      if (unit != null)
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.content_copy, size: 20),
                          onPressed: () => _copy(context, e.title, 'Copied'),
                        ),
                      if (e.onDelete != null)
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: e.onDelete,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (unit == null) return list;

    final count = items.length;
    final label = '$count ${unit.toUpperCase()}${count == 1 ? '' : 'S'}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 23, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: text.bodySmall?.copyWith(letterSpacing: 1.5),
                ),
              ),
              if (copyOptions.isNotEmpty)
                PopupMenuButton<int>(
                  tooltip: 'More ways to copy',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (i) => _copy(
                    context,
                    copyOptions[i].text(),
                    copyOptions[i].message,
                  ),
                  itemBuilder: (_) => [
                    for (var i = 0; i < copyOptions.length; i++)
                      PopupMenuItem(
                        value: i,
                        child: Text(copyOptions[i].label),
                      ),
                  ],
                ),
              RetroButton(
                label: 'Copy all',
                icon: Icons.copy_all,
                onPressed: () => _copy(
                  context,
                  items.map((e) => e.title).join(copySeparator),
                  'Copied $count $unit${count == 1 ? '' : 's'}',
                ),
              ),
            ],
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
  }
}
