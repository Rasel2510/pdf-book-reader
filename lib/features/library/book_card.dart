import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/retro_box.dart';
import '../../data/models.dart';

enum BookAction { highlights, rename, delete }

/// One book on the shelf: cover, progress strip, status stamp, title.
class BookCard extends StatelessWidget {
  const BookCard({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onAction,
  });

  final Book book;
  final VoidCallback onOpen;
  final ValueChanged<BookAction> onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 4),
                  child: _Cover(book: book),
                ),
                Positioned(top: 8, right: 12, child: _MenuButton(onAction)),
                Positioned(top: -8, left: -6, child: _Stamp(book: book)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            book.pageCount == 0
                ? 'NOT OPENED'
                : 'PAGE ${book.lastPage} / ${book.pageCount}',
            style: text.bodySmall?.copyWith(
              letterSpacing: 1,
              color: AppColors.ink.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return RetroBox(
      radius: 4,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(book.coverPath),
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, _, _) => _FallbackCover(book: book),
                ),
                // Book spine.
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: ColoredBox(color: Color(0x33000000)),
                ),
              ],
            ),
          ),
          _ProgressStrip(value: book.progress),
        ],
      ),
    );
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.covers[book.id % AppColors.covers.length];
    final onColor = color == AppColors.mustard
        ? AppColors.onLight
        : AppColors.onDark;
    final letter = book.title.isEmpty ? '?' : book.title[0].toUpperCase();

    return ColoredBox(
      color: color,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 3, color: onColor),
            const Spacer(),
            Text(
              letter,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 56,
                height: 1,
                color: onColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              book.title.toUpperCase(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 10,
                letterSpacing: 1,
                color: onColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: const ColoredBox(color: AppColors.terracotta),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final done = book.pageCount > 0 && book.progress >= 1;
    final fresh = book.lastPage <= 1;
    final label = done
        ? 'DONE'
        : fresh
        ? 'NEW'
        : '${(book.progress * 100).round()}%';
    final color = done ? AppColors.teal : AppColors.mustard;

    return Transform.rotate(
      angle: -0.12,
      child: RetroBox(
        color: color,
        radius: 20,
        shadow: 2,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 12,
            color: done ? AppColors.onDark : AppColors.onLight,
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton(this.onAction);

  final ValueChanged<BookAction> onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<BookAction>(
      onSelected: onAction,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: BookAction.highlights,
          child: Text('Highlights & notes'),
        ),
        PopupMenuItem(value: BookAction.rename, child: Text('Rename')),
        PopupMenuItem(value: BookAction.delete, child: Text('Delete')),
      ],
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.ink, width: 2),
        ),
        child: Icon(Icons.more_vert, size: 16, color: AppColors.ink),
      ),
    );
  }
}
