import 'dart:async';

import 'package:flutter/services.dart';

/// PDFs another app hands to this one ("Open with" in a file manager, a
/// chat, the browser's downloads). The Android side copies the file into the
/// app's cache and keeps it until it is asked for here.
abstract final class IncomingPdf {
  static const _channel = MethodChannel('paperleaf/open_pdf');

  /// Calls [onPdf] for a PDF that is waiting now (the app was started by
  /// opening it) and for each one that arrives while the app runs. [path]
  /// is a copy in the cache that the receiver may delete; [name] is the
  /// file's name as the other app shows it.
  static void listen(void Function(String path, String name) onPdf) {
    Future<void> take() async {
      try {
        final data = await _channel.invokeMapMethod<String, String>(
          'takePending',
        );
        final path = data?['path'];
        if (path == null || path.isEmpty) return;
        onPdf(path, data?['name'] ?? 'Book.pdf');
      } catch (_) {
        // No Android side (tests, other platforms): nothing ever arrives.
      }
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pdfArrived') await take();
    });
    unawaited(take());
  }
}
