import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';
import '../../core/theme/page_tint.dart';

final pageTintProvider = NotifierProvider<PageTintController, PageTint>(
  PageTintController.new,
);

/// Global reader page color, saved in shared preferences.
class PageTintController extends Notifier<PageTint> {
  static const _key = 'page_tint';

  @override
  PageTint build() {
    final saved = ref.read(sharedPrefsProvider).getString(_key);
    return PageTint.values.asNameMap()[saved] ?? PageTint.sepia;
  }

  Future<void> select(PageTint tint) async {
    state = tint;
    await ref.read(sharedPrefsProvider).setString(_key, tint.name);
  }
}
