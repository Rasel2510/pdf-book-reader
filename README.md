# Paperleaf Reader

Offline PDF reader: one page per screen, swipe to turn, highlights,
bookmarks, saved words, and reading progress.

The Android launcher name is **Paperleaf Reader**. Its launcher icon is an
original, shaded hardback-book image, with the same artwork on the simple
paper-colored Flutter splash screen. Hiding the reader controls leaves system
bars visible so the PDF viewport stays fixed.

Requires a recent stable Flutter (Dart 3.10 or newer).

## Build the APK

    flutter pub get
    flutter build apk --release

APK: build/app/outputs/flutter-apk/app-release.apk

Smaller, faster-installing APK for a real phone:

    flutter build apk --release --split-per-abi

The split build creates one APK per CPU architecture in
`build/app/outputs/flutter-apk/`.

Judge smoothness only in profile or release mode, never in debug:

    flutter run --profile

If a version fails to resolve, run `flutter pub upgrade --major-versions`.

## Notes
- Home screen is a bookshelf: cover, progress bar and page count per book.
- Each book has its own saved progress, bookmarks, highlights and words (menu on the cover).
- Imported PDFs are copied into app storage (originals are untouched).
- Highlights are written into the app copy of the PDF and listed in Notes.
- To use those PDF highlights in another reader, open the reader menu and
  choose **Save annotated PDF**, then save the file somewhere that app can
  access and open that saved PDF there. Other readers must support PDF text
  markup annotations to display the highlights.
- Scanned (image-only) PDFs have no selectable text, so they cannot be highlighted.
- Syncfusion PDF viewer is free under the Community License for individuals
  and small companies.

## Copying words and highlights
Notes screen (list icon in the reader, or "Highlights & notes" on a book's
menu in the library), tabs Words and Highlights:
- Copy icon on a row, or long-press the row: copies that one entry (full text).
- "Copy all" at the top: copies every entry in the tab. Words go one per
  line; highlights are separated by a blank line.
Bookmarks are only page numbers, so they have no copy button.

## Page turn
Reading settings (sliders icon) -> Page turn:
- Pages change horizontally only. Vertical swipes do not turn pages.
- Book flip: swipe left/right and the page swings like a real book page, or
  tap the left/right edge of the screen. Swipes made while a turn is still
  finishing are queued. Swiping past the first/last page pushes the page
  sideways and springs back. Use the zoom button to enter zoom mode, then
  pinch and pan; reset zoom to resume page-flip gestures.
- Slide: classic swipe with pinch zoom.
Saved in shared preferences.

How the flip works (lib/features/reader/):
- flip_controller.dart: all logic (drag, snap, animation, hand-off). Owned by
  the reader screen.
- flip_pager.dart: view only, values and callbacks.
- lib/core/page_render_service.dart: pre-renders the neighbour pages with
  pdfx so the page under the turning page is ready. If a page is not ready
  the flip falls back to moving the viewer underneath.
Tuning: `_viewerSettle` in flip_controller.dart (flash at the end of a turn),
`_tapZone` in flip_pager.dart (edge tap width).

## Page color
Reading settings (sliders icon, library or reader) sets the PDF page color: White, Cream, Sepia,
Old book, Sage, Night. Saved in shared preferences and applied to all books.
Add a color in lib/core/theme/page_tint.dart.

## Look and feel
Retro paper theme: warm cream background, ink outlines, hard offset shadows.
Fonts are bundled (works offline): Abril Fatface (OFL) and Special Elite
(Apache 2.0). Licenses are in assets/fonts/.
Colors and fonts live in lib/core/theme/, shared widgets in lib/core/widgets/.

## Performance notes
State management is Riverpod (`flutter_riverpod`). Rules the code follows:
- Persistent data lives in providers: library (`library_controller.dart`),
  bookmarks per book (`notes_providers.dart`, in memory, optimistic writes),
  highlights/words per book, page color, page turn.
- Reader screen: `build` runs only when page color or turn style changes.
  Current page, bookmark icon, text selection and "unsaved highlights" are
  small listenables, so a page turn never rebuilds the PDF viewer.
- Page changes reuse the existing PDF viewer and update only page-dependent
  controls; changing the turn style is the only setting that replaces it.
- Page progress is written once after 0.7 s without a page change (and on
  exit / app pause), not on every page.
- Highlights go to the DB at once; the PDF file is rewritten 3 s after the
  last highlight, on app pause, or before leaving the reader.
- Flip: the viewer moves to the new page while the page is still turning
  (hidden under the pre-rendered bitmap); the overlay only waits for what is
  left of `_viewerSettle` in flip_controller.dart.
- Page color is baked into the pre-rendered bitmaps once, so the animation
  draws plain images (no color-filter pass per frame).
- Pre-render window follows the reader (`PageRenderService.focus`); jobs for
  pages the reader already passed are skipped.
- DB has indexes on highlights/words by book (schema version 4).

## Features added later
- **Search in book:** magnifier in the reader. Type, press search, use the
  arrows to move between matches (count shown as 3/12). Back closes search.
- **Contents:** reader menu (three dots) > Contents. Uses the PDF's own
  bookmarks; PDFs without any say so.
- **Go to page:** reader menu > Go to page (slider).
- **Highlight colors:** four dots above the buttons while text is selected.
  The color is also shown on the Notes list.
- **Delete highlight:** Notes opened from the reader show a delete icon on
  highlights; it also removes the mark from the page.
- **Word meanings:** "Save" fetches the meaning in the background; "Define"
  shows it first. Words tab: look-up button for words saved offline, and the
  "..." menu copies words + meanings or CSV (word, meaning, page).
- **Reading stats:** library menu > Reading stats (streak, today, last 7 days,
  totals).
- **Rename and sort books:** book menu > Rename; library menu > sort.
- **Keep screen on:** Reading settings > Keep screen on (default on).

Dictionary lookups use the internet. The Android release manifest already
declares the required internet permission.

## Version-sensitive Syncfusion calls
Contents uses `jumpToBookmark` through `dynamic` for compatibility with
viewer versions that do not expose that method. If opening a section does
nothing, see `reader_screen.dart` and `toc.dart`.
