import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/widgets/provider_quick_switch.dart';

/// Which source each picked mode should start on, decided the way a mode
/// switch decides it ([pickSourceForMode]).
///
/// A mode that already remembers a source keeps it. A reading mode with no
/// reader installed lands on its AniList catalogue rather than an empty home.
/// [select] is set only when the app is not already in the primary mode.
({Map<ContentMode, String> remember, String? select}) planTasteSources({
  required List<ContentMode> modes,
  required String? Function(ContentMode mode) remembered,
  required String currentId,
  required List<ProviderEntity>? usable,
  required Set<String> favorites,
}) {
  final remember = <ContentMode, String>{};
  final target = <ContentMode, String>{};
  for (final mode in modes) {
    final kept = remembered(mode);
    if (kept != null && kept.isNotEmpty) {
      target[mode] = kept;
      continue;
    }
    // Watch always has sources; before the list has loaded there is nothing
    // better to choose than the one already current.
    if (usable == null && mode == ContentMode.video) continue;
    final pick = pickSourceForMode(
      mode: mode,
      remembered: '',
      currentId: currentId,
      candidates: [
        for (final p in usable ?? const <ProviderEntity>[])
          if (p.id.contentMode == mode) p,
      ],
      favorites: favorites,
    );
    remember[mode] = pick.id;
    target[mode] = pick.id;
  }
  final primary = modes.isEmpty ? null : modes.first;
  final select = primary == null || currentId.contentMode == primary
      ? null
      : target[primary];
  return (remember: remember, select: select);
}
