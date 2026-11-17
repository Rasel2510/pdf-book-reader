import 'package:flutter/material.dart';

/// One line of a PDF's table of contents (its bookmark tree, flattened).
final class TocEntry {
  const TocEntry({
    required this.title,
    required this.depth,
    required this.bookmark,
    this.pageNumber,
  });

  final String title;
  final int depth;
  final int? pageNumber;

  /// The viewer's own bookmark object, handed back to it to jump.
  final Object bookmark;
}

TocEntry? chapterForPage(List<TocEntry> entries, int page) {
  TocEntry? chapter;
  for (final entry in entries) {
    final entryPage = entry.pageNumber;
    if (entryPage == null || entryPage > page) continue;
    final currentPage = chapter?.pageNumber ?? 0;
    if (entryPage > currentPage ||
        (entryPage == currentPage && entry.depth > chapter!.depth)) {
      chapter = entry;
    }
  }
  return chapter;
}

/// Flattens the bookmark tree of a loaded PDF document. Returns an empty
/// list for PDFs without one (and for anything unexpected: the contents list
/// is a convenience and must never break reading).
///
/// [document] is typed `dynamic` on purpose: only `bookmarks`, `count`,
/// `[]`, `title`, destinations and pages are used, and the tree is walked
/// defensively.
List<TocEntry> readToc(dynamic document) {
  const maxEntries = 3000;
  final out = <TocEntry>[];

  void walk(dynamic node, int depth) {
    final count = node.count as int;
    for (var i = 0; i < count && out.length < maxEntries; i++) {
      final item = node[i];
      final title = (item.title as String).trim();
      if (title.isNotEmpty) {
        int? pageNumber;
        try {
          final destination =
              item.destination ?? item.namedDestination?.destination;
          final page = destination?.page;
          final pageIndex = page == null
              ? -1
              : document.pages.indexOf(page) as int;
          if (pageIndex >= 0) pageNumber = pageIndex + 1;
        } catch (_) {}
        out.add(
          TocEntry(
            title: title,
            depth: depth,
            bookmark: item as Object,
            pageNumber: pageNumber,
          ),
        );
      }
      walk(item, depth + 1);
    }
  }

  try {
    walk(document.bookmarks, 0);
  } catch (_) {
    return const [];
  }
  return out;
}

Future<TocEntry?> showContentsSheet(
  BuildContext context,
  List<TocEntry> entries,
) {
  final text = Theme.of(context).textTheme;

  return showModalBottomSheet<TocEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Contents', style: text.titleLarge),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return InkWell(
                  onTap: () => Navigator.pop(context, e),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24 + 18.0 * e.depth.clamp(0, 5),
                      10,
                      24,
                      10,
                    ),
                    child: Text(
                      e.title,
                      style: e.depth == 0 ? text.titleSmall : text.bodyMedium,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
