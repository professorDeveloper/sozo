import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/core/error/result.dart';
import '../entities/media_resolve_entity.dart';
import '../repositories/detail_repository.dart';

class ResolveMediaUseCase {
  final DetailRepository repository;
  const ResolveMediaUseCase(this.repository);

  /// How long extraction may take before it is called a failure.
  ///
  /// Nothing downstream had a deadline: an extension that accepts the call and
  /// never answers — a source running its own local server that stops
  /// responding, a scraper waiting on a host that never closes the socket —
  /// left "Extracting media…" on screen for as long as the screen was open,
  /// with no error and no way out but Back.
  ///
  /// Generous on purpose. A chain of three redirects through a slow host is
  /// ordinary and legitimately takes twenty seconds; this is the line between
  /// slow and hung, not a performance target.
  static const Duration deadline = Duration(seconds: 75);

  Future<Result<MediaResolveEntity>> call({
    required String ref,
    required String provider,
    String? lang,
  }) async {
    try {
      return await repository
          .resolveMedia(ref: ref, provider: provider, lang: lang)
          .timeout(deadline);
    } on TimeoutException {
      return Failure(Exception('player.resolve_timeout'.tr()));
    }
  }
}
