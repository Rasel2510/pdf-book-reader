import 'dart:io';

import 'package:pdfx/pdfx.dart' as pdfx;

/// Renders page 1 of [pdfPath] to a JPEG at [coverPath].
/// Returns the page count, or 0 if the PDF could not be read.
Future<int> createCover({
  required String pdfPath,
  required String coverPath,
}) async {
  try {
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    try {
      final page = await doc.getPage(1);
      try {
        const width = 400.0;
        final image = await page.render(
          width: width,
          height: width * page.height / page.width,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 85,
        );
        if (image != null) await File(coverPath).writeAsBytes(image.bytes);
      } finally {
        await page.close();
      }
      return doc.pagesCount;
    } finally {
      await doc.close();
    }
  } catch (_) {
    return 0;
  }
}
