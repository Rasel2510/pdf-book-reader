import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final dictionaryProvider = Provider<DictionaryService>(
  (ref) => DictionaryService(),
);

/// Short English meanings from the free dictionaryapi.dev (no key needed).
/// Needs internet; every failure just returns null.
class DictionaryService {
  static final _single = RegExp(r"^[A-Za-z][A-Za-z'’-]{0,39}$");

  /// Returns one lookup-ready word, removing punctuation around a selection.
  static String? lookupWord(String text) {
    final word = text.trim().replaceAll(
      RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'),
      '',
    );
    return _single.hasMatch(word) ? word : null;
  }

  /// Only single words are looked up (not phrases or sentences).
  static bool canLookUp(String text) => lookupWord(text) != null;

  Future<String?> lookup(String word) async {
    final lookupWord = DictionaryService.lookupWord(word);
    if (lookupWord == null) return null;
    final w = lookupWord.toLowerCase().replaceAll('’', "'");

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client.getUrl(
        Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/$w'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      return parseDefinition(body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// First usable definition in a dictionaryapi.dev response, as
/// "(noun) the definition", or null.
String? parseDefinition(String body) {
  try {
    final data = jsonDecode(body);
    if (data is! List) return null;
    for (final entry in data) {
      final meanings = entry is Map ? entry['meanings'] : null;
      if (meanings is! List) continue;
      for (final meaning in meanings) {
        if (meaning is! Map) continue;
        final defs = meaning['definitions'];
        if (defs is! List || defs.isEmpty) continue;
        final first = defs.first;
        final text = first is Map ? first['definition'] : null;
        if (text is! String || text.trim().isEmpty) continue;
        final pos = meaning['partOfSpeech'];
        return pos is String && pos.isNotEmpty
            ? '($pos) ${text.trim()}'
            : text.trim();
      }
    }
  } catch (_) {}
  return null;
}
