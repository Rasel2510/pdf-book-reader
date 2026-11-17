import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/incoming_pdf.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/models.dart';
import 'features/library/library_controller.dart';
import 'features/library/library_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/settings/page_tint_controller.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    IncomingPdf.listen((path, name) => unawaited(_openIncoming(path, name)));
  }

  /// A PDF another app handed over ("Open with"): it goes on the shelf
  /// (unless it is there already) and opens, whatever screen was showing.
  Future<void> _openIncoming(String path, String name) async {
    Book? book;
    var problem = 'Could not open that PDF.';
    try {
      book = await ref.read(libraryProvider.notifier).addIncoming(path, name);
    } on NotAPdfException {
      problem = 'That file is not a PDF, or it is damaged.';
    } catch (error, stackTrace) {
      debugPrint('Could not open an incoming PDF: $error\n$stackTrace');
    } finally {
      // The copy the Android side made; the shelf has its own by now.
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (!mounted) return;

    final opened = book;
    final navigator = _navigator.currentState;
    if (opened == null || navigator == null) {
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    // Back to the shelf first: a book that is open closes (it saves its
    // place as it goes), so there is never a reader on top of a reader.
    navigator.popUntil((route) => route.isFirst);
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(builder: (_) => ReaderScreen(book: opened)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The whole app goes dark with the reader's Night page, so a dark page
    // is not framed by bright bars, sheets and lists.
    final night = ref.watch(pageTintProvider.select((tint) => tint.isDark));
    if (AppColors.useNight(night)) _rebuildAll(context);

    return MaterialApp(
      title: 'Paperleaf Reader',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      theme: AppTheme.current,
      home: const LibraryScreen(),
    );
  }

  /// Widgets read [AppColors] when they build, and many of them are `const`
  /// or do not listen to the theme, so a theme change alone would leave them
  /// in the old colors. This asks every widget on screen to build again; no
  /// state is lost and the open screens stay open.
  static void _rebuildAll(BuildContext context) {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }
}
