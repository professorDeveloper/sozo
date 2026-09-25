import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_api.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_server_store.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_server.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_urls.dart';
import 'package:soplay/features/jellyfin/presentation/widgets/jellyfin_widgets.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Address and account, then which libraries get a row on Home.
///
/// Pops with the saved server, or null when abandoned. Passing [server] signs
/// in to it again with the address and user filled in.
class JellyfinConnectPage extends StatefulWidget {
  const JellyfinConnectPage({super.key, this.server});

  final JellyfinServer? server;

  static Future<JellyfinServer?> open(
    BuildContext context, {
    JellyfinServer? server,
  }) => Navigator.of(context).push<JellyfinServer>(
    MaterialPageRoute(builder: (_) => JellyfinConnectPage(server: server)),
  );

  @override
  State<JellyfinConnectPage> createState() => _JellyfinConnectPageState();
}

class _JellyfinConnectPageState extends State<JellyfinConnectPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _url = TextEditingController(
    text: widget.server?.baseUrl ?? '',
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.server?.userName ?? '',
  );
  final TextEditingController _password = TextEditingController();

  JellyfinApi get _api => getIt<JellyfinApi>();

  bool _testing = false;
  bool _signingIn = false;
  bool _saving = false;
  bool _obscure = true;
  String? _error;
  String? _ok;

  /// Set once signed in: the step moves on to libraries.
  JellyfinServer? _pending;
  List<Map<String, dynamic>> _libraries = const [];
  final Set<String> _hidden = {};

  bool get _busy => _testing || _signingIn || _saving;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateUrl(String? v) =>
      JellyfinUrls.normalizeBaseUrl(v ?? '').isEmpty
      ? 'jellyfin.error_url'.tr()
      : null;

  Future<void> _test() async {
    if (_validateUrl(_url.text) != null) {
      _form.currentState?.validate();
      return;
    }
    final base = JellyfinUrls.normalizeBaseUrl(_url.text);
    setState(() {
      _testing = true;
      _error = null;
      _ok = null;
    });
    final watch = Stopwatch()..start();
    try {
      final info = await _api.publicInfo(base);
      if (!mounted) return;
      setState(() {
        _ok = 'jellyfin.found_server'.tr(
          namedArgs: {
            'name': info.name,
            'version': info.version,
            'ms': '${watch.elapsedMilliseconds}',
          },
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = jellyfinErrorText(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _signIn() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final base = JellyfinUrls.normalizeBaseUrl(_url.text);
    setState(() {
      _signingIn = true;
      _error = null;
      _ok = null;
    });
    try {
      final info = await _api.publicInfo(base);
      final login = await _api.authenticate(
        base,
        _user.text.trim(),
        _password.text,
      );
      final previous = getIt<JellyfinServerStore>().byId(info.id);
      final server = JellyfinServer(
        id: info.id,
        name: info.name,
        baseUrl: base,
        userId: login.userId,
        userName: login.userName,
        accessToken: login.token,
        version: info.version,
        hiddenLibraries: previous?.hiddenLibraries ?? const [],
        addedAt: previous?.addedAt ?? DateTime.now(),
      );
      final views = await _api.views(server);
      if (!mounted) return;
      setState(() {
        _pending = server;
        _libraries = [
          for (final v in views)
            if (JellyfinBridge.playableCollections.contains(
                  v['CollectionType']?.toString(),
                ) &&
                v['Id'] != null)
              v,
        ];
        _hidden
          ..clear()
          ..addAll(server.hiddenLibraries);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = jellyfinErrorText(e, login: true));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _save() async {
    final pending = _pending;
    if (pending == null) return;
    setState(() => _saving = true);
    final known = {for (final l in _libraries) l['Id'].toString()};
    final server = pending.copyWith(
      hiddenLibraries: _hidden.where(known.contains).toList(),
    );
    await getIt<JellyfinServerStore>().save(server);
    if (!mounted) return;
    context.read<ProviderBloc>().add(const ProviderLoad(localOnly: true));
    Navigator.of(context).pop(server);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return PopScope(
      canPop: pending == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _pending = null);
      },
      child: SettingsPageScaffold(
        title: pending == null
            ? 'jellyfin.connect_title'.tr()
            : 'jellyfin.libraries_title'.tr(),
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: pending == null ? _formStep() : _libraryStep(pending),
          ),
        ],
      ),
    );
  }

  Widget _formStep() {
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          key: const ValueKey('form'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                const JellyfinLogo(size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'jellyfin.connect_intro'.tr(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            AuthTextField(
              controller: _url,
              hint: 'jellyfin.url_hint'.tr(),
              icon: Icons.dns_outlined,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.url],
              validator: _validateUrl,
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _user,
              hint: 'jellyfin.username_hint'.tr(),
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'jellyfin.error_username'.tr()
                  : null,
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _password,
              hint: 'jellyfin.password_hint'.tr(),
              icon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _signIn(),
              enabled: !_busy,
              suffix: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.textHint,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: 18),
            AuthErrorBanner(message: _error),
            if (_ok != null) JellyfinOkBanner(message: _ok!),
            AppPrimaryButton(
              label: 'jellyfin.sign_in'.tr(),
              icon: Icons.login_rounded,
              loading: _signingIn,
              onPressed: _busy ? null : _signIn,
            ),
            const SizedBox(height: 10),
            AppSecondaryButton(
              label: _testing
                  ? 'jellyfin.testing'.tr()
                  : 'jellyfin.test_connection'.tr(),
              icon: Icons.network_check_rounded,
              onPressed: _busy ? null : _test,
            ),
            SettingsFootnote('jellyfin.connect_footnote'.tr()),
          ],
        ),
      ),
    );
  }

  Widget _libraryStep(JellyfinServer server) {
    return Column(
      key: const ValueKey('libraries'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        JellyfinOkBanner(
          message: 'jellyfin.signed_in_to'.tr(
            namedArgs: {'name': server.name, 'user': server.userName},
          ),
        ),
        SettingsLabel('jellyfin.libraries_label'.tr()),
        JellyfinLibraryToggles(
          libraries: _libraries,
          hidden: _hidden,
          onChanged: (id, visible) => setState(() {
            visible ? _hidden.remove(id) : _hidden.add(id);
          }),
        ),
        SettingsFootnote('jellyfin.libraries_intro'.tr()),
        const SizedBox(height: 22),
        AppPrimaryButton(
          label: 'general.save'.tr(),
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
