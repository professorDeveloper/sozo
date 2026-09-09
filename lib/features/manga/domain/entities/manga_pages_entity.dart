import 'manga_page_entity.dart';

class MangaPagesEntity {
  final List<MangaPageEntity> pages;
  final Map<String, String> headers;

  /// A novel chapter's text, when this is a novel rather than a comic.
  ///
  /// Novel sources implement `getHtmlContent` and return one HTML document for
  /// the whole chapter; comic sources implement `getPageList` and return image
  /// urls. They are different shapes, so this carries both rather than
  /// pretending a chapter of prose is a list of pages — which is how novels
  /// used to arrive here as zero pages and an empty reader.
  final String? html;

  bool get isText => html != null && html!.trim().isNotEmpty;

  const MangaPagesEntity({
    required this.pages,
    required this.headers,
    this.html,
  });
}
