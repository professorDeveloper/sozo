part of 'player_page.dart';

/// Keeps a Jellyfin server told about what is playing, and starts where it
/// says the viewer left off. Every call is a no-op for any other source.
extension _PlayerJellyfin on _PlayerPageState {
  bool get _isJellyfin => widget.args.provider.startsWith('jf:');

  /// The server's resume point for [url], used only when the local history
  /// has none: a position this device saved is the fresher of the two.
  Duration _jellyfinResume(String? url, Duration local) {
    if (local > Duration.zero || !_isJellyfin || url == null) return local;
    return getIt<JellyfinReporter>().resumeFor(url);
  }

  void _jellyfinProgress({bool paused = false}) {
    if (!_isJellyfin) return;
    final url = _videoUrl;
    final c = _controller;
    if (url == null || c == null || !c.value.isInitialized) return;
    getIt<JellyfinReporter>().progress(
      url: url,
      position: c.value.position,
      paused: paused,
    );
  }

  void _jellyfinStop() {
    if (!_isJellyfin) return;
    final url = _videoUrl;
    if (url == null) return;
    final c = _controller;
    getIt<JellyfinReporter>().stop(
      url: url,
      position: c != null && c.value.isInitialized
          ? c.value.position
          : Duration.zero,
      failed: _errorMessage != null,
    );
  }
}
