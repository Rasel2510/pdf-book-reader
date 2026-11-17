import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_core/theme.dart'
    show SfPdfViewerTheme, SfPdfViewerThemeData;
import 'package:syncfusion_flutter_pdf/pdf.dart'
    show PdfDocument, PdfTextExtractor, TextLine;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
// The line-by-line bounds of a mark are not part of the public API.
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdfviewer/src/annotation/text_markup.dart'
    show
        HighlightAnnotationExtension,
        SquigglyAnnotationExtension,
        StrikethroughAnnotationExtension,
        UnderlineAnnotationExtension;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/dictionary_service.dart';
import '../../core/file_utils.dart';
import '../../core/page_render_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/highlight_colors.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../library/library_controller.dart';
import '../notes/notes_providers.dart';
import '../notes/notes_screen.dart';
import 'flip_controller.dart';
import 'flip_pager.dart';
import 'go_to_page_sheet.dart';
import 'selection_bar.dart';
import 'toc.dart';
import '../settings/keep_awake_controller.dart';
import '../settings/page_tint_controller.dart';
import '../settings/page_turn_controller.dart';
import '../settings/reading_settings_sheet.dart';

enum _ReaderMenu { contents, goToPage, saveAnnotatedPdf, settings }

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.book, this.startPage});

  final Book book;

  /// Overrides the saved page (e.g. when opened from a highlight).
  final int? startPage;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

