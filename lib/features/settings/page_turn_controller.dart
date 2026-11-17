import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';

enum PageTurn {
  flip('Book flip'),
  slide('Slide');

  const PageTurn(this.label);

  final String label;
}

final pageTurnProvider = NotifierProvider<PageTurnController, PageTurn>(
  PageTurnController.new,
);

/// Global page-turn style, saved in shared preferences.
class PageTurnController extends Notifier<PageTurn> {
  static const _key = 'page_turn';

  @override
  PageTurn build() {
    final saved = ref.read(sharedPrefsProvider).getString(_key);
    return PageTurn.values.asNameMap()[saved] ?? PageTurn.flip;
  }

  Future<void> select(PageTurn turn) async {
    state = turn;
    await ref.read(sharedPrefsProvider).setString(_key, turn.name);
  }
}
