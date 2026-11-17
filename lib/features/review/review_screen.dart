import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/retro_box.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/review_schedule.dart';

/// How many saved words are due for review now (shown on the shelf's menu).
final reviewDueProvider = FutureProvider.autoDispose<int>((ref) async {
  final counts = await ref
      .watch(repositoryProvider)
      .reviewCounts(DateTime.now().millisecondsSinceEpoch);
  return counts.due;
});

/// Flashcards over the saved words of every book: the word is shown, the
/// reader recalls its meaning, turns the card and says whether they knew it.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// Most words asked about in one sitting.
  static const _sessionSize = 30;

  late final Repository _repo;

  /// Cards still to answer; the first one is on screen. Null while loading.
  List<ReviewWord>? _queue;
  ReviewCounts? _counts;
  int _sessionTotal = 0;
  int _known = 0;
  bool _shown = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(repositoryProvider);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final words = await _repo.wordsToReview(now, limit: _sessionSize);
      final counts = await _repo.reviewCounts(now);
      if (!mounted) return;
      setState(() {
        _queue = words;
        _counts = counts;
        _sessionTotal = words.length;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load words to review: $error\n$stackTrace');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _answer({required bool knew}) async {
    final queue = _queue;
    if (queue == null || queue.isEmpty) return;
    final word = queue.first;
    final next = nextReview(box: word.box, knew: knew, now: DateTime.now());

    setState(() {
      queue.removeAt(0);
      if (knew) {
        _known++;
      } else {
        // Comes round again before the sitting ends.
        queue.add(word.inBox(next.box));
      }
      _shown = false;
    });

    try {
      await _repo.setWordReview(word.id, box: next.box, due: next.due);
    } catch (error, stackTrace) {
      // The card moved on; the word just stays due and is asked again.
      debugPrint('Could not save a review answer: $error\n$stackTrace');
    }
    if (mounted) ref.invalidate(reviewDueProvider);
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;

    return Scaffold(
      appBar: AppBar(title: const Text('Word review')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _failed
              ? const _Message(
                  icon: Icons.error_outline,
                  title: 'Could not load your words',
                  text: 'Close this screen and try again.',
                )
              : queue == null
              ? const SizedBox.shrink()
              : queue.isNotEmpty
              ? _session(context, queue)
              : _sessionTotal > 0
              ? _Message(
                  icon: Icons.emoji_events_outlined,
                  title: 'Done for now',
                  text: _known == 1
                      ? 'You went through 1 word.'
                      : 'You went through $_known words.',
                  action: 'Back to the shelf',
                  onAction: () => Navigator.pop(context),
                )
              : _nothingDue(_counts),
        ),
      ),
    );
  }

  Widget _nothingDue(ReviewCounts? counts) {
    final resting = counts?.resting ?? 0;
    final nextDue = counts?.nextDue;
    if (resting > 0 && nextDue != null) {
      final when = dueLabel(nextDue, DateTime.now());
      return _Message(
        icon: Icons.check_circle_outline,
        title: 'All caught up',
        text: resting == 1
            ? 'Your word comes back $when.'
            : 'Your $resting words are resting. '
                  'The next one comes back $when.',
      );
    }
    final unexplained = counts?.withoutMeaning ?? 0;
    return _Message(
      icon: Icons.style_outlined,
      title: 'No words to review yet',
      text: unexplained > 0
          ? 'Your saved words have no meaning yet. Open a book\'s notes '
                'and look them up (this needs internet).'
          : 'Long-press a word while reading and save it. It will be '
                'waiting for you here.',
    );
  }

  Widget _session(BuildContext context, List<ReviewWord> queue) {
    final text = Theme.of(context).textTheme;
    final word = queue.first;
    final done = _sessionTotal - queue.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$_known OF $_sessionTotal KNOWN',
          style: text.bodySmall?.copyWith(letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: _sessionTotal == 0
                ? 0
                : done.clamp(0, _sessionTotal) / _sessionTotal,
            minHeight: 6,
            color: AppColors.terracotta,
            backgroundColor: AppColors.paperDark,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: RetroBox(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _shown ? null : () => setState(() => _shown = true),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        word.word,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 34,
                          height: 1.15,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${word.bookTitle} · page ${word.page}',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.ink.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_shown)
                        Flexible(
                          child: SingleChildScrollView(
                            child: Text(
                              word.meaning,
                              textAlign: TextAlign.center,
                              style: text.bodyLarge?.copyWith(height: 1.45),
                            ),
                          ),
                        )
                      else
                        Text(
                          'Think of the meaning, then tap the card.',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.ink.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_shown)
          Row(
            children: [
              Expanded(
                child: RetroButton(
                  label: 'Not yet',
                  icon: Icons.replay,
                  color: AppColors.terracotta,
                  foreground: AppColors.onDark,
                  onPressed: () => _answer(knew: false),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: RetroButton(
                  label: 'I knew it',
                  icon: Icons.check,
                  color: AppColors.teal,
                  foreground: AppColors.onDark,
                  onPressed: () => _answer(knew: true),
                ),
              ),
            ],
          )
        else
          RetroButton(
            label: 'Show meaning',
            icon: Icons.visibility_outlined,
            onPressed: () => setState(() => _shown = true),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RetroBox(
            color: AppColors.mustard,
            radius: 40,
            padding: const EdgeInsets.all(20),
            child: Icon(icon, size: 48, color: AppColors.onLight),
          ),
          const SizedBox(height: 28),
          Text(title, textAlign: TextAlign.center, style: style.titleLarge),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: style.bodyMedium),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 24),
            RetroButton(label: action!, onPressed: onAction!),
          ],
        ],
      ),
    );
  }
}
