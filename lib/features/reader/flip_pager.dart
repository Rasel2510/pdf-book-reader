import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'flip_controller.dart' show CurlPose;

/// Draws the page turn (book curl or plain slide) over any page viewer and
/// forwards touches.
///
/// Pure view: everything arrives as values and callbacks. The logic lives
/// in FlipController, owned by the screen.
///
/// Layers, bottom to top: the viewer ([child]), the turn itself (painted
/// from [image] and [under]), the gesture layer.
class FlipPager extends StatelessWidget {
  const FlipPager({
    super.key,
    required this.child,
    required this.boundaryKey,
    required this.enabled,
    required this.progress,
    required this.image,
    required this.under,
    required this.blank,
    required this.forward,
    required this.edgeSign,
    required this.edgeTravel,
    required this.blockChild,
    required this.onTouchDown,
    required this.onTapZone,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    this.curl = true,
    this.tapZones = true,
    this.pose,
    this.imageFitted = false,
    this.backdrop,
  });

  /// Share of the width, at each side, where a tap turns the page.
  static const _tapZone = 0.28;

  /// The viewer has its own swipe-to-turn. This layer must claim a drag
  /// first, so the viewer is made to wait for a much longer movement. This
  /// layer keeps the platform's usual distance (a pan is accepted after
  /// twice this), so a long press to select text is not mistaken for a drag.
  static const _gestures = DeviceGestureSettings(touchSlop: 8);
  static const _viewerGestures = DeviceGestureSettings(touchSlop: 48);

  static final ValueListenable<CurlPose> _restPose = ValueNotifier<CurlPose>((
    pivotY: 0.8,
    tilt: -0.25,
  ));

  final Widget child;

  /// Key of the RepaintBoundary around [child]; used to capture the page.
  final GlobalKey boundaryKey;
  final bool enabled;

  /// 0 = turn not started, 1 = turn done. Also drives the edge push.
  final Animation<double> progress;

  /// Snapshot of the page the turn starts on, or null when idle.
  final ui.Image? image;

  /// Bitmap of the page the turn ends on, or null (viewer shows it).
  /// Already tinted by the render service. Given without [image], it is
  /// simply held over the viewer.
  final ui.Image? under;

  /// [image] is a page bitmap like [under], not a viewer snapshot.
  final bool imageFitted;

  /// Color the viewer shows around the page; [blank] if not known.
  final Color? backdrop;

  /// Color of an empty page with the reader tint applied.
  final Color blank;
  final bool forward;

  /// -1 / +1: push the page left / right (first or last page). 0: none.
  final int edgeSign;
  final double edgeTravel;

  /// Stop the viewer reacting to touches while a turn is running.
  final bool blockChild;

  final VoidCallback onTouchDown;
  final void Function(bool forward) onTapZone;
  final void Function(ScaleStartDetails details) onScaleStart;
  final void Function(ScaleUpdateDetails details, Size size) onScaleUpdate;
  final void Function(ScaleEndDetails details) onScaleEnd;

  /// true: the page curls over like paper. false: pages slide sideways.
  final bool curl;

  /// Whether a tap near the left / right side turns the page.
  final bool tapZones;

  /// Where the curl is held and how far it leans (curl only).
  final ValueListenable<CurlPose>? pose;

