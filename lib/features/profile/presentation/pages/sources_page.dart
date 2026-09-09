import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/aniyomi/presentation/pages/aniyomi_sources_page.dart';
import 'package:soplay/features/cloudstream/presentation/pages/cloudstream_sources_page.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/presentation/pages/mangayomi_sources_page.dart';
import 'package:soplay/features/extensions/presentation/pages/source_catalog_page.dart';
import 'package:soplay/features/manga/presentation/pages/manga_sources_page.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Where content comes from: the active cloud provider, and the installable
/// extension ecosystems this platform can run.
class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  /// The extension rows this platform supports. Empty on a platform that runs
  /// none, so the caller can drop the card entirely.
  static List<Widget> extensionRows(BuildContext context) => <Widget>[
    // Ungated: the catalog is read from the backend, so it works everywhere;
    // what it can offer still depends on what this platform runs.
    SettingsNavTile(
      icon: Icons.translate_rounded,
      title: 'catalog.title'.tr(),
      subtitle: 'catalog.subtitle'.tr(),
      onTap: () => SourceCatalogPage.open(context),
    ),
    if (BridgeControl.canHost && CloudStreamChannel.isSupported)
      SettingsNavTile(
        leading: const SettingsTileLogo(
          url:
              'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRzeluIShlMnhgHeVHgTSkvsthvQEK2xaS5A&s',
          fallback: Icons.extension_outlined,
        ),
        title: 'profile.cloudstream_sources'.tr(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CloudStreamSourcesPage()),
        ),
      ),
    if (BridgeControl.canHost && AniyomiChannel.isSupported)
      SettingsNavTile(
        leading: const SettingsTileLogo(
          url:
              'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s',
          fallback: Icons.play_circle_outline,
        ),
        title: 'profile.aniyomi_sources'.tr(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AniyomiSourcesPage()),
        ),
      ),
    if (BridgeControl.canHost && MangaChannel.isSupported)
      SettingsNavTile(
        leading: const SettingsTileLogo(
          url:
              'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s',
          fallback: Icons.menu_book_outlined,
        ),
        title: 'manga.sources_title'.tr(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MangaSourcesPage()),
        ),
      ),
    // JavaScript extensions run on every platform, the only ecosystem that does.
    if (MangayomiRuntime.isSupported)
      SettingsNavTile(
        leading: const SettingsTileLogo(
          url:
              'https://raw.githubusercontent.com/kodjodevf/mangayomi/main/assets/app_icons/icon-red.png',
          fallback: Icons.javascript_outlined,
        ),
        title: 'Mangayomi Sources',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MangayomiSourcesPage()),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = extensionRows(context);
    return SettingsPageScaffold(
      title: 'profile.sources_title'.tr(),
      children: [
        SettingsLabel('profile.section_active_source'.tr()),
        const SettingsCard(children: [ProviderTile()]),
        SettingsFootnote('profile.active_source_footnote'.tr()),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 20),
          SettingsLabel('profile.section_extensions'.tr()),
          SettingsCard(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SettingsDivider(),
                rows[i],
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// The active provider in one row: logo, name, how many there are to choose
/// from. Opens the picker.
class ProviderTile extends StatelessWidget {
  const ProviderTile({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderBloc, ProviderState>(
      builder: (context, state) {
        final loaded = state is ProviderLoaded ? state : null;
        final current = loaded?.currentProvider;
        final name = current?.name ?? loaded?.currentProviderId ?? '—';
        final total = loaded?.providers.length ?? 0;
        return SettingsNavTile(
          icon: Icons.movie_filter_outlined,
          title: 'profile.provider'.tr(),
          valueLeading: current != null && current.image.isNotEmpty
              ? ProviderMark(url: current.image)
              : null,
          value: total > 0 ? '$name · $total' : name,
          onTap: () => context.push('/providers'),
        );
      },
    );
  }
}

/// A 22px provider logo that holds its slot while loading so the name next
/// to it does not slide when the image lands.
class ProviderMark extends StatelessWidget {
  const ProviderMark({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 22,
        height: 22,
        fit: BoxFit.cover,
        placeholder: (_, _) => const SizedBox(width: 22, height: 22),
        errorWidget: (_, _, _) => const SizedBox(width: 22, height: 22),
      ),
    );
  }
}
