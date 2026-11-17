import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';

final keepAwakeProvider = NotifierProvider<KeepAwakeController, bool>(
  KeepAwakeController.new,
);

/// Keep the screen on while a book is open (on by default).
class KeepAwakeController extends Notifier<bool> {
  static const _key = 'keep_awake';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_key) ?? true;

  Future<void> set(bool value) async {
    state = value;
    await ref.read(sharedPrefsProvider).setBool(_key, value);
  }
}
