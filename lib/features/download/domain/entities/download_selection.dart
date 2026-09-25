/// A concrete file/rendition, not the quality currently used by the player.
class DownloadSelection {
  const DownloadSelection({
    required this.url,
    required this.headers,
    this.height,
  });
  final String url;
  final Map<String, String> headers;
  final int? height;
}
