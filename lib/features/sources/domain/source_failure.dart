import 'package:easy_localization/easy_localization.dart';

/// What a source failure says, and what it says underneath.
///
/// An extension reports in the only vocabulary it has — `HttpException: HTTP
/// error 404`, `InvocationTargetException`, `UnknownHostException` — and that
/// string went to the screen unaltered. It is precise and it is useless: the
/// reader cannot tell "this site shut down" from "you are offline" from "this
/// source needs a newer app", and those want three different reactions.
///
/// So the recognised cases get a sentence, and the raw line moves underneath
/// where it still helps a bug report. The unrecognised ones are shown as they
/// were, because a wrong plain-language guess is worse than a technical truth.
class SourceFailure {
  const SourceFailure({required this.headline, this.detail});

  final String headline;

  /// The original message, when the headline is a translation of it rather
  /// than the thing itself.
  final String? detail;

  static SourceFailure of(String? raw) {
    // "Exception: " is Dart's own toString talking, not the source. It was
    // reaching the screen twice — once in the headline and once in the line
    // under it.
    var text = (raw ?? '').trim();
    for (final prefix in const ['Exception: ', 'PlatformException: ']) {
      while (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
      }
    }
    if (text.isEmpty) return SourceFailure(headline: 'search.source_failed'.tr());
    final lower = text.toLowerCase();

    // The site answered, and said no. 404 and 410 on a source's own landing
    // page mean it moved or closed — by far the most common way a source dies.
    if (_hasCode(lower, 404) || _hasCode(lower, 410)) {
      return SourceFailure(
        headline: 'sources.fail_gone'.tr(),
        detail: text,
      );
    }
    // Blocked rather than missing: Cloudflare, a region lock, a bot check.
    if (_hasCode(lower, 403) ||
        _hasCode(lower, 401) ||
        lower.contains('cloudflare')) {
      return SourceFailure(
        headline: 'sources.fail_blocked'.tr(),
        detail: text,
      );
    }
    if (_hasCode(lower, 429) || lower.contains('rate limit')) {
      return SourceFailure(
        headline: 'sources.fail_rate_limited'.tr(),
        detail: text,
      );
    }
    // Never reached it at all.
    if (lower.contains('unknownhost') ||
        lower.contains('unable to resolve host') ||
        lower.contains('sockettimeout') ||
        lower.contains('timeoutexception') ||
        lower.contains('connectexception') ||
        lower.contains('failed to connect') ||
        lower.contains('sslexception') ||
        lower.contains('sslhandshake')) {
      return SourceFailure(
        headline: 'sources.fail_unreachable'.tr(),
        detail: text,
      );
    }
    // The extension and the app disagree about the API between them.
    if (lower.contains('nosuchmethod') ||
        lower.contains('noclassdeffound') ||
        lower.contains('classnotfound') ||
        lower.contains('abstractmethod') ||
        lower.contains('nosuchfield') ||
        lower.contains('incompatibleclasschange')) {
      return SourceFailure(
        headline: 'sources.fail_incompatible'.tr(),
        detail: text,
      );
    }
    // The source's own code threw. Not something the reader can act on beyond
    // trying another source, and saying so beats reprinting a Java class name.
    if (lower.contains('invocationtarget') ||
        lower.contains('nullpointer') ||
        lower.contains('indexoutofbounds') ||
        lower.contains('illegalstate') ||
        lower.contains('illegalargument')) {
      return SourceFailure(
        headline: 'sources.fail_broken'.tr(),
        detail: text,
      );
    }
    return SourceFailure(headline: text);
  }

  /// Whether [lower] carries HTTP status [code] as its own token.
  ///
  /// Substring matching would read a 404 out of a content id, and a source that
  /// works would be reported as gone.
  static bool _hasCode(String lower, int code) =>
      RegExp('(^|[^0-9])$code([^0-9]|\$)').hasMatch(lower);
}
