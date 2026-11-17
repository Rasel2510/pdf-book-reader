import 'dart:io';

/// A readable book title from a PDF's file name:
/// "15-05-2021-084550The-Alchemist-Paulo-Coelho" becomes
/// "The Alchemist Paulo Coelho".
String cleanBookTitle(String fileName) {
  final original = fileName.trim();
  var title = original;

  // A date, time or download number stuck on the front. Few digits are kept:
  // they may be the title itself ("1984", "2001 A Space Odyssey").
  final lead = RegExp(r'^[\d\s._()\[\]-]+').stringMatch(title) ?? '';
  if (RegExp(r'\d').allMatches(lead).length >= 6) {
    title = title.substring(lead.length);
  }

  // A copy number on the end: "Book (1)".
  title = title.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');

  // Underscores stand in for spaces. So do dashes, when the name has no
  // spaces at all (otherwise a dash is part of the title: "Spider-Man 2").
  title = title.replaceAll('_', ' ');
  if (!title.trim().contains(' ')) title = title.replaceAll('-', ' ');

  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  return title.isEmpty ? original : title;
}

/// Writes to a temp file first, then renames, so a crash cannot leave a
/// half-written PDF behind.
Future<void> writeBytesAtomic(String path, List<int> bytes) async {
  final tmp = File('$path.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(path);
}
