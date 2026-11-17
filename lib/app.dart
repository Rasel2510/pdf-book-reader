import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/library/library_screen.dart';
import 'features/settings/page_tint_controller.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The whole app goes dark with the reader's Night page, so a dark page
    // is not framed by bright bars, sheets and lists.
    final night = ref.watch(pageTintProvider.select((tint) => tint.isDark));
    if (AppColors.useNight(night)) _rebuildAll(context);

    return MaterialApp(
      title: 'Paperleaf Reader',
      debugShowCheckedModeBanner: false,
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