  @override
  Widget build(BuildContext context) {
    final turning = image;
    final revealed = under;
    final around = backdrop ?? blank;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final media = MediaQuery.of(context);

        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: progress,
              builder: (context, inner) => Transform.translate(
                offset: Offset(edgeSign * edgeTravel * progress.value, 0),
                child: inner,
              ),
              child: RepaintBoundary(
                key: boundaryKey,
                child: IgnorePointer(
                  ignoring: blockChild,
                  // Always present, so toggling never rebuilds the viewer.
                  child: MediaQuery(
                    data: enabled
                        ? media.copyWith(gestureSettings: _viewerGestures)
                        : media,
                    child: child,
                  ),
                ),
              ),
            ),
            if (turning != null && revealed == null)
              IgnorePointer(
                key: const ValueKey('flip-fallback-cover'),
                child: ColoredBox(
                  color: around,
                  child: RawImage(image: turning, fit: BoxFit.contain),
                ),
              )
            else if (turning == null && revealed != null)
              IgnorePointer(
                key: const ValueKey('flip-held-page'),
                child: ColoredBox(
                  color: around,
                  child: RawImage(image: revealed, fit: BoxFit.contain),
                ),
              )
            else if (turning != null && revealed != null)
              IgnorePointer(
                key: const ValueKey('flip-layer'),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: curl
                        ? _CurlPainter(
                            progress: progress,
                            pose: pose ?? _restPose,
                            shot: turning,
                            shotFitted: imageFitted,
                            neighbor: revealed,
                            forward: forward,
                            blank: blank,
                            around: around,
                          )
                        : _SlidePainter(
                            progress: progress,
                            shot: turning,
                            shotFitted: imageFitted,
                            neighbor: revealed,
                            forward: forward,
                            around: around,
                          ),
                  ),
                ),
              ),
            if (enabled)
              Positioned.fill(
                key: const ValueKey('flip-gestures'),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => onTouchDown(),
                  child: MediaQuery(
                    data: media.copyWith(gestureSettings: _gestures),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: !tapZones
                          ? null
                          : (d) {
                              final x = d.localPosition.dx;
                              if (x < width * _tapZone) {
                                onTapZone(false);
                              } else if (x > width * (1 - _tapZone)) {
                                onTapZone(true);
                              }
                            },
                      onScaleStart: onScaleStart,
                      onScaleUpdate: (d) =>
                          onScaleUpdate(d, constraints.biggest),
                      onScaleEnd: onScaleEnd,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Draws one sheet. The viewer snapshot covers the whole area; a
/// pre-rendered page is fitted inside it on the color the viewer shows
/// around a page.
void _paintSheet(
  Canvas canvas,
  Size size,
  ui.Image image,
  Color around, {
  required bool fitted,
  double opacity = 1,
}) {
  final paint = Paint()
    ..filterQuality = FilterQuality.low
    ..color = Color.fromRGBO(0, 0, 0, opacity);
  final src = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  final area = Offset.zero & size;
  if (!fitted) {
    canvas.drawImageRect(image, src, area, paint);
    return;
  }
  if (opacity >= 1) canvas.drawRect(area, Paint()..color = around);
  final scale = math.min(size.width / src.width, size.height / src.height);
  final dst = Rect.fromCenter(
    center: area.center,
    width: src.width * scale,
    height: src.height * scale,
  );
  canvas.drawImageRect(image, src, dst, paint);
}

/// Paper page turn. The sheet is bound at the left edge. The part beyond
/// the fold line is folded back over the page (its back side shows), and
/// the page underneath appears where it was.
///
/// Forward: the current page curls away to the left. Backward: the previous
/// page curls back in from the left, the same motion run in reverse.
class _CurlPainter extends CustomPainter {
  _CurlPainter({
    required this.progress,
    required this.pose,
    required this.shot,
    required this.shotFitted,
    required this.neighbor,
    required this.forward,
    required this.blank,
    required this.around,
  }) : super(repaint: Listenable.merge([progress, pose]));

  final Animation<double> progress;
  final ValueListenable<CurlPose> pose;

  /// The page the turn started on: a viewer snapshot, or a page bitmap
  /// if [shotFitted].
  final ui.Image shot;
  final bool shotFitted;

  /// Pre-rendered page the turn ends on.
  final ui.Image neighbor;
  final bool forward;

  /// Paper color (back of the page) and the color around a page.
  final Color blank;
  final Color around;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final area = Offset.zero & size;

    // q: how far the top sheet is curled away (0 flat, 1 gone).
    final t = progress.value;
    final q = forward ? t : 1 - t;
    final top = forward ? shot : neighbor;
    final bottom = forward ? neighbor : shot;
    final topFitted = forward ? shotFitted : true;
    final bottomFitted = forward ? true : shotFitted;

    canvas.save();
    canvas.clipRect(area);
    _paintSheet(canvas, size, bottom, around, fitted: bottomFitted);

    if (q <= 0.001) {
      _paintSheet(canvas, size, top, around, fitted: topFitted);
      canvas.restore();
      return;
    }
    if (q >= 0.999) {
      canvas.restore();
      return;
    }

    // Fold line: through (foldX, pivotY), leaning by `lean` (x per unit y).
    // It may never cross the bound edge, so the lean dies out near the end.
    final foldX = w * (1 - q);
    final pivotY = pose.value.pivotY.clamp(0.0, 1.0) * h;
    final reach = math.max(pivotY, h - pivotY);
    final maxLean = foldX / reach;
    final lean = (pose.value.tilt * math.min(1.0, q * 4))
        .clamp(-maxLean, maxLean)
        .toDouble();
    final xTop = foldX - pivotY * lean;
    final xBottom = foldX + (h - pivotY) * lean;

    final far = Path()
      ..moveTo(xTop, 0)
      ..lineTo(w + h, 0)
      ..lineTo(w + h, h)
      ..lineTo(xBottom, h)
      ..close();
    final keep = Path()
      ..moveTo(-1, 0)
      ..lineTo(xTop, 0)
      ..lineTo(xBottom, h)
      ..lineTo(-1, h)
      ..close();

    final len = math.sqrt(lean * lean + 1);
    final ux = lean / len; // along the fold
    final uy = 1 / len;
    final normal = Offset(uy, -ux); // towards the folded-away side
    final fold = Offset(foldX, pivotY);

    // Mirror across the fold line.
    final a = 2 * ux * ux - 1;
    final b = 2 * ux * uy;
    final d = 2 * uy * uy - 1;
    final mirror = Float64List(16)
      ..[0] = a
      ..[1] = b
      ..[4] = b
      ..[5] = d
      ..[10] = 1
      ..[12] = foldX - a * foldX - b * pivotY
      ..[13] = pivotY - b * foldX - d * pivotY
      ..[15] = 1;

    final lifted = w - foldX; // width of the folded-back part
    final strength = math.min(1.0, (1 - q) * 3) * math.min(1.0, q * 6);

    // Shadow of the lifted page on the page underneath.
    canvas.save();
    canvas.clipPath(far);
    canvas.drawRect(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          fold,
          fold + normal * math.max(12.0, math.min(lifted, w * 0.3)),
          [Color.fromRGBO(0, 0, 0, 0.38 * strength), const Color(0x00000000)],
        ),
    );
    canvas.restore();

    // The part of the top sheet still lying flat.
    canvas.save();
    canvas.clipPath(keep);
    _paintSheet(canvas, size, top, around, fitted: topFitted);
    canvas.restore();

    final flap = Path.combine(
      PathOperation.intersect,
      far,
      Path()..addRect(area),
    ).transform(mirror);

    // Shadow of the folded-back part on the flat part.
    canvas.save();
    canvas.clipPath(keep);
    canvas.drawPath(
      flap,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 0.32 * strength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.restore();

    // Back of the page: paper with the print faintly showing through.
    canvas.save();
    canvas.transform(mirror);
    canvas.clipRect(area);
    canvas.clipPath(far);
    canvas.drawRect(area, Paint()..color = blank);
    _paintSheet(canvas, size, top, around, fitted: topFitted, opacity: 0.1);
    canvas.restore();

    // Roundness of the bend: dark in the crease, a soft highlight, and a
    // darker free edge.
    canvas.save();
    canvas.clipPath(flap);
    canvas.drawRect(
      flap.getBounds(),
      Paint()
        ..shader = ui.Gradient.linear(
          fold,
          fold - normal * math.max(1.0, lifted),
          const [
            Color(0x47000000),
            Color(0x00000000),
            Color(0x1AFFFFFF),
            Color(0x00000000),
            Color(0x24000000),
          ],
          const [0, 0.16, 0.42, 0.78, 1],
        ),
    );
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CurlPainter old) =>
      old.shot != shot ||
      old.shotFitted != shotFitted ||
      old.neighbor != neighbor ||
      old.forward != forward ||
      old.blank != blank ||
      old.around != around ||
      old.progress != progress ||
      old.pose != pose;
}

/// Plain slide: the current page moves out, the next one follows it in.
class _SlidePainter extends CustomPainter {
  _SlidePainter({
    required this.progress,
    required this.shot,
    required this.shotFitted,
    required this.neighbor,
    required this.forward,
    required this.around,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final ui.Image shot;
  final bool shotFitted;
  final ui.Image neighbor;
  final bool forward;
  final Color around;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final area = Offset.zero & size;
    final sign = forward ? -1.0 : 1.0;
    final moved = progress.value * size.width;

    canvas.save();
    canvas.clipRect(area);
    canvas.drawRect(area, Paint()..color = around);

    canvas.save();
    canvas.translate(sign * moved, 0);
    _paintSheet(canvas, size, shot, around, fitted: shotFitted);
    canvas.restore();

    canvas.save();
    canvas.translate(sign * (moved - size.width), 0);
    _paintSheet(canvas, size, neighbor, around, fitted: true);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SlidePainter old) =>
      old.shot != shot ||
      old.shotFitted != shotFitted ||
      old.neighbor != neighbor ||
      old.forward != forward ||
      old.around != around ||
      old.progress != progress;
}
