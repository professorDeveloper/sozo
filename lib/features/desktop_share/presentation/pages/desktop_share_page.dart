import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/extensions/extension_bridge.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';

class DesktopSharePage extends StatefulWidget {
  const DesktopSharePage({super.key});

  @override
  State<DesktopSharePage> createState() => _DesktopSharePageState();
}

class _DesktopSharePageState extends State<DesktopSharePage> {
  BridgeStatus _status = const BridgeStatus(enabled: false, link: null);
  bool _busy = false;
  final TextEditingController _urlCtrl = TextEditingController();

  List<_ShareProvider> _providers = const [];
  final Set<String> _picked = <String>{};
  bool _shareAll = true;
  bool _loadingProviders = false;

  bool get _isHost => BridgeControl.canHost;

  bool get _isIosClient => !_isHost && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_isHost) {
      _initHost();
    } else {
      _urlCtrl.text = getIt<HiveService>().getBridgeUrl();
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _initHost() async {
    final status = await BridgeControl.getStatus();
    final selection = await BridgeControl.getSharedProviders();
    if (!mounted) return;
    setState(() {
      _status = status;
      _shareAll = selection.shareAll;
      _picked
        ..clear()
        ..addAll(selection.ids);
    });
    if (status.enabled) _loadProviders();
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final s = await BridgeControl.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _status = s;
      _busy = false;
    });
    if (value) _loadProviders();
  }

  Future<void> _loadProviders() async {
    if (_loadingProviders) return;
    setState(() => _loadingProviders = true);
    final out = <_ShareProvider>[];

    Future<void> add(
      String category,
      bool supported,
      Future<List<dynamic>> Function() fetch,
    ) async {
      if (!supported) return;
      try {
        for (final e in await fetch()) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final id = (m['id'] as String?)?.trim() ?? '';
          if (id.isEmpty) continue;
          out.add(_ShareProvider(
            id: id,
            name: (m['name'] as String?) ?? id,
            icon: (m['icon'] as String?),
            category: category,
          ));
        }
      } catch (_) {}
    }

    await add('cloudstream', CloudStreamChannel.isSupported,
        CloudStreamChannel.ensureLoaded);
    await add('aniyomi', AniyomiChannel.isSupported, AniyomiChannel.ensureLoaded);
    await add('manga', MangaChannel.isSupported, MangaChannel.ensureLoaded);

    if (!mounted) return;
    setState(() {
      _providers = out;
      _loadingProviders = false;
      if (_shareAll || _picked.isEmpty) {
        _picked
          ..clear()
          ..addAll(out.map((p) => p.id));
      }
    });
  }

  Future<void> _saveSelection() async {
    setState(() => _busy = true);
    await BridgeControl.setSharedProviders(
      shareAll: _shareAll,
      ids: _picked,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('desktop.saved_refresh_on_pc'.tr()),
      ),
    );
  }

  Future<void> _saveUrl() async {
    final url = _urlCtrl.text.trim();
    await getIt<HiveService>().setBridgeUrl(url);
    ExtensionBridge.setUrl(url);
    if (!mounted) return;
    if (url.isNotEmpty) context.read<ProviderBloc>().add(const ProviderLoad());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          url.isEmpty
              ? 'desktop.sources_turned_off'.tr()
              : 'desktop.saved_loading_sources'.tr(),
        ),
      ),
    );
  }

  void _refreshDesktopSources() {
    context.read<ProviderBloc>().add(const ProviderLoad());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('desktop.refreshing_sources'.tr())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: _isHost ? _hostBody() : _clientBody(),
      ),
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: isDesktopPlatform,
        title: Text(_isHost
            ? 'desktop.share_title'.tr()
            : _isIosClient
                ? 'ios.sources_title'.tr()
                : 'desktop.sources_title'.tr()),
      ),
      body: isDesktopPlatform
          ? MaxWidthBox(maxWidth: 560, child: body)
          : body,
    );
  }


  List<Widget> _hostBody() {
    final link = _status.link;
    return [
      _card(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'desktop.share_with_desktop'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'desktop.let_pc_use_sources'.tr(),
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch.adaptive(
                value: _status.enabled,
                activeThumbColor: AppColors.primary,
                onChanged: _toggle,
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (_status.enabled && link != null)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'desktop.your_link'.tr(),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      link,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    color: AppColors.primary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('desktop.link_copied'.tr())),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        )
      else if (_status.enabled)
        _card(
          child: Text(
            'desktop.no_wifi_address'.tr(),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      if (_status.enabled) ...[
        const SizedBox(height: 12),
        _sourcePickerCard(),
      ],
      const SizedBox(height: 16),
      _instructions([
        'desktop.step_host_same_wifi'.tr(),
        'desktop.step_host_turn_on'.tr(),
        'desktop.step_host_pick_sources'.tr(),
        'desktop.step_host_paste_on_pc'.tr(),
        'desktop.step_host_keep_open'.tr(),
      ]),
    ];
  }

  Widget _sourcePickerCard() {
    final total = _providers.length;
    final sharedCount = _shareAll ? total : _picked.length;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'desktop.sources_to_share'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'desktop.reload_from_phone'.tr(),
                icon: const Icon(Icons.refresh_rounded,
                    size: 20, color: AppColors.textSecondary),
                onPressed: _loadingProviders ? null : _loadProviders,
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _shareAll,
            activeThumbColor: AppColors.primary,
            title: Text(
              'desktop.share_all_sources'.tr(),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            subtitle: Text(
              _shareAll
                  ? 'desktop.every_source_shared'.tr()
                  : 'desktop.sharing_count'
                      .tr(args: ['$sharedCount', '$total']),
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
            onChanged: (v) => setState(() {
              _shareAll = v;
              if (v) {
                _picked
                  ..clear()
                  ..addAll(_providers.map((p) => p.id));
              }
            }),
          ),
          if (!_shareAll) ...[
            Divider(color: AppColors.divider, height: 16),
            _pickerControls(),
            const SizedBox(height: 4),
            _pickerList(),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy ? null : _saveSelection,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text('desktop.save_send_to_desktop'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerControls() {
    return Row(
      children: [
        Text(
          'desktop.n_selected'.tr(args: ['${_picked.length}']),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const Spacer(),
        TextButton(
          onPressed: _providers.isEmpty
              ? null
              : () => setState(
                  () => _picked.addAll(_providers.map((p) => p.id))),
          child: Text('desktop.select_all'.tr()),
        ),
        TextButton(
          onPressed: _picked.isEmpty ? null : () => setState(_picked.clear),
          child: Text('desktop.clear'.tr()),
        ),
      ],
    );
  }

  Widget _pickerList() {
    if (_loadingProviders) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_providers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'desktop.no_sources_yet'.tr(),
          style: const TextStyle(color: AppColors.textHint, fontSize: 13),
        ),
      );
    }

    const groups = [
      ('cloudstream', 'CloudStream', Icons.extension_outlined),
      ('aniyomi', 'Aniyomi', Icons.play_circle_outline),
      ('manga', 'Manga', Icons.menu_book_outlined),
    ];

    final children = <Widget>[];
    for (final (key, label, icon) in groups) {
      final items = _providers.where((p) => p.category == key).toList();
      if (items.isEmpty) continue;
      children.add(_groupHeader(icon, '$label · ${items.length}'));
      for (final p in items) {
        children.add(_providerCheck(p));
      }
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: Scrollbar(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: children,
        ),
      ),
    );
  }

  Widget _groupHeader(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textHint),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );

  Widget _providerCheck(_ShareProvider p) {
    final checked = _picked.contains(p.id);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppColors.primary,
      value: checked,
      onChanged: (v) => setState(() {
        if (v == true) {
          _picked.add(p.id);
        } else {
          _picked.remove(p.id);
        }
      }),
      secondary: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: (p.icon != null && p.icon!.isNotEmpty)
            ? Image.network(
                p.icon!,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _SourceIconFallback(),
              )
            : const _SourceIconFallback(),
      ),
      title: Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      ),
    );
  }


  List<Widget> _clientBody() {
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'desktop.phone_link'.tr(),
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'http://192.168.x.x:8765',
                hintStyle: TextStyle(color: AppColors.textHint),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _saveUrl,
                child: Text('general.save'.tr()),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _refreshDesktopSources,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('desktop.refresh_sources'.tr()),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _instructions(
        [
          (_isIosClient
                  ? 'ios.step_client_same_wifi'
                  : 'desktop.step_client_same_wifi')
              .tr(),
          'desktop.step_client_open_on_phone'.tr(),
          'desktop.step_client_choose_sources'.tr(),
          'desktop.step_client_copy_link'.tr(),
          'desktop.step_client_refresh'.tr(),
          'desktop.step_client_keep_open'.tr(),
          if (!_isIosClient) 'desktop.step_client_emulator'.tr(),
        ],
        descKey: _isIosClient ? 'ios.how_it_works_desc' : null,
      ),
    ];
  }


  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: child,
      );

  Widget _instructions(List<String> steps, {String? descKey}) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'desktop.how_it_works'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (descKey ?? 'desktop.how_it_works_desc').tr(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _ShareProvider {
  const _ShareProvider({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
  });

  final String id;
  final String name;
  final String? icon;
  final String category;
}

class _SourceIconFallback extends StatelessWidget {
  const _SourceIconFallback();

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.extension_outlined,
            size: 16, color: AppColors.textHint),
      );
}
