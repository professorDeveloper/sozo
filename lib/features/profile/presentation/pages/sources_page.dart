import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/system/extension_dns.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/features/aniyomi/presentation/pages/aniyomi_sources_page.dart';
import 'package:soplay/features/cloudstream/presentation/pages/cloudstream_sources_page.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/presentation/pages/mangayomi_sources_page.dart';
import 'package:soplay/features/extensions/presentation/pages/source_catalog_page.dart';
import 'package:soplay/features/manga/presentation/pages/manga_sources_page.dart';
import 'package:soplay/features/profile/presentation/widgets/provider_quick_switch.dart';
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
        title: 'profile.mangayomi_sources'.tr(),
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
        // On this page rather than in general settings: it changes how SOURCE
        // traffic resolves and nothing else, and putting it beside the sources
        // is what makes that obvious without a paragraph.
        if (ExtensionDns.isSupported) ...[
          const SizedBox(height: 20),
          SettingsLabel('settings.dns_title'.tr()),
          const SettingsCard(children: [_DnsTile()]),
          SettingsFootnote('settings.dns_subtitle'.tr()),
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
          // Shows the current source, so it changes the current source —
          // the same sheet the home chip and the profile hub open. The full
          // providers page is still one row down inside it, where managing
          // rather than picking belongs.
          onTap: () => openProviderQuickSwitch(context),
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


/// Which resolver the extension runtimes use.
///
/// Reads the platform side rather than a stored preference, so what it shows is
/// what is actually in force. Those differ when a resolver cannot be built —
/// the app falls back to the system one rather than losing name resolution
/// entirely, and a row claiming Cloudflare over a system lookup would be a lie.
class _DnsTile extends StatefulWidget {
  const _DnsTile();

  @override
  State<_DnsTile> createState() => _DnsTileState();
}

class _DnsTileState extends State<_DnsTile> {
  DnsProvider _current = DnsProvider.system;

  @override
  void initState() {
    super.initState();
    ExtensionDns.current().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  Future<void> _pick() async {
    final chosen = await showAdaptiveModal<DnsProvider>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  'settings.dns_title'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            for (final p in DnsProvider.values)
              ListTile(
                title: Text(p.labelKey.tr()),
                trailing: p == _current
                    ? Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheet).pop(p),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final applied = await ExtensionDns.apply(chosen);
    if (!mounted) return;
    setState(() => _current = applied);
    // Only when it did not take. Announcing every success would be noise;
    // silently showing "System default" after somebody picked Cloudflare would
    // be a mystery.
    if (applied != chosen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.dns_fallback'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsNavTile(
      icon: Icons.dns_outlined,
      title: 'settings.dns_title'.tr(),
      value: _current.labelKey.tr(),
      onTap: _pick,
    );
  }
}
