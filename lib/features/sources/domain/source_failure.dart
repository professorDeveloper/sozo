import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';

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
/// Which KIND of failure it was, for the callers that have to react to it
/// rather than print it.
///
/// A plain enum and not an icon: this is domain, and the two screens that draw
/// a failure disagreed about the picture for years precisely because each one
/// re-derived the kind from the raw string with its own list of substrings.
/// The kind is decided once, here, beside the sentence it goes with.
enum SourceFailureKind {
  /// The site answered, and it is not there any more — 404, 410.
  gone,

  /// Reached and refused: Cloudflare, a region lock, a bot check, 401/403.
  blocked,

  /// Asked too often.
  rateLimited,

  /// Never reached at all. The only kind that is genuinely about the
  /// reader's connection.
  unreachable,

  /// The extension and the app disagree about the API between them.
  incompatible,

  /// The extension and its own SITE disagree: the site changed its response
  /// and the installed version still expects the old one. Different from
  /// [incompatible] in the only way that matters — the fix is updating the
  /// source, not the app.
  outdated,

  /// The source's own code threw.
  broken,

  /// Nothing recognised it, so the raw line is the headline.
  unknown,
}

/// Equatable because blocs carry one in their state: two failures that say the
/// same thing are the same state, and without this every rebuild compared by
/// identity and reported a change.
class SourceFailure extends Equatable {
  const SourceFailure({
    required this.headline,
    this.detail,
    this.kind = SourceFailureKind.unknown,
  });

  final String headline;

  final SourceFailureKind kind;

  /// The original message, when the headline is a translation of it rather
  /// than the thing itself.
  final String? detail;

  @override
  List<Object?> get props => [headline, detail, kind];

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
    if (text.isEmpty) {
      return SourceFailure(headline: 'search.source_failed'.tr());
    }
    final lower = text.toLowerCase();

    // The site answered, and said no. 404 and 410 on a source's own landing
    // page mean it moved or closed — by far the most common way a source dies.
    if (_hasCode(lower, 404) || _hasCode(lower, 410)) {
      return SourceFailure(
        headline: 'sources.fail_gone'.tr(),
        detail: text,
        kind: SourceFailureKind.gone,
      );
    }
    // Blocked rather than missing: Cloudflare, a region lock, a bot check.
    if (_hasCode(lower, 403) ||
        _hasCode(lower, 401) ||
        lower.contains('cloudflare')) {
      return SourceFailure(
        headline: 'sources.fail_blocked'.tr(),
        detail: text,
        kind: SourceFailureKind.blocked,
      );
    }
    if (_hasCode(lower, 429) || lower.contains('rate limit')) {
      return SourceFailure(
        headline: 'sources.fail_rate_limited'.tr(),
        detail: text,
        kind: SourceFailureKind.rateLimited,
      );
    }
    // Never reached it at all.
    //
    // Two vocabularies, because a source failure arrives in whichever language
    // the layer that threw it speaks. The first group is the JVM's, from an
    // extension running on Android; the second is Dart's and Dio's, from the
    // app's own client. Only the first was here, so every failure raised on
    // the Dart side of the line — being offline, most of all — fell through to
    // `unknown` and put a `DioException` on the screen.
    if (lower.contains('unknownhost') ||
        lower.contains('unable to resolve host') ||
        lower.contains('sockettimeout') ||
        lower.contains('timeoutexception') ||
        lower.contains('connectexception') ||
        lower.contains('failed to connect') ||
        lower.contains('sslexception') ||
        lower.contains('sslhandshake') ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection error') ||
        lower.contains('connection refused') ||
        lower.contains('connection closed') ||
        lower.contains('connection reset') ||
        lower.contains('network is unreachable') ||
        lower.contains('no address associated') ||
        lower.contains('handshakeexception') ||
        lower.contains('timeout') ||
        lower.contains('timed out')) {
      return SourceFailure(
        headline: 'sources.fail_unreachable'.tr(),
        detail: text,
        kind: SourceFailureKind.unreachable,
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
        kind: SourceFailureKind.incompatible,
      );
    }
    // The extension is behind its own site.
    //
    // A Tachiyomi source parses the site's JSON into a declared shape, so when
    // the site adds or drops a field the installed extension throws
    // `MissingFieldException: Fields [artists, authors, ...] are required for
    // type with serial name '...MangaDto'` — measured, on a reader whose whole
    // home screen was that sentence. It is not the app, not the network and not
    // the site being down: the source needs a newer build, which its repo
    // usually already has.
    if (lower.contains('missingfield') ||
        lower.contains('serializationexception') ||
        lower.contains('jsondecodingexception') ||
        lower.contains('jsonconvertexception') ||
        lower.contains('unknown key') ||
        lower.contains('jsonsyntaxexception')) {
      return SourceFailure(
        headline: 'sources.fail_outdated'.tr(),
        detail: text,
        kind: SourceFailureKind.outdated,
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
        kind: SourceFailureKind.broken,
      );
    }
    // Nothing recognised it, so the raw line is the headline — minus the class
    // name in front of it, if a readable sentence follows. See [_unwrapJvm].
    return SourceFailure(headline: _unwrapJvm(text));
  }

  /// Drops a leading JVM class name when a readable sentence follows it.
  ///
  /// Some extensions write their message FOR the reader — a gallery source
  /// answers a browse with `java.lang.UnsupportedOperationException: Please
  /// enter a query in the format of gallery:{username}`, which is the most
  /// useful thing anything said about that screen. It arrived with a Java class
  /// name bolted to the front, so the one message written to be read looked
  /// like a crash.
  ///
  /// Only ever the headline, and only at the very end. Every classifier above
  /// keys on exactly these class names — `UnknownHostException`,
  /// `NullPointerException` — so unwrapping before them would hide from each
  /// rule the word it exists to match, and a source's own crash would come back
  /// as unrecognised.
  ///
  /// Prose only: something short, or with no space in it, is another identifier
  /// rather than a sentence, and there the class name is all the information
  /// there is.
  static String _unwrapJvm(String text) {
    final m = RegExp(
      r'^(?:[a-z][a-z0-9]*\.)+[A-Za-z][A-Za-z0-9_$.]*(?:Exception|Error)\s*:\s*(.+)$',
      dotAll: true,
    ).firstMatch(text);
    if (m == null) return text;
    // The message, never the stack under it.
    final rest = m.group(1)!.split('\n').first.trim();
    if (rest.length < 12 || !rest.contains(' ')) return text;
    return rest;
  }

  /// Whether [lower] carries HTTP status [code] as its own token.
  ///
  /// Substring matching would read a 404 out of a content id, and a source that
  /// works would be reported as gone.
  static bool _hasCode(String lower, int code) =>
      RegExp('(^|[^0-9])$code([^0-9]|\$)').hasMatch(lower);
}