/// Rebuild rules for this screen (this is what keeps page turns smooth):
/// `build` runs only when the page color or the turn style changes. Things
/// that change while reading (current page, bookmark icon, text selection,
/// unsaved edits) live in small listenables that rebuild only the widget
/// that shows them, never the PDF viewer.
class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _progressDelay = Duration(milliseconds: 700);
  static const _docSaveDelay = Duration(seconds: 3);
  static const _selectionClearDelay = Duration(milliseconds: 150);

  final _viewerKey = GlobalKey<SfPdfViewerState>();
  final _boundaryKey = GlobalKey();
  final _controller = PdfViewerController();

  // Read once: using `ref` after dispose throws in Riverpod 3.
  late final Repository _repo;
  late final LibraryController _library;
  late final DictionaryService _dictionary;
  late final PageRenderService _render;
  late final FlipController _flip;
  late final File _file;

  late final ValueNotifier<int> _pageN;
  final _pageCountDisplay = ValueNotifier<int>(0);
  final _zoomLevel = ValueNotifier<double>(1);
  final _selected = ValueNotifier<String?>(null);
  final _highlightColor = ValueNotifier<Color>(highlightColors.first);
  Timer? _selectionClearTimer;
  String? _lastSelectionText;
  int? _lastSelectionPage;
  bool _addingHighlightFromBar = false;

  // Search: the app bar turns into a search field while open.
  final _searchOpen = ValueNotifier<bool>(false);
  final _searchField = TextEditingController();
  final _searchResult = ValueNotifier<PdfTextSearchResult?>(null);

  // Reading mode: a tap in the middle of the page hides every bar, the next
  // tap brings them back. The bars float over the page, so the page never
  // changes size (no re-render).
  final _chrome = ValueNotifier<bool>(true);
  Offset? _tapStart;
  DateTime _tapTime = DateTime.now();
  bool _tapHadSelection = false;
  int _pointers = 0;
  bool _flipPinching = false;
  bool _flipDragActive = false;

  // One finger on a zoomed page: where the page was panned to when the
  // finger went down, and how fast the finger moves.
  double? _zoomedPanStart;
  VelocityTracker? _zoomedPanSpeed;
  double _flipPinchStartZoom = 1;
  Timer? _chromeTimer;

  List<TocEntry> _toc = const [];

  // Reading log, written together with the page progress.
  DateTime _lastActivity = DateTime.now();
  int _pendingPages = 0;
  int _pendingSeconds = 0;

  /// True while highlights are in the viewer but not yet written to the file.
  final _unsavedEdits = ValueNotifier<bool>(false);
  int _editCount = 0;
  Future<void>? _docSave;

  int _pageCount = 0;
  late int _savedPage;
  bool _restored = false;
  bool _flipping = false;
  bool _leaving = false;
  bool _loadFailed = false;

  Timer? _progressTimer;
  Timer? _docTimer;

  // The viewer widget is built once per turn style. Handing Flutter the same
  // instance again skips the element update, so rebuilds above it are free.
  Widget? _viewer;
  bool? _viewerIsFlip;

  Book get _book => widget.book;
  int get _page => _pageN.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo = ref.read(repositoryProvider);
    _library = ref.read(libraryProvider.notifier);
    _dictionary = ref.read(dictionaryProvider);
    _controller.annotationSettings.highlight
      ..color = highlightColors.first
      ..opacity = 1;
    unawaited(_applyWakelock(ref.read(keepAwakeProvider)));
    unawaited(ref.read(bookmarksProvider.notifier).load(_book.id));
    _file = File(_book.filePath);
    _savedPage = _book.lastPage;
    _pageN = ValueNotifier(widget.startPage ?? _book.lastPage);

    _render = PageRenderService(_book.filePath, marksFor: _marksFor)
      ..setTint(ref.read(pageTintProvider).filter);
    _flip = FlipController(
      vsync: this,
      boundaryKey: _boundaryKey,
      pixelRatio: () => MediaQuery.devicePixelRatioOf(context),
      currentPage: () => _page,
      pageCount: () => _pageCount,
      jumpTo: _jumpTo,
      prepareNeighborImage: _render.prepare,
      onFlipStart: () => _flipping = true,
      onFlipReveal: _onFlipReveal,
      onFlipEnd: _onFlipEnd,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _docTimer?.cancel();
    _selectionClearTimer?.cancel();
    _chromeTimer?.cancel();
    unawaited(_flushProgress());
    unawaited(_applyWakelock(false));
    _clearSearchResult();
    _flip.dispose();
    unawaited(_render.dispose());
    _controller.dispose();
    _pageN.dispose();
    _pageCountDisplay.dispose();
    _zoomLevel.dispose();
    _selected.dispose();
    _highlightColor.dispose();
    _searchOpen.dispose();
    _chrome.dispose();
    _searchField.dispose();
    _searchResult.dispose();
    _unsavedEdits.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS may kill the app in the background: write what is pending now.
    // (`inactive` also fires for a pulled-down shade; not worth a save.)
    if (state == AppLifecycleState.resumed) {
      _lastActivity = DateTime.now(); // time away is not reading time
      return;
    }
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    unawaited(_flushProgress());
    unawaited(_saveDocument());
  }

  void _setChrome(bool show) {
    if (_chrome.value == show) return;
    // Keep OS bars visible so Android does not resize the reader on a toggle.
    _chrome.value = show;
  }

  // A tap is one short press that barely moves. Watched with a Listener, so
  // it never competes with the viewer's own gestures (scroll, zoom, select).
  // A second finger (pinch) cancels it.
  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers > 1) {
      _tapStart = null;
      _zoomedPanStart = null;
      _zoomedPanSpeed = null;
      return;
    }
    if (_controller.zoomLevel > 1) {
      _zoomedPanStart = _controller.scrollOffset.dx;
      _zoomedPanSpeed = VelocityTracker.withKind(e.kind)
        ..addPosition(e.timeStamp, e.position);
    }
    _tapStart = e.position;
    _tapTime = DateTime.now();
    _tapHadSelection = _selected.value != null;
  }

  void _onPointerMove(PointerMoveEvent e) {
    _zoomedPanSpeed?.addPosition(e.timeStamp, e.position);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers = (_pointers - 1).clamp(0, 99);
    _tapStart = null;
    _zoomedPanStart = null;
    _zoomedPanSpeed = null;
  }

  /// The viewer does not always report a zoom change (it silently goes back
  /// to 1 when the page changes), so its real zoom is read after anything
  /// that can change it. The page-turn layer is on only at zoom 1.
  void _syncZoom() {
    if (!mounted || _flipPinching) return;
    _zoomLevel.value = _controller.zoomLevel;
  }

  /// On a zoomed page a swipe pans. Only a quick sideways swipe that starts
  /// with the page already at that edge turns the page. The viewer would do
  /// that itself with a plain slide; this starts the real turn first, which
  /// covers it.
  void _turnFromZoomedSwipe() {
    final start = _zoomedPanStart;
    final speed = _zoomedPanSpeed;
    _zoomedPanStart = null;
    _zoomedPanSpeed = null;
    if (start == null || speed == null) return;
    if (_controller.zoomLevel <= 1 || _selected.value != null) return;
    if (_searchOpen.value || _pageCount == 0) return;

    final velocity = speed.getVelocity().pixelsPerSecond;
    final atEdge = (_controller.scrollOffset.dx - start).abs() < 1;
    if (!atEdge || velocity.dx.abs() < 600 || velocity.dy.abs() > 800) return;

    _flip.invalidate(); // the capture from touch-down shows the old position
    unawaited(_flip.turn(forward: velocity.dx < 0));
  }

  void _onPointerUp(PointerUpEvent e, double width, bool flip) {
    _pointers = (_pointers - 1).clamp(0, 99);
    _turnFromZoomedSwipe();
    _syncZoom();
    final start = _tapStart;
    _tapStart = null;
    if (start == null || _tapHadSelection || _selected.value != null) return;
    if ((e.position - start).distance > 18) return;
    if (DateTime.now().difference(_tapTime).inMilliseconds > 250) return;
    if (_searchOpen.value) return;

    if (flip) {
      // Side zones turn pages (FlipPager); only the middle toggles.
      final x = e.localPosition.dx;
      if (x < width * 0.28 || x > width * 0.72) return;
      _setChrome(!_chrome.value);
      return;
    }
    // Scroll mode has double-tap zoom: wait briefly so a double tap zooms
    // without flashing the bars, and a second tap cancels the toggle.
    if (_chromeTimer?.isActive ?? false) {
      _chromeTimer!.cancel();
      return;
    }
    _chromeTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _setChrome(!_chrome.value);
    });
  }

  Future<void> _applyWakelock(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Keeping the screen awake is a nicety; never let it break reading.
    }
  }

  // Reading log. A turn to a page 1-3 ahead counts as pages read (bigger
  // jumps are navigation). The time since the previous turn counts up to two
  // minutes, so a book left open on a table does not add hours.

  void _trackTurn(int from, int to) {
    final now = DateTime.now();
    _pendingSeconds += now.difference(_lastActivity).inSeconds.clamp(0, 120);
    _lastActivity = now;
    if (to > from && to - from <= 3) _pendingPages += to - from;
  }

  Future<void> _flushStats() async {
    final now = DateTime.now();
    _pendingSeconds += now.difference(_lastActivity).inSeconds.clamp(0, 120);
    _lastActivity = now;

    final pages = _pendingPages;
    final seconds = _pendingSeconds;
    if (pages == 0 && seconds == 0) return;
    _pendingPages = 0;
    _pendingSeconds = 0;
    await _repo.logReading(_book.id, pages, seconds);
  }

  // Progress is written once the reader stops turning pages, not on every
  // page: a quick flick through 30 pages costs one write.

  void _scheduleProgress() {
    _progressTimer?.cancel();
    _progressTimer = Timer(_progressDelay, () => unawaited(_flushProgress()));
  }

  Future<void> _flushProgress() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    unawaited(_flushStats());
    final page = _page;
    if (page == _savedPage) return;
    _savedPage = page;
    await _repo.saveProgress(_book.id, page);
  }

  /// The highlights and other marks the viewer has on [page], for the
  /// pre-rendered bitmaps (the platform renderer does not draw them).
  List<PageMark> _marksFor(int page) {
    final marks = <PageMark>[];
    for (final annotation in _controller.getAnnotations()) {
      if (annotation.pageNumber != page) continue;
      final (rects, kind) = switch (annotation) {
        HighlightAnnotation() => (
          annotation.textMarkupRects,
          PageMarkKind.highlight,
        ),
        UnderlineAnnotation() => (
          annotation.textMarkupRects,
          PageMarkKind.underline,
        ),
        SquigglyAnnotation() => (
          annotation.textMarkupRects,
          PageMarkKind.underline,
        ),
        StrikethroughAnnotation() => (
          annotation.textMarkupRects,
          PageMarkKind.strikethrough,
        ),
        _ => (const <Rect>[], PageMarkKind.highlight),
      };
      final color = annotation.color.withValues(alpha: annotation.opacity);
      for (final rect in rects) {
        marks.add((rect: rect, color: color, kind: kind));
      }
    }
    return marks;
  }

  /// Pre-render the pages around the current one; a turn draws them.
  void _prefetch() {
    if (!mounted || _pageCount == 0) return;
    unawaited(_render.focus(_page));
  }

  Future<void> _onLoaded(PdfDocumentLoadedDetails d) async {
    _pageCount = d.document.pages.count;
    _pageCountDisplay.value = _pageCount;
    _toc = readToc(d.document);
    if (_pageCount != _book.pageCount) {
      unawaited(_repo.savePageCount(_book.id, _pageCount));
    }
    if (_page > 1) _controller.jumpToPage(_page);
    // Ignore page-change events fired while restoring the saved page.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _restored = true;
    _lastActivity = DateTime.now();
    if (widget.startPage != null) _scheduleProgress();
    _replaceRetiredHighlightColors();
    unawaited(_adoptPdfHighlights(d.document));
    _prefetch();
  }

  /// Highlights in colors the app no longer offers get the color that
  /// replaced them: on the page, in the saved PDF and in Notes. A convenience
  /// that must never get in the way of reading.
  void _replaceRetiredHighlightColors() {
    try {
      var recolored = false;
      final highlights = _controller
          .getAnnotations()
          .whereType<HighlightAnnotation>();
      for (final highlight in highlights) {
        final next = replacementForHighlightColor(highlight.color.toARGB32());
        if (next == null || highlight.isLocked) continue;
        highlight.color = Color(next);
        recolored = true;
      }
      if (recolored) _markEdited(_page);
    } catch (error, stackTrace) {
      debugPrint('Could not recolor highlights: $error\n$stackTrace');
    }
    unawaited(_recolorHighlightRecords());
  }

  Future<void> _recolorHighlightRecords() async {
    try {
      final replacements = <int, int>{};
      for (final row in await _repo.highlights(_book.id)) {
        final color = row.color;
        final next = color == null ? null : replacementForHighlightColor(color);
        if (color != null && next != null) replacements[color] = next;
      }
      var changed = 0;
      for (final MapEntry(key: from, value: to) in replacements.entries) {
        changed += await _repo.recolorHighlights(_book.id, from, to);
      }
      if (changed > 0 && mounted) ref.invalidate(highlightsProvider(_book.id));
    } on Exception catch (error, stackTrace) {
      debugPrint('Could not recolor highlight records: $error\n$stackTrace');
    }
  }

  void _onLoadFailed(PdfDocumentLoadFailedDetails d) {
    if (_loadFailed) return;
    _loadFailed = true;
    // The viewer can report this while it is building: leave after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _toast('Could not open this PDF. ${d.description}', seconds: 3);
      Navigator.pop(context);
    });
  }

  void _onPageChanged(PdfPageChangedDetails d) {
    if (!_restored || _flipping) return;
    _trackTurn(_page, d.newPageNumber);
    _pageN.value = d.newPageNumber;
    _syncZoom();
    _flip.invalidate();
    _prefetch();
    _scheduleProgress();
  }

  void _onZoomLevelChanged(PdfZoomDetails details) {
    if (!_flipPinching) _zoomLevel.value = details.newZoomLevel;
  }

  void _onFlipScaleStart(ScaleStartDetails _) {
    _flipPinching = false;
    _flipDragActive = false;
  }

  void _onFlipScaleUpdate(ScaleUpdateDetails details, Size size) {
    if (details.pointerCount > 1) {
      if (!_flipPinching) {
        _flipPinching = true;
        _flipPinchStartZoom = _controller.zoomLevel;
        if (_flipDragActive) _flip.abort();
        _flipDragActive = false;
      }
      _controller.zoomLevel = (_flipPinchStartZoom * details.scale)
          .clamp(1.0, 3.0)
          .toDouble();
      return;
    }

    final delta = details.focalPointDelta;
    if (!_flipDragActive && delta.dx.abs() > delta.dy.abs()) {
      _flipDragActive = true;
      _flip.dragStart(
        grabY: size.height > 0 ? details.localFocalPoint.dy / size.height : 0.5,
      );
    }
    if (_flipDragActive) {
      unawaited(
        _flip.dragUpdate(
          delta.dx,
          size.width,
          dy: delta.dy,
          height: size.height,
        ),
      );
    }
  }

  void _onFlipScaleEnd(ScaleEndDetails details) {
    if (_flipPinching) {
      _flipPinching = false;
      _zoomLevel.value = _controller.zoomLevel;
    } else if (_flipDragActive) {
      _flip.dragEnd(details.velocity.pixelsPerSecond.dx);
    }
    _flipDragActive = false;
  }

  void _toggleZoom() {
    _controller.zoomLevel = _controller.zoomLevel > 1 ? 1 : 2;
    _syncZoom();
  }

  /// Moves the viewer only. The page number stays on the page the flip
  /// started from until [_onFlipEnd] says where the turn ended (a cancelled
  /// turn would otherwise leave it on the wrong page for a moment).
  void _jumpTo(int page) => _controller.jumpToPage(page);

  /// A jump that is not a page turn (go to page, notes): the page a turn
  /// may still be holding on screen is no longer the one to show.
  void _goTo(int page) {
    _flip.dropCover();
    _controller.jumpToPage(page);
  }

  void _onFlipEnd(int turnedTo) {
    _flipping = false;
    // Page changes are muted during a turn. If the viewer was sent somewhere
    // else meanwhile, the page it is on now is the truth.
    final shown = _controller.pageNumber;
    final page = shown >= 1 && shown <= _pageCount ? shown : turnedTo;
    if (_page != page) _trackTurn(_page, page);
    _pageN.value = page;
    _syncZoom();
    _flip.invalidate();
    _prefetch();
    _scheduleProgress();
  }

  /// The turn is done and its page is on screen (still as a bitmap; the
  /// viewer catches up and then [_onFlipEnd] runs). Get the pages around it
  /// ready now, so the next turn can start at once.
  void _onFlipReveal(int page) {
    if (_page != page) _trackTurn(_page, page);
    _pageN.value = page;
    _syncZoom(); // a turn from a zoomed page lands at zoom 1
    _prefetch();
    _scheduleProgress();
  }

  /// Switching style re-lays out the viewer, which fires page-change events
  /// (usually page 1). Remember the page first, mute the events, jump back.
  void _onTurnStyleChanged(bool flip) {
    if (_pageCount == 0) return; // not loaded yet; viewer opens on the page
    final page = _page;
    _restored = false;
    _flip.abort();
    _flip.invalidate();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (flip) _controller.zoomLevel = 1; // flip mode has no zoom
      _controller.jumpToPage(page);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _pageN.value = page;
      _restored = true;
      _prefetch();
    });
  }

  /// Pre-rendered pages are sized to the viewport.
  void _onViewportChanged(Size size, double pixelRatio) {
    if (!_render.configure(size, pixelRatio)) return;
    _flip.invalidate();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch());
  }

  void _toggleBookmark() {
    unawaited(ref.read(bookmarksProvider.notifier).toggle(_book.id, _page));
  }

  void _onSelection(PdfTextSelectionChangedDetails d) {
    final text = d.selectedText?.trim();
    final value = (text == null || text.isEmpty) ? null : text;
    _selectionClearTimer?.cancel();
    if (value == null) {
      if (_selected.value != null) {
        _selectionClearTimer = Timer(_selectionClearDelay, () {
          _selected.value = null;
          _lastSelectionText = null;
          _lastSelectionPage = null;
        });
      }
      return;
    }

    _selected.value = value;
    _lastSelectionText = value;
    final lines = _viewerKey.currentState?.getSelectedTextLines();
    _lastSelectionPage = lines?.isNotEmpty == true
        ? lines!.first.pageNumber
        : _page;
    _flip.abort();
  }

  void _clearSelection() {
    _selectionClearTimer?.cancel();
    _selected.value = null;
    _lastSelectionText = null;
    _lastSelectionPage = null;
    _controller.clearSelection();
  }

  void _onAnnotationAdded(Annotation annotation) {
    if (_addingHighlightFromBar || annotation is! HighlightAnnotation) return;
    final text = _lastSelectionText;
    final page = _lastSelectionPage;
    if (text == null || page == null || page != annotation.pageNumber) return;

    final annotationMarker = _newHighlightAnnotationMarker();
    annotation.subject = annotationMarker;
    _lastSelectionText = null;
    _lastSelectionPage = null;
    _markEdited(page);
    unawaited(
      _saveHighlightRecord(
        page,
        text,
        color: annotation.color,
        annotationMarker: annotationMarker,
      ),
    );
  }

  Future<void> _copySelection() async {
    final text = _selected.value;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    _clearSelection();
    _toast('Copied');
  }

  Future<void> _highlight() async {
    final text = _selected.value;
    final lines = _viewerKey.currentState?.getSelectedTextLines();
    if (text == null || lines == null || lines.isEmpty) return;

    final page = lines.first.pageNumber;
    final color = _highlightColor.value;
    final annotationMarker = _newHighlightAnnotationMarker();
    final annotation = HighlightAnnotation(textBoundsCollection: lines);
    annotation
      ..color = color
      ..opacity = 1
      ..subject = annotationMarker;
    _addingHighlightFromBar = true;
    try {
      _controller.addAnnotation(annotation);
    } finally {
      _addingHighlightFromBar = false;
    }
    _clearSelection();
    _markEdited(page);
    await _saveHighlightRecord(
      page,
      text,
      color: color,
      annotationMarker: annotationMarker,
    );
  }

  static const _markerPrefix = 'Paperleaf Reader highlight ';

  String _newHighlightAnnotationMarker() =>
      '$_markerPrefix${_book.id}-'
      '${DateTime.now().microsecondsSinceEpoch}';

  /// Highlights that are in the PDF but not in Notes get a Notes entry: the
  /// ones made in another app, and the app's own after its data was lost
  /// (the marks live in the PDF, the list does not). The words are read
  /// from the page under each mark.
  ///
  /// A mark and its entry are tied together by a tag in the PDF. Opening the
  /// book again must not add the same marks again, also when a tag did not
  /// reach the file (the app was closed before the save): an untagged mark
  /// first looks for an entry with the same words on its page whose own mark
  /// is missing, and takes that one over.
  Future<void> _adoptPdfHighlights(PdfDocument document) async {
    try {
      final rows = await _repo.highlights(_book.id);
      if (!mounted) return;
      final marks = _controller
          .getAnnotations()
          .whereType<HighlightAnnotation>()
          .toList();
      bool isTagged(HighlightAnnotation mark) =>
          mark.subject?.startsWith(_markerPrefix) ?? false;

      final tagsInPdf = {for (final mark in marks) ?mark.subject};
      final tagsInNotes = {for (final row in rows) ?row.annotationMarker};
      // Entries from before marks were tagged cannot be told apart from
      // untagged marks on the same page: leave those pages alone.
      final untaggedPages = {
        for (final row in rows)
          if (row.annotationMarker == null) row.page,
      };
      // Entries whose mark is not in the PDF under their tag, by page.
      final orphans = <int, List<Highlight>>{};
      for (final row in rows) {
        final tag = row.annotationMarker;
        if (tag != null && !tagsInPdf.contains(tag)) {
          (orphans[row.page] ??= []).add(row);
        }
      }

      final missing = [
        for (final mark in marks)
          if (isTagged(mark)
              ? !tagsInNotes.contains(mark.subject)
              : !untaggedPages.contains(mark.pageNumber) && !mark.isLocked)
            mark,
      ];
      if (missing.isEmpty) return;

      final extractor = PdfTextExtractor(document);
      final linesOfPage = <int, List<TextLine>>{};
      final takenOver = <int>{}; // ids of entries
      var added = 0;
      var retagged = false;
      for (final mark in missing) {
        if (!mounted) return;
        final page = mark.pageNumber;
        final lines = linesOfPage[page] ??= extractor.extractTextLines(
          startPageIndex: page - 1,
          endPageIndex: page - 1,
        );
        final words = _wordsUnder(mark.textMarkupRects, lines);
        final text = words.isEmpty ? 'Highlight on page $page' : words;

        var tag = mark.subject;
        if (!isTagged(mark)) {
          Highlight? entry;
          for (final row in orphans[page] ?? const <Highlight>[]) {
            if (!takenOver.contains(row.id) && _sameWords(row.text, text)) {
              entry = row;
              break;
            }
          }
          tag =
              entry?.annotationMarker ??
              '${_newHighlightAnnotationMarker()}-$added';
          // If the tag cannot be put on the mark, the entry is still made:
          // next time the mark finds it by its words.
          if (_tag(mark, tag)) retagged = true;
          if (entry != null) {
            takenOver.add(entry.id);
            continue;
          }
        }
        await _repo.addHighlight(
          _book.id,
          page,
          text,
          color: mark.color.toARGB32(),
          annotationMarker: tag,
        );
        added++;
        // Reading a page's text is slow: let a frame through between marks.
        await Future<void>.delayed(Duration.zero);
      }

      // An entry without a mark that says the same as one that has its mark
      // (same page) is a copy of it.
      var removed = 0;
      for (final onPage in orphans.values) {
        final kept = onPage.where((row) => takenOver.contains(row.id)).toList();
        for (final row in onPage) {
          if (takenOver.contains(row.id)) continue;
          if (kept.any((other) => _sameWords(other.text, row.text))) {
            await _repo.deleteHighlight(row.id);
            removed++;
          }
        }
      }

      if (!mounted) return;
      if (retagged) _markEdited(_page);
      if (added > 0 || removed > 0) {
        ref.invalidate(highlightsProvider(_book.id));
      }
    } catch (error, stackTrace) {
      debugPrint('Could not read highlights from the PDF: $error\n$stackTrace');
    }
  }

  static final _spaces = RegExp(r'\s+');

  static bool _sameWords(String a, String b) =>
      a.replaceAll(_spaces, '') == b.replaceAll(_spaces, '');

  /// Puts [tag] on a mark that came with the PDF. The viewer writes a tag
  /// into the file only for marks it created itself, so the mark is replaced
  /// by an identical new one. The new one is added first: if anything fails
  /// the page keeps its mark. Returns whether the mark now carries the tag.
  bool _tag(HighlightAnnotation mark, String tag) {
    if (mark.isLocked) return false;
    try {
      final copy =
          HighlightAnnotation(
              textBoundsCollection: [
                for (final rect in mark.textMarkupRects)
                  PdfTextLine(rect, '', mark.pageNumber),
              ],
            )
            ..color = mark.color
            ..opacity = mark.opacity.clamp(0.0, 1.0).toDouble()
            ..subject = tag;

      _addingHighlightFromBar = true; // not a highlight the reader just made
      try {
        _controller.addAnnotation(copy);
      } finally {
        _addingHighlightFromBar = false;
      }
      if (!_controller.getAnnotations().contains(copy)) return false;

      _controller.removeAnnotation(mark);
      if (_controller.getAnnotations().contains(mark)) {
        _controller.removeAnnotation(copy); // keep one mark, the old one
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The words of [lines] that lie under the mark's [rects], in reading
  /// order.
  static String _wordsUnder(List<Rect> rects, List<TextLine> lines) {
    final out = StringBuffer();
    for (final line in lines) {
      if (!rects.any((rect) => rect.inflate(2).overlaps(line.bounds))) continue;
      Rect? previous;
      for (final word in line.wordCollection) {
        final text = word.text.trim();
        if (text.isEmpty) continue;
        final bounds = word.bounds;
        if (!rects.any((rect) => rect.inflate(1.5).contains(bounds.center))) {
          continue;
        }
        // A PDF can store one word in pieces ("s" + "tartled"). Pieces that
        // touch belong together; a real space is wider than this.
        final touching =
            previous != null &&
            bounds.left - previous.right < bounds.height * 0.12;
        if (out.isNotEmpty && !touching) out.write(' ');
        out.write(text);
        previous = bounds;
      }
    }
    return out.toString();
  }

  Future<void> _saveHighlightRecord(
    int page,
    String text, {
    required Color color,
    required String annotationMarker,
  }) async {
    try {
      await _repo.addHighlight(
        _book.id,
        page,
        text,
        color: color.toARGB32(),
        annotationMarker: annotationMarker,
      );
    } on Exception catch (error, stackTrace) {
      debugPrint('Could not save highlight: $error\n$stackTrace');
      _toast('Highlight added to the page, but could not be saved to Notes.');
      return;
    }
    if (!mounted) return;
    ref.invalidate(highlightsProvider(_book.id));
    _toast('Highlight saved');
  }

  /// The page is edited in the viewer: captures and pre-rendered bitmaps of
  /// it lack the change until the file is saved. Rewriting the PDF is the
  /// slow part (large files take seconds), so it waits until the reader
  /// pauses instead of running per edit.
  void _markEdited(int page) {
    _flip.invalidate();
    _render.marksChanged();
    _prefetch();
    _editCount++;
    _unsavedEdits.value = true;
    _docTimer?.cancel();
    _docTimer = Timer(_docSaveDelay, () => unawaited(_saveDocument()));
  }

  /// Removes one highlight's mark from the open PDF (called by the Notes
  /// screen). New marks are matched by their PDF annotation subject. Older marks
  /// can be removed only when their page and color identify one untagged mark.
  Future<bool> _removeHighlight(Highlight highlight) async {
    final annotations = _controller
        .getAnnotations()
        .whereType<HighlightAnnotation>()
        .where((annotation) => annotation.pageNumber == highlight.page)
        .toList();
    HighlightAnnotation? target;
    if (highlight.annotationMarker != null) {
      for (final annotation in annotations) {
        if (annotation.subject == highlight.annotationMarker) {
          target = annotation;
          break;
        }
      }
    } else {
      final legacyRows = (await _repo.highlights(_book.id))
          .where(
            (row) =>
                row.page == highlight.page &&
                row.annotationMarker == null &&
                (highlight.color == null || row.color == highlight.color),
          )
          .toList();
      final candidates = annotations.where((annotation) {
        final untagged =
            annotation.subject == null || annotation.subject!.isEmpty;
        final sameColor =
            highlight.color == null ||
            annotation.color.toARGB32() == highlight.color;
        return untagged && sameColor && !annotation.isLocked;
      });
      if (legacyRows.length == 1 && candidates.length == 1) {
        target = candidates.first;
      }
    }

    if (target == null || target.isLocked) return false;
    _controller.removeAnnotation(target);
    if (_controller.getAnnotations().contains(target)) return false;
    _markEdited(highlight.page);
    return true;
  }

  /// Persist annotations inside the app's private copy of the PDF. A second
  /// call while a save runs waits for that save instead of starting another.
  Future<void> _saveDocument() {
    _docTimer?.cancel();
    return _docSave ??= _writeDocument().whenComplete(() => _docSave = null);
  }

  Future<void> _writeDocument() async {
    if (!_unsavedEdits.value || _pageCount == 0) return;
    final edits = _editCount;
    try {
      await writeBytesAtomic(_book.filePath, await _controller.saveDocument());
      if (!mounted) return;
      // An edit made while saving keeps the flag up for the next round.
      if (edits == _editCount) _unsavedEdits.value = false;
      if (_leaving) return; // no point re-rendering pages on the way out
      await _render.reset();
      _prefetch();
    } catch (_) {
      // Stays unsaved; the next trigger (timer, pause, exit) tries again.
    }
  }

  /// Saves the selected word (or [word]); the meaning is looked up in the
  /// background when it is a single word and the device is online.
  Future<void> _saveWord({String? word, String? meaning}) async {
    final text = word ?? _selected.value;
    if (text == null) return;
    final page = _page;
    _clearSelection();
    _toast('Word saved');

    try {
      final id = await _repo.addWord(_book.id, page, text);
      var found = meaning;
      if (found == null && DictionaryService.canLookUp(text)) {
        found = await _dictionary.lookup(text);
      }
      if (found != null) await _repo.setWordMeaning(id, found);
    } on Exception catch (error, stackTrace) {
      debugPrint('Could not save word: $error\n$stackTrace');
      _toast('Could not save the word.');
    }
  }

  /// Shows the meaning of the selected word, with a shortcut to save it.
  Future<void> _define() async {
    final selected = _selected.value;
    if (selected == null) return;
    final word = DictionaryService.lookupWord(selected);
    if (word == null) return;
    _clearSelection();
    _toast('Looking up “$word”…');

    final meaning = await _dictionary.lookup(word);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.ink, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        title: Text(word),
        content: Text(
          meaning ?? 'No meaning found. Check your internet connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CLOSE'),
          ),
          if (meaning != null)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('SAVE WORD'),
            ),
        ],
      ),
    );
    if (save ?? false) unawaited(_saveWord(word: word, meaning: meaning));
  }

  Future<void> _saveAnnotatedPdf() async {
    try {
      await _saveDocument();
      final bytes = await _controller.saveDocument();
      if (!mounted) return;

      final fileName =
          '${_book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.pdf';
      final saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/pdf',
        dialogTitle: 'Save annotated PDF',
      );
      if (!mounted || saved == null) return;
      _toast('Annotated PDF saved. Open it in Moon Reader.');
    } on Exception catch (error, stackTrace) {
      debugPrint('Could not save annotated PDF: $error\n$stackTrace');
      _toast('Could not save the annotated PDF.');
    }
  }

  // Search

  Future<void> _runSearch(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;
    _clearSearchResult();
    _flip.dropCover(); // the search moves the viewer to the first match

    final result = _controller.searchText(text);
    if (!mounted || !_searchOpen.value) {
      result.clear();
      return;
    }
    _searchResult.value = result;
  }

  void _clearSearchResult() {
    try {
      _searchResult.value?.clear();
    } catch (_) {}
    _searchResult.value = null;
  }

  void _closeSearch() {
    _clearSearchResult();
    _searchField.clear();
    _searchOpen.value = false;
  }

  // Contents and go-to-page

  Future<void> _openContents() async {
    if (_toc.isEmpty) {
      _toast('This PDF has no table of contents.');
      return;
    }
    final entry = await showContentsSheet(context, _toc);
    if (entry == null) return;
    try {
      _flip.dropCover();
      (_controller as dynamic).jumpToBookmark(entry.bookmark);
    } catch (_) {
      _toast('Could not open that section.');
    }
  }

  Future<void> _goToPage() async {
    if (_pageCount < 2) return;
    final page = await showGoToPageSheet(
      context,
      current: _page,
      count: _pageCount,
    );
    if (page != null && page != _page) _goTo(page);
  }

  Future<void> _openNotes() async {
    final page = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NotesScreen(book: _book, onDeleteHighlight: _removeHighlight),
      ),
    );
    if (page != null) _goTo(page);
  }

  /// Leaving with unsaved highlights: write the file first, then close.
  /// A clean exit just hands the final progress to the shelf.
  Future<void> _onPop(bool didPop, Object? result) async {
    if (!didPop && _searchOpen.value) {
      _closeSearch();
      return;
    }
    if (didPop) {
      unawaited(_flushProgress());
      if (_pageCount > 0) _library.applyProgress(_book.id, _page, _pageCount);
      return;
    }
    _leaving = true;
    await _saveDocument();
    // A highlight made while that save ran needs one more round.
    if (mounted && _unsavedEdits.value) await _saveDocument();
    if (!mounted) return;
    // Still unsaved (the write failed): do not trap the reader on screen.
    _unsavedEdits.value = false;
    Navigator.pop(context);
  }

  void _toast(String message, {int seconds = 1}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: seconds),
        ),
      );
  }

  Widget _viewerFor(bool flip) {
    if (_viewer != null && _viewerIsFlip == flip) return _viewer!;
    _viewerIsFlip = flip;
    return _viewer = SfPdfViewerTheme(
      // White around the page: after the page tint it is the paper color
      // (black on the Night page), so the page has no differently colored
      // bands above and below it.
      data: const SfPdfViewerThemeData(backgroundColor: Colors.white),
      child: SfPdfViewer.file(
        _file,
        key: _viewerKey,
        controller: _controller,
        pageLayoutMode: .single,
        scrollDirection: PdfScrollDirection.horizontal,
        maxZoomLevel: 3,
        enableDoubleTapZooming: true,
        // The app's own bar at the bottom does this job (and records the
        // highlight in Notes, which the viewer's popup menu does not).
        canShowTextSelectionMenu: false,
        pageSpacing: 0,
        canShowScrollHead: false,
        canShowPageLoadingIndicator: false,
        onDocumentLoaded: _onLoaded,
        onDocumentLoadFailed: _onLoadFailed,
        onPageChanged: _onPageChanged,
        onZoomLevelChanged: _onZoomLevelChanged,
        onTextSelectionChanged: _onSelection,
        onAnnotationAdded: _onAnnotationAdded,
      ),
    );
  }

  PreferredSizeWidget _readerAppBar() {
    return AppBar(
      actions: [
        _BookmarkButton(
          bookId: _book.id,
          page: _pageN,
          onPressed: _toggleBookmark,
        ),
        IconButton(
          tooltip: 'Search in book',
          icon: const Icon(Icons.search),
          onPressed: () {
            _setChrome(true);
            _searchOpen.value = true;
          },
        ),
        ValueListenableBuilder<double>(
          valueListenable: _zoomLevel,
          builder: (context, zoom, _) => IconButton(
            tooltip: zoom > 1 ? 'Reset zoom' : 'Zoom in',
            icon: Icon(zoom > 1 ? Icons.zoom_out : Icons.zoom_in),
            onPressed: _toggleZoom,
          ),
        ),
        IconButton(
          tooltip: 'Highlights, bookmarks, words',
          icon: const Icon(Icons.list_alt),
          onPressed: _openNotes,
        ),
        PopupMenuButton<_ReaderMenu>(
          tooltip: 'More',
          onSelected: (item) => switch (item) {
            _ReaderMenu.contents => _openContents(),
            _ReaderMenu.goToPage => _goToPage(),
            _ReaderMenu.saveAnnotatedPdf => _saveAnnotatedPdf(),
            _ReaderMenu.settings => showReadingSettingsSheet(context),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: _ReaderMenu.contents, child: Text('Contents')),
            PopupMenuItem(
              value: _ReaderMenu.goToPage,
              child: Text('Go to page'),
            ),
            PopupMenuItem(
              value: _ReaderMenu.saveAnnotatedPdf,
              child: Text('Save annotated PDF'),
            ),
            PopupMenuItem(
              value: _ReaderMenu.settings,
              child: Text('Reading settings'),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _searchAppBar() {
    return AppBar(
      leading: IconButton(
        tooltip: 'Close search',
        icon: const Icon(Icons.arrow_back),
        onPressed: _closeSearch,
      ),
      title: TextField(
        controller: _searchField,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: _runSearch,
        decoration: const InputDecoration(
          hintText: 'Search in this book',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
      actions: [
        ValueListenableBuilder<PdfTextSearchResult?>(
          valueListenable: _searchResult,
          builder: (context, result, _) => result == null
              ? const SizedBox.shrink()
              : ListenableBuilder(
                  listenable: result,
                  builder: (context, _) => Center(
                    child: Text(
                      !result.isSearchCompleted
                          ? '…'
                          : result.hasResult
                          ? '${result.currentInstanceIndex}/'
                                '${result.totalInstanceCount}'
                          : 'None',
                    ),
                  ),
                ),
        ),
        IconButton(
          tooltip: 'Previous match',
          icon: const Icon(Icons.keyboard_arrow_up),
          onPressed: () {
            _flip.dropCover();
            _searchResult.value?.previousInstance();
          },
        ),
        IconButton(
          tooltip: 'Next match',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () {
            _flip.dropCover();
            _searchResult.value?.nextInstance();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tint = ref.watch(pageTintProvider);
    final flip = ref.watch(pageTurnProvider) == PageTurn.flip;
    // Slide follows the finger exactly; the curl runs a little ahead.
    _flip.dragSpan = flip ? 0.85 : 1;

    ref.listen(
      pageTurnProvider,
      (_, next) => _onTurnStyleChanged(next == PageTurn.flip),
    );
    ref.listen(keepAwakeProvider, (_, on) => unawaited(_applyWakelock(on)));
    // Captures and pre-rendered pages have the old color baked in.
    ref.listen(pageTintProvider, (_, next) {
      _render.setTint(next.filter);
      _flip.invalidate();
      _prefetch();
    });

    final scaffold = Scaffold(
      extendBodyBehindAppBar: true,
      // The only text field is in the app bar; the keyboard must not shrink
      // the page (that would re-render every pre-rendered page).
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ListenableBuilder(
          listenable: Listenable.merge([_searchOpen, _chrome]),
          builder: (context, _) {
            final open = _searchOpen.value;
            final show = open || _chrome.value;
            return IgnorePointer(
              ignoring: !show,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                offset: show ? Offset.zero : const Offset(0, -1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: show ? 1 : 0,
                  child: open ? _searchAppBar() : _readerAppBar(),
                ),
              ),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              _onViewportChanged(
                constraints.biggest,
                MediaQuery.devicePixelRatioOf(context),
              );

              final width = constraints.maxWidth;
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: (e) => _onPointerUp(e, width, flip),
                onPointerCancel: _onPointerCancel,
                child: ListenableBuilder(
                  listenable: Listenable.merge([_flip, _zoomLevel]),
                  // Built once per screen build, not once per flip frame.
                  child: ColorFiltered(
                    colorFilter: tint.filter,
                    child: _viewerFor(flip),
                  ),
                  builder: (context, viewer) => ValueListenableBuilder<String?>(
                    valueListenable: _selected,
                    child: viewer,
                    builder: (context, selected, viewer) => FlipPager(
                      boundaryKey: _boundaryKey,
                      enabled: selected == null && _zoomLevel.value <= 1,
                      curl: flip,
                      tapZones: flip,
                      pose: _flip.pose,
                      progress: _flip.progress,
                      image: _flip.image,
                      under: _flip.under,
                      blank: tint.blank,
                      forward: _flip.forward,
                      edgeSign: _flip.edgeSign,
                      edgeTravel: FlipController.edgeTravel,
                      imageFitted: _flip.imageFitted,
                      backdrop: _flip.backdrop,
                      blockChild: _flip.active || _flip.covering,
                      onTouchDown: _flip.prepare,
                      onTapZone: (forward) => _flip.turn(forward: forward),
                      onScaleStart: _onFlipScaleStart,
                      onScaleUpdate: _onFlipScaleUpdate,
                      onScaleEnd: _onFlipScaleEnd,
                      child: viewer!,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SafeArea(
                top: false,
                child: ListenableBuilder(
                  listenable: Listenable.merge([_pageN, _pageCountDisplay]),
                  builder: (context, _) {
                    final page = _pageN.value;
                    final pageCount = _pageCountDisplay.value;
                    final chapter = chapterForPage(_toc, page)?.title;
                    // Just a quiet line of text at the foot of the page,
                    // in the page's own text color (light on the Night
                    // page). The glow in the paper color keeps it readable
                    // where a page's own print runs underneath.
                    final barText = Theme.of(context).textTheme.labelLarge
                        ?.copyWith(
                          fontSize: 12,
                          color: tint.textColor.withValues(alpha: 0.72),
                          shadows: [
                            Shadow(color: tint.swatch, blurRadius: 3),
                            Shadow(color: tint.swatch, blurRadius: 6),
                          ],
                        );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                      child: Row(
                        children: [
                          Text(
                            'PAGE $page${pageCount > 0 ? ' / $pageCount' : ''}',
                            style: barText,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              chapter ?? 'Chapter unavailable',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: barText,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<String?>(
              valueListenable: _selected,
              builder: (context, selected, _) => selected == null
                  ? const SizedBox.shrink()
                  : ValueListenableBuilder<Color>(
                      valueListenable: _highlightColor,
                      builder: (context, color, _) => SelectionBar(
                        color: color,
                        onColor: (c) => _highlightColor.value = c,
                        canDefine: DictionaryService.canLookUp(selected),
                        onHighlight: _highlight,
                        onSaveWord: _saveWord,
                        onDefine: _define,
                        onCopy: _copySelection,
                        onClose: _clearSelection,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );

    // Back is held while highlights wait to be written (briefly) and while
    // the search bar is open (it closes the search first).
    return ListenableBuilder(
      listenable: Listenable.merge([_unsavedEdits, _searchOpen]),
      child: scaffold,
      builder: (context, child) => PopScope(
        canPop: !_unsavedEdits.value && !_searchOpen.value,
        onPopInvokedWithResult: _onPop,
        child: child!,
      ),
    );
  }
}

/// Only this button rebuilds when the page changes or a bookmark is toggled.
class _BookmarkButton extends ConsumerWidget {
  const _BookmarkButton({
    required this.bookId,
    required this.page,
    required this.onPressed,
  });

  final int bookId;
  final ValueListenable<int> page;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final marks = ref.watch(bookmarksProvider.select((all) => all[bookId]));

    return ValueListenableBuilder<int>(
      valueListenable: page,
      builder: (context, current, _) {
        final marked = marks?.contains(current) ?? false;
        return IconButton(
          tooltip: 'Bookmark page',
          icon: Icon(
            marked ? Icons.bookmark : Icons.bookmark_border,
            color: marked ? AppColors.terracotta : null,
          ),
          onPressed: onPressed,
        );
      },
    );
  }
}
