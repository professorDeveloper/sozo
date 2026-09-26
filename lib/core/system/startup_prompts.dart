/// The prompts the app raises on its own — an available update, the "open
/// links in Sozo" offer — one at a time, and at most one per launch.
///
/// Each used to be started from the same first frame, independently, so on a
/// fresh install the update dialog and the deep-link sheet opened on top of
/// each other the moment onboarding ended. A queue fixes the stacking; the
/// per-launch limit keeps a second prompt from following the first straight
/// away, which reads just as badly.
abstract final class StartupPrompts {
  static Future<void> _chain = Future<void>.value();
  static bool _shownThisLaunch = false;

  /// Runs [prompt] after any prompt already running. [prompt] answers whether
  /// it showed anything. [always] is for what must be seen regardless of
  /// what came before (a forced update).
  static Future<void> run(
    Future<bool> Function() prompt, {
    bool always = false,
  }) {
    final next = _chain.then((_) async {
      if (_shownThisLaunch && !always) return;
      if (await prompt()) _shownThisLaunch = true;
    }).catchError((Object _) {});
    _chain = next;
    return next;
  }
}
