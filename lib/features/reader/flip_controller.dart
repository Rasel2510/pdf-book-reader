import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// How the curling page is held: [pivotY] is the height (0 top, 1 bottom)
/// the fold line passes through, [tilt] how far the fold leans (sideways
/// shift per unit of height; negative = the bottom corner leads).
typedef CurlPose = ({double pivotY, double tilt});

/// Logic of the book-flip page turn: drag tracking, snap decision, the
/// animation, and the hand-off to the PDF viewer. No widgets in here; the
/// screen owns it and passes plain values to [FlipPager].
///
/// A turn captures the visible page as a bitmap and swings it away. The
/// page underneath is a pre-rendered bitmap of the neighbour page
/// (prepared by [prepareNeighborImage]); the viewer only jumps once the turn
/// completes. If a page cannot be rendered ahead, the viewer is the fallback.
///
/// The viewer needs up to a second to paint a page it was moved to, and is
/// blank until then. So after a turn the bitmap of the new page stays on top
/// ([covering]) until the viewer really shows it. A turn started meanwhile
/// turns that bitmap; it never waits for the viewer.
class FlipController extends ChangeNotifier {
  FlipController({
    required TickerProvider vsync,
    required this.boundaryKey,
    required this.pixelRatio,
    required this.currentPage,
    required this.pageCount,
    required this.jumpTo,
    required this.prepareNeighborImage,
    required this.onFlipStart,
    required this.onFlipReveal,
    required this.onFlipEnd,
  }) : _anim = AnimationController(vsync: vsync, duration: _duration);

  /// Max sideways push (logical px) when swiping past the first/last page.
  static const edgeTravel = 36.0;

  static const _duration = Duration(milliseconds: 320);

  /// The viewer shows a blank page while it rasters the destination page.
  /// The turn's own bitmap stays on top until the viewer really shows
  /// content; these are the shortest and longest waits after it moved.
  static const _minSettle = Duration(milliseconds: 140);
  static const _maxSettle = kDebugMode
      ? Duration(milliseconds: 4000)
      : Duration(milliseconds: 2500);

  static const _tapPose = (pivotY: 0.8, tilt: -0.25);
  static const _maxTilt = 0.45;

  /// Progress at which the viewer is moved to the new page.
  static const _jumpAt = 0.5;

  final GlobalKey boundaryKey;
  final double Function() pixelRatio;
  final int Function() currentPage;
  final int Function() pageCount;
  final void Function(int page) jumpTo;

  /// Waits for [page] and returns an owned bitmap handle, or null on failure.
  final Future<ui.Image?> Function(int page) prepareNeighborImage;
  final VoidCallback onFlipStart;
  final void Function(int page) onFlipReveal;
  final void Function(int page) onFlipEnd;

  final AnimationController _anim;

  // Values for the widget.
  ui.Image? _image;
  ui.Image? _under;
  bool _imageFitted = false;
  Color? _backdrop;
  bool _forward = true;
  int _edgeSign = 0;

  /// Bumped whenever the held page changes hands; stops its old watcher.
  int _coverEpoch = 0;

  Animation<double> get progress => _anim;

  /// How the curling page is held; follows the finger during a drag.
  final pose = ValueNotifier<CurlPose>(_tapPose);

  /// Share of the width a drag must cover for a full turn. 1 makes the
  /// page follow the finger exactly (slide).
  double dragSpan = 0.85;
  ui.Image? get image => _image;
  ui.Image? get under => _under;

  /// Whether [image] is a page bitmap (fitted like [under]) and not a
  /// snapshot of the whole viewer.
  bool get imageFitted => _imageFitted;

  /// No turn is running, but the page of the last one is still held over
  /// the viewer (in [under]) while the viewer paints it.
  bool get covering => _image == null && _under != null;

  /// Color the viewer shows around the page, read from its pixels. Null
  /// until first measured.
  Color? get backdrop => _backdrop;
  bool get forward => _forward;
  bool get active => _active;

  /// -1 / +1 while the page is pushed left / right at the first or last
  /// page, else 0.
  int get edgeSign => _edgeSign;

  // Pre-captured bitmap of the current page (taken on touch-down).
  ui.Image? _prepared;
  int _preparedPage = 0;
  Future<ui.Image?>? _preparing;
  int _epoch = 0;

  int _from = 1;
  double _dx = 0;
  double _dy = 0;
  double _grabY = 0.5;
  double _width = 1;
  double? _pendingVelocity;
  int _queued = 0; // a turn requested while busy: 1 next, -1 previous

