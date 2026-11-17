import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_book_reader/features/reader/flip_pager.dart';

void main() {
  testWidgets(
    'flip keeps the current page visible when no page is pre-rendered',
    (tester) async {
      final progress = AnimationController(vsync: const TestVSync());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 20, 20),
        Paint()..color = Colors.blue,
      );
      final image = await recorder.endRecording().toImage(20, 20);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 300,
            child: FlipPager(
              boundaryKey: GlobalKey(),
              enabled: true,
              progress: progress,
              image: image,
              under: null,
              blank: Colors.white,
              forward: true,
              edgeSign: 0,
              edgeTravel: 36,
              blockChild: false,
              onTouchDown: () {},
              onTapZone: (_) {},
              onScaleStart: (_) {},
              onScaleUpdate: (_, _) {},
              onScaleEnd: (_) {},
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('flip-fallback-cover')), findsOneWidget);
      expect(find.byKey(const ValueKey('flip-layer')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      image.dispose();
      progress.dispose();
    },
  );

  testWidgets('flip gesture layer forwards two-pointer scale updates', (
    tester,
  ) async {
    final progress = AnimationController(vsync: const TestVSync());
    var scaleUpdates = 0;
    var pointerCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: FlipPager(
            boundaryKey: GlobalKey(),
            enabled: true,
            progress: progress,
            image: null,
            under: null,
            blank: Colors.white,
            forward: true,
            edgeSign: 0,
            edgeTravel: 36,
            blockChild: false,
            onTouchDown: () {},
            onTapZone: (_) {},
            onScaleStart: (_) {},
            onScaleUpdate: (details, _) {
              scaleUpdates++;
              pointerCount = details.pointerCount;
            },
            onScaleEnd: (_) {},
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );

    final first = await tester.startGesture(const Offset(80, 100), pointer: 1);
    final second = await tester.startGesture(
      const Offset(220, 100),
      pointer: 2,
    );
    await first.moveTo(const Offset(40, 100));
    await second.moveTo(const Offset(260, 100));
    await tester.pump();

    expect(scaleUpdates, greaterThan(0));
    expect(pointerCount, 2);

    await first.up();
    await second.up();
    await tester.pumpWidget(const SizedBox.shrink());
    progress.dispose();
  });

  testWidgets('a sideways drag is claimed before the viewer can scroll', (
    tester,
  ) async {
    final progress = AnimationController(vsync: const TestVSync());
    final pages = PageController();
    var scaleUpdates = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 300,
          child: FlipPager(
            boundaryKey: GlobalKey(),
            enabled: true,
            progress: progress,
            image: null,
            under: null,
            blank: Colors.white,
            forward: true,
            edgeSign: 0,
            edgeTravel: 36,
            blockChild: false,
            onTouchDown: () {},
            onTapZone: (_) {},
            onScaleStart: (_) {},
            onScaleUpdate: (_, _) => scaleUpdates++,
            onScaleEnd: (_) {},
            // Stands in for the PDF viewer, which pages on a swipe too.
            child: PageView(
              controller: pages,
              children: const [
                ColoredBox(color: Colors.white),
                ColoredBox(color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(PageView), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(scaleUpdates, greaterThan(0));
    expect(pages.page, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    pages.dispose();
    progress.dispose();
  });

  for (final curl in [true, false]) {
    for (final forward in [true, false]) {
      testWidgets('paints a ${curl ? 'curl' : 'slide'} turn '
          '(${forward ? 'forward' : 'backward'}) at every stage', (
        tester,
      ) async {
        final progress = AnimationController(vsync: const TestVSync());
        Future<ui.Image> solid(Color color) {
          final recorder = ui.PictureRecorder();
          Canvas(
            recorder,
          ).drawRect(const Rect.fromLTWH(0, 0, 20, 30), Paint()..color = color);
          return recorder.endRecording().toImage(20, 30);
        }

        final image = await solid(Colors.blue);
        final under = await solid(Colors.red);

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 300,
              height: 400,
              child: FlipPager(
                boundaryKey: GlobalKey(),
                enabled: true,
                curl: curl,
                progress: progress,
                image: image,
                under: under,
                blank: Colors.white,
                forward: forward,
                edgeSign: 0,
                edgeTravel: 36,
                blockChild: true,
                onTouchDown: () {},
                onTapZone: (_) {},
                onScaleStart: (_) {},
                onScaleUpdate: (_, _) {},
                onScaleEnd: (_) {},
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        );

        expect(find.byKey(const ValueKey('flip-layer')), findsOneWidget);
        for (final value in [0.0, 0.02, 0.3, 0.5, 0.8, 0.98, 1.0]) {
          progress.value = value;
          await tester.pump();
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        image.dispose();
        under.dispose();
        progress.dispose();
      });
    }
  }
}
