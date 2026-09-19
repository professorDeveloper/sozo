import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/tracker/presentation/pages/tracker_links_page.dart';

/// The AniList side of [TrackerLinksPage]. Kept as its own route so the screen
/// is named for what the user asked for, not for how it is implemented.
class AnilistLinksPage extends StatelessWidget {
  const AnilistLinksPage({super.key});

  @override
  Widget build(BuildContext context) => TrackerLinksPage(
    store: getIt<AnilistLinkStore>(),
    title: 'anilist.linked_titles'.tr(),
    accent: kAnilistBlue,
  );
}