  bool _dragging = false;
  bool _ignore = false;
  bool _busyAtStart = false;
  bool _starting = false;
  bool _active = false;
  bool _finishing = false;
  bool _edging = false;
  bool _jumpedEarly = false;
  bool _viewerMoved = false;
  bool _disposed = false;

  /// Time since the viewer was last moved by a turn.
  final _sinceMove = Stopwatch();

  /// The page on screen changed in a way the controller did not do itself
  /// (tint, highlight, page jump, resize): drop the pre-captured bitmap.
  void invalidate() {
    _epoch++;
    _prepared?.dispose();
    _prepared = null;
    if (_disposed) return;
    // The color around the page may have changed too (tint).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _under == null) unawaited(_sampleBackdrop());
    });
  }

  /// Capture the current page ahead of a possible drag.
  Future<void> prepare() async {
    if (_disposed || _active || _finishing || _starting) return;
    if (_under != null) return; // a held page hides the viewer
    unawaited(_sampleBackdrop());
    if (_preparing != null || pageCount() == 0) return;
    final page = currentPage();
    if (_prepared != null && _preparedPage == page) return;

    final epoch = _epoch;
    final job = _capture();
    _preparing = job;
    final shot = await job;
    _preparing = null;
    if (shot == null) return;

    if (_disposed || epoch != _epoch || page != currentPage()) {
      shot.dispose();
      return;
    }
    _prepared?.dispose();
    _prepared = shot;
    _preparedPage = page;
  }

  Future<ui.Image?> _capture() async {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    try {
      return await boundary.toImage(pixelRatio: pixelRatio());
    } catch (_) {
      return null;
    }
  }

  /// Reads the color around the page from the corner of a tiny capture.
  Future<void> _sampleBackdrop() async {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;

    ui.Image? probe;
    try {
      probe = await boundary.toImage(pixelRatio: 0.05);
      final data = await probe.toByteData();
      if (data == null || data.lengthInBytes < 4 || _disposed) return;
      final color = Color.fromARGB(
        255,
        data.getUint8(0),
        data.getUint8(1),
        data.getUint8(2),
      );
      if (color == _backdrop) return;
      _backdrop = color;
      notifyListeners();
    } catch (_) {
      // Keep the last known color.
    } finally {
      probe?.dispose();
    }
  }

  Future<ui.Image?> _takeShot() async {
    final pending = _preparing;
    if (pending != null) await pending;

    final ready = _prepared;
    _prepared = null;
    if (ready != null && _preparedPage == currentPage()) return ready;
    ready?.dispose();
    return _capture();
  }

  // Drag input

  /// [grabY]: height of the finger on the page, 0 (top) to 1 (bottom).
  void dragStart({double grabY = 0.5}) {
    _busyAtStart = _active || _finishing || _starting;
    _ignore = _busyAtStart;
    _dragging = true;
    _dx = 0;
    _dy = 0;
    if (!_busyAtStart) {
      _grabY = grabY.clamp(0.0, 1.0).toDouble();
      pose.value = (pivotY: _grabY, tilt: 0);
    }
    _pendingVelocity = null;
    unawaited(prepare());
  }

  /// [dy] and [height]: vertical finger movement and page height; they
  /// make the curl lean after the finger.
  Future<void> dragUpdate(
    double delta,
    double width, {
    double dy = 0,
    double height = 0,
  }) async {
    _dx += delta;
    _width = width;
    if (_ignore) return;

    if (_dragging && height > 0 && width > 0) {
      _dy += dy;
      pose.value = (
        pivotY: (_grabY + _dy / height / 2).clamp(0.0, 1.0).toDouble(),
        tilt: (_dy / (width * 0.6)).clamp(-_maxTilt, _maxTilt).toDouble(),
      );
    }

    if (!_active && !_edging) {
      if (_starting || _dx.abs() < 2) return;
      await _begin(forward: _dx < 0);
    }

    if (_edging) {
      if (_dragging) _anim.value = _progress();
    } else if (_active) {
      if (_dragging) {
        _anim.value = _progress();
      } else {
        // Finger was lifted while the page was being captured.
        _settle(_pendingVelocity ?? 0);
      }
    }
  }

  void dragEnd(double velocity) {
    _dragging = false;

    if (_ignore) {
      // Swiped while the previous turn was still finishing: queue it.
      final fast = velocity.abs() > 500;
      if (_busyAtStart && (fast || _dx.abs() > 40)) {
        final forward = fast ? velocity < 0 : _dx < 0;
        _queued = forward ? 1 : -1;
      }
      return;
    }
    if (_edging) {
      _releaseEdge();
    } else if (_starting) {
      _pendingVelocity = velocity;
    } else if (_active) {
      _settle(velocity);
    }
  }

  void dragCancel() => dragEnd(0);

  double _progress() {
    final moved = _forward ? -_dx : _dx;
    return (moved / (_width * dragSpan)).clamp(0.0, 1.0).toDouble();
  }

  /// Turn without a drag (tap zones, queued swipes).
  Future<void> turn({required bool forward}) async {
    if (_disposed || _active || _edging) return;
    if (_finishing || _starting) {
      _queued = forward ? 1 : -1;
      return;
    }
    final count = pageCount();
    if (count == 0) return;

    final to = currentPage() + (forward ? 1 : -1);
    if (to < 1 || to > count) {
      await _bounceOnce(forward);
      return;
    }

    pose.value = _tapPose;
    await _begin(forward: forward);
    if (_active) await _finish(true);
  }

  /// Settle a turn that is running when it can no longer be driven by the
  /// finger (e.g. text got selected).
  void abort() {
    if (_active && !_finishing) {
      _dragging = false;
      unawaited(_finish(_anim.value > 0.5));
    } else if (_edging) {
      _releaseEdge();
    }
  }

  Future<void> _begin({required bool forward}) async {
    final count = pageCount();
    final from = currentPage();
    final to = forward ? from + 1 : from - 1;

    if (count == 0) {
      _ignore = true;
      return;
    }
    if (to < 1 || to > count) {
      // First/last page: push the page sideways instead of turning.
      _forward = forward;
      _edging = true;
      _edgeSign = forward ? -1 : 1;
      _anim.value = 0;
      notifyListeners();
      return;
    }

    _starting = true;
    // A page still held over the viewer is the page being left: turn that
    // bitmap. The viewer underneath may not have painted it yet.
    final held = covering ? _under : null;
    if (held != null) _coverEpoch++; // this turn owns it now
    final images = await Future.wait<ui.Image?>([
      if (held == null) _takeShot() else Future<ui.Image?>.value(),
      prepareNeighborImage(to),
    ]);
    final shot = held ?? images[0];
    final under = images[1];
    if (shot == null || _disposed) {
      under?.dispose();
      if (held == null) shot?.dispose(); // a held page is still in _under
      _starting = false;
      _ignore = true;
      return;
    }

    _jumpedEarly = under == null;
    _viewerMoved = false;
    onFlipStart();
    if (under == null) _moveViewer(to);

    _anim.value = 0;
    _image = shot;
    _imageFitted = held != null;
    _under = under;
    _forward = forward;
    _from = from;
    _active = true;
    _starting = false;
    notifyListeners();
  }

  void _settle(double velocity) {
    final inDirection = _forward ? -velocity : velocity;
    final complete =
        inDirection > -500 && (_anim.value > 0.3 || inDirection > 500);
    unawaited(_finish(complete));
  }

  void _moveViewer(int page) {
    _viewerMoved = true;
    _sinceMove
      ..reset()
      ..start();
    jumpTo(page);
  }

  Future<void> _finish(bool complete) async {
    if (_finishing || !_active) return;
    _finishing = true;

    final target = _forward ? _from + 1 : _from - 1;

    // The pre-rendered bitmap fully covers the viewer, so the viewer can move
    // to the new page while the turn is still running and has the rest of the
    // animation to paint it. (Without a bitmap it already moved in _begin.)
    void moveWhenCovered() {
      if (_disposed || _viewerMoved || _anim.value < _jumpAt) return;
      _moveViewer(target);
    }

    final moveEarly = complete && !_jumpedEarly;
    if (moveEarly) {
      _anim.addListener(moveWhenCovered);
      moveWhenCovered(); // a drag released past the point already
    }

    try {
      final remaining = complete ? 1 - _anim.value : _anim.value;
      final ms = (_duration.inMilliseconds * remaining).round().clamp(120, 320);
      await _anim.animateTo(
        complete ? 1.0 : 0.0,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOut,
      );
      if (_disposed) return;

      if (moveEarly) _anim.removeListener(moveWhenCovered);
      if (moveEarly && !_viewerMoved) _moveViewer(target);
      if (!complete && _jumpedEarly) _moveViewer(_from);
      if (complete) onFlipReveal(target);

      final page = complete ? target : _from;
      if (_under == null) {
        // No bitmap of the other page: the snapshot stays up until the
        // viewer has painted.
        final epoch = ++_coverEpoch;
        await WidgetsBinding.instance.endOfFrame;
        if (_viewerMoved) await _viewerPainted(epoch);
        if (_disposed) return;
        _release();
        onFlipEnd(page);
      } else {
        // The page now on top stays over the viewer until the viewer has
        // painted it. The next turn can start right away.
        final keep = complete ? _under : (_imageFitted ? _image : null);
        final drop = [
          if (!identical(_image, keep)) _image,
          if (!identical(_under, keep)) _under,
        ];
        _image = null;
        _under = keep;
        _imageFitted = false;
        _active = false;
        notifyListeners();
        _disposeAfterFrame(drop);
        if (keep == null) {
          onFlipEnd(page);
        } else {
          unawaited(_watchCover(page));
        }
      }
    } finally {
      if (moveEarly && !_disposed) _anim.removeListener(moveWhenCovered);
      _finishing = false;
    }

    final queued = _queued;
    _queued = 0;
    if (queued != 0 && !_disposed) unawaited(turn(forward: queued > 0));
  }

  /// Something else is about to move the viewer (search, go to page): let
  /// go of a held page now, it is no longer the page being shown.
  void dropCover() {
    if (_disposed || !covering) return;
    _coverEpoch++;
    final cover = _under;
    _under = null;
    notifyListeners();
    _disposeAfterFrame([cover]);
    onFlipEnd(currentPage());
  }

  /// Takes the held page away once the viewer shows [page] itself. Gives
  /// up silently if a new turn took the held page over.
  Future<void> _watchCover(int page) async {
    final epoch = ++_coverEpoch;
    await WidgetsBinding.instance.endOfFrame;
    await _viewerPainted(epoch);
    if (_disposed || epoch != _coverEpoch || !covering) return;

    final cover = _under;
    _under = null;
    notifyListeners();
    _disposeAfterFrame([cover]);
    onFlipEnd(page);
  }

  /// Completes once the viewer shows the page it was moved to (or after
  /// [_maxSettle], e.g. for a page that really is empty).
  Future<void> _viewerPainted(int epoch) async {
    while (!_disposed &&
        epoch == _coverEpoch &&
        _sinceMove.elapsed < _maxSettle) {
      if (_sinceMove.elapsed >= _minSettle && await _viewerHasContent()) {
        // One more frame, so what was measured is on screen.
        await WidgetsBinding.instance.endOfFrame;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  /// Whether the middle of the viewer is more than one flat color. Looks at
  /// a tiny capture; the middle is always inside the page, never the
  /// background around it.
  Future<bool> _viewerHasContent() async {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return false;

    ui.Image? probe;
    try {
      probe = await boundary.toImage(pixelRatio: 0.12);
      final data = await probe.toByteData();
      if (data == null) return false;

      final w = probe.width;
      final h = probe.height;
      var low = 255 * 3;
      var high = 0;
      for (var y = h ~/ 4; y < h * 3 ~/ 4; y++) {
        for (var x = w ~/ 4; x < w * 3 ~/ 4; x++) {
          final i = (y * w + x) * 4;
          final sum =
              data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2);
          if (sum < low) low = sum;
          if (sum > high) high = sum;
        }
      }
      return high - low > 54; // an average of 18 per color channel
    } catch (_) {
      return false;
    } finally {
      probe?.dispose();
    }
  }

  void _release() {
    final image = _image;
    final under = _under;
    _image = null;
    _under = null;
    _imageFitted = false;
    _active = false;
    notifyListeners();
    _disposeAfterFrame([image, under]);
  }

  /// Dispose after the frame that stops drawing them.
  void _disposeAfterFrame(List<ui.Image?> images) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        for (final image in images) {
          image?.dispose();
        }
      })
      ..ensureVisualUpdate();
  }

  // Edge bounce

  void _releaseEdge() {
    _edging = false;
    _finishing = true;
    unawaited(
      _anim
          .animateBack(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          )
          .whenComplete(_endBounce),
    );
  }

  Future<void> _bounceOnce(bool forward) async {
    _finishing = true;
    _edgeSign = forward ? -1 : 1;
    _anim.value = 0;
    notifyListeners();

    await _anim.animateTo(
      0.45,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
    await _anim.animateBack(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    _endBounce();
  }

  void _endBounce() {
    if (_disposed) return;
    _edgeSign = 0;
    _finishing = false;
    notifyListeners();

    final queued = _queued;
    _queued = 0;
    if (queued != 0) unawaited(turn(forward: queued > 0));
  }

  @override
  void dispose() {
    _disposed = true;
    _anim.dispose();
    pose.dispose();
    _image?.dispose();
    _under?.dispose();
    _prepared?.dispose();
    super.dispose();
  }
}
