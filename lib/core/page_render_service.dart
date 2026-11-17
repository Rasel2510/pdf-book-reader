import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:pdfx/pdfx.dart' as pdfx;

/// How a mark made in the viewer is drawn on a page.
enum PageMarkKind { highlight, underline, strikethrough }

/// One line of a highlight (or underline, strikethrough): [rect] in page
/// points from the page's top-left corner.
typedef PageMark = ({ui.Rect rect, ui.Color color, PageMarkKind kind});

/// Renders single PDF pages to bitmaps (used under the book-flip transition,
/// so the next page is ready before the viewer has painted it).
///
/// - Renders run one at a time: Android's PdfRenderer allows only one open
///   page per document.
/// - Only pages near the reader's position are worth rendering. [focus] moves
///   that window, and queued jobs for pages that fell out of it are skipped,
///   so flipping fast never wastes time on pages the reader already passed.
/// - The page tint is baked into each bitmap here, once, off the interaction
///   path. The flip animation then draws plain images with no per-frame
///   color-filter pass.
/// - The platform renderer leaves out highlights and other marks, so they
///   are drawn here on top, the way the viewer draws them. A page then looks
///   the same as a bitmap and in the viewer.
class PageRenderService {
  PageRenderService(this.path, {this.marksFor});

  final String path;

  /// The marks currently on a page, asked for each time it is rendered.
  final List<PageMark> Function(int page)? marksFor;

  static const _maxCached = 4;

  /// Pages farther than this from the focus are not rendered.
  static const _window = 2;

  final _cache = <int, ui.Image>{};
  final _pending = <int, Future<void>>{};

  Future<void> _queue = Future<void>.value();
  Future<pdfx.PdfDocument>? _doc;

  ui.Size _size = ui.Size.zero;
  double _ratio = 1;
  ui.ColorFilter? _tint;
  int _center = 1;
  int _generation = 0;
  bool _disposed = false;

  /// Target viewport in logical pixels. Returns true if it changed (the
  /// cache was dropped).
  bool configure(ui.Size size, double pixelRatio) {
    if (size == _size && pixelRatio == _ratio) return false;
    _size = size;
    _ratio = pixelRatio;
    _clear();
    return true;
  }

  /// Returns true if the tint changed (the cache was dropped).
  bool setTint(ui.ColorFilter filter) {
    if (_tint == filter) return false;
    _tint = filter;
    _clear();
    return true;
  }

  void _clear() {
    _generation++;
    // Jobs already queued see the new generation and stop; clearing the flags
    // lets the caller queue fresh ones right away (tint change, reset).
    _pending.clear();
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }

  /// A new handle on the cached bitmap (the caller disposes it), or null.
  ui.Image? take(int page) => _cache[page]?.clone();

  /// Move the window to [page] and render its neighbours, next page first.
  Future<void> focus(int page) {
    _center = page;
    _evictFar();
    return Future.wait([
      prefetch(page + 1),
      prefetch(page - 1),
      prefetch(page + 2),
    ]);
  }

  bool _wanted(int page) => (page - _center).abs() <= _window;

  void _evictFar() {
    while (_cache.length > _maxCached) {
      final far = _cache.keys.reduce(
        (a, b) => (a - _center).abs() >= (b - _center).abs() ? a : b,
      );
      _cache.remove(far)?.dispose();
    }
  }

  Future<void> prefetch(int page) {
    if (_disposed || page < 1 || _size.isEmpty || _cache.containsKey(page)) {
      return Future<void>.value();
    }
    final pending = _pending[page];
    if (pending != null) return pending;

    final generation = _generation;
    late final Future<void> job;
    job = _serial(() async {
      try {
        if (_disposed || generation != _generation || !_wanted(page)) return;
        final image = await _render(page);
        if (image == null) return;
        if (_disposed || generation != _generation) {
          image.dispose();
          return;
        }
        _cache.remove(page)?.dispose();
        _cache[page] = image;
        _evictFar();
      } catch (_) {
        // A page that cannot be rendered just has no pre-rendered bitmap;
        // the flip falls back to moving the viewer.
      } finally {
        if (identical(_pending[page], job)) _pending.remove(page);
      }
    });
    _pending[page] = job;
    return job;
  }

