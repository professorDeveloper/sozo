/// How long an extension call may take before the app stops waiting on it.
///
/// Nothing in either JS runtime was bounded, so a source that never answered
/// left the screen it was loading on its skeleton indefinitely. Generous rather
/// than tight: a single call can legitimately be several requests plus a
/// Cloudflare solve, and cutting a slow-but-working source off reads as the
/// same bug from the other side.
///
/// 40s was not generous enough for the worst honest case: a Cloudflare-gated
/// source (animepahe) spends up to 30s in [CfBypassService.solve] alone before
/// its first request even starts, and the catalog fetch still has to follow.
/// That timed out mid-solve and looked exactly like a dead provider.
const Duration kJsCallTimeout = Duration(seconds: 60);
