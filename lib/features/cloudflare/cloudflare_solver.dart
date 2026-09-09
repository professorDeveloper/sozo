import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/network/user_agent.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver_page.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';

Future<bool> requestCloudflareSolve(
  BuildContext context,
  String provider,
) async {
  if (Platform.isLinux) return false;
  if (provider.length < 4) return false;
  final id = provider.substring(3);

  // `my:` handled first, and separately: it is the one ecosystem that does not
  // run behind an Android host channel, so neither half of the work below fits
  // it. See [_solveForMangayomi].
  if (provider.startsWith('my:')) return _solveForMangayomi(context, id);

  Map<String, dynamic> info;
  if (provider.startsWith('an:')) {
    info = await AniyomiChannel.cloudflareInfo(id);
  } else if (provider.startsWith('mn:')) {
    info = await MangaChannel.cloudflareInfo(id);
  } else if (provider.startsWith('cs:')) {
    info = await CloudStreamChannel.cloudflareInfo(id);
  } else {
    return false;
  }

  final baseUrl = (info['baseUrl'] ?? '').toString();
  if (baseUrl.isEmpty) return false;
  final userAgent = (info['userAgent'] ?? '').toString();

  if (!context.mounted) return false;
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => CloudflareSolverPage(
        baseUrl: baseUrl,
        userAgent: userAgent,
      ),
    ),
  );
  return result ?? false;
}

/// The Mangayomi arm of [requestCloudflareSolve].
///
/// `my:` was simply missing from the dispatch above, so every Mangayomi source
/// fell through to `return false`: the "Solve Cloudflare" button on the home
/// error screen was drawn — `isCloudflareError` matches the message either way
/// — and pressing it opened nothing and said nothing.
///
/// It cannot reuse that path, in either half:
///
///  * **Target.** `an:`/`mn:`/`cs:` ask their Android host for a `baseUrl` and
///    a `userAgent` over a method channel. Mangayomi has no host; the answer
///    lives in Dart, in the installed-source store and in the one agent the
///    app presents.
///  * **Result.** Those three run their HTTP inside the Android hosts, which
///    share the system WebView's cookie jar — so the clearance is already
///    theirs the moment the page pops and `true` is the whole answer. Mangayomi
///    fetches through Dio, whose jar is a separate Dart object that never sees
///    a WebView cookie. Popping `true` here would have reloaded straight back
///    into the same challenge; the clearance has to be carried across by hand.
Future<bool> _solveForMangayomi(BuildContext context, String id) async {
  final runtime = getIt<MangayomiRuntime>();

  // The host that actually came back challenged beats the source's configured
  // baseUrl — an extension often reads from an API or CDN host its metadata
  // never mentions, and cf_clearance is scoped to the zone it was issued for.
  final host = runtime.dartFetch.pendingCfHost ??
      Uri.tryParse(runtime.store.sourceById(id)?.baseUrl ?? '')?.host;
  if (host == null || host.isEmpty) return false;

  if (!context.mounted) return false;
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => CloudflareSolverPage(
        // The zone root, not a deep link. Cloudflare clears a whole zone at
        // once, and the root is an ordinary HTML page — the URL that failed is
        // as likely to be JSON, which a WebView downloads instead of rendering.
        baseUrl: 'https://$host/',
        // Cloudflare binds cf_clearance to the exact agent that earned it, and
        // the replay goes out under kSozoUserAgent. Solving under any other
        // string earns a cookie the CDN then refuses.
        userAgent: kSozoUserAgent,
      ),
    ),
  );
  if (result != true) return false;

  // Reporting success without this would reload into the same challenge.
  return runtime.dartFetch.adoptSolvedClearance(host);
}

bool isCloudflareError(Object? error) {
  if (error == null) return false;
  final msg = error.toString().toLowerCase();
  return msg.contains('cloudflare') ||
      msg.contains('failed to bypass cloudflare');
}