  /// Waits for [page] to be available and returns an owned image handle.
  Future<ui.Image?> prepare(int page) async {
    await prefetch(page);
    if (_disposed) return null;
    return take(page);
  }

  /// A mark was added to or removed from a page in the viewer: bitmaps made
  /// before that are out of date (also ones being rendered right now).
  void marksChanged() => _clear();

  /// The PDF file changed on disk (e.g. edits were saved).
  Future<void> reset() {
    _clear();
    return _serial(_closeDocument);
  }

  Future<void> dispose() {
    _disposed = true;
    _clear();
    return _serial(_closeDocument);
  }

  Future<void> _closeDocument() async {
    final doc = _doc;
    _doc = null;
    if (doc == null) return;
    try {
      await (await doc).close();
    } catch (_) {}
  }

  Future<void> _serial(Future<void> Function() job) {
    final next = _queue.then((_) => job());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<pdfx.PdfDocument> _open() => _doc ??= _openFresh();

  Future<pdfx.PdfDocument> _openFresh() async {
    try {
      return await pdfx.PdfDocument.openFile(path);
    } catch (_) {
      _doc = null; // let the next call try again
      rethrow;
    }
  }

  Future<ui.Image?> _render(int page) async {
    final doc = await _open();
    if (page > doc.pagesCount) return null;

    final pdfPage = await doc.getPage(page);
    try {
      // Same fit as the viewer: whole page inside the viewport.
      final scale = math.min(
        _size.width / pdfPage.width,
        _size.height / pdfPage.height,
      );
      final result = await pdfPage.render(
        width: pdfPage.width * scale * _ratio,
        height: pdfPage.height * scale * _ratio,
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        // The bitmap is only on screen for the length of one turn.
        quality: 80,
      );
      if (result == null) return null;

      final codec = await ui.instantiateImageCodec(result.bytes);
      try {
        final decoded = (await codec.getNextFrame()).image;
        var marks = const <PageMark>[];
        try {
          marks = marksFor?.call(page) ?? marks;
        } catch (_) {
          // The viewer may be gone already; the page is drawn without marks.
        }
        return _finished(decoded, marks, decoded.width / pdfPage.width);
      } finally {
        codec.dispose();
      }
    } finally {
      await pdfPage.close();
    }
  }

  /// Draws [source] with [marks] on top, all through the current tint, into
  /// a new bitmap. [scale] is bitmap pixels per page point.
  Future<ui.Image> _finished(
    ui.Image source,
    List<PageMark> marks,
    double scale,
  ) async {
    final filter = _tint;
    if (filter == null && marks.isEmpty) return source;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (filter != null) {
      canvas.saveLayer(
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        ui.Paint()..colorFilter = filter,
      );
    }
    canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    for (final mark in marks) {
      final rect = ui.Rect.fromLTRB(
        mark.rect.left * scale,
        mark.rect.top * scale,
        mark.rect.right * scale,
        mark.rect.bottom * scale,
      );
      final line = ui.Paint()
        ..color = mark.color
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = scale;
      switch (mark.kind) {
        case PageMarkKind.highlight:
          // The viewer fills a highlight at 30% of its opacity.
          canvas.drawRect(
            rect,
            ui.Paint()
              ..color = mark.color.withValues(alpha: mark.color.a * 0.3),
          );
        case PageMarkKind.underline:
          canvas.drawLine(rect.bottomLeft, rect.bottomRight, line);
        case PageMarkKind.strikethrough:
          canvas.drawLine(rect.centerLeft, rect.centerRight, line);
      }
    }
    if (filter != null) canvas.restore();
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(source.width, source.height);
    } finally {
      picture.dispose();
      source.dispose();
    }
  }
}
