import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/discord/discord_brand.dart';
import 'package:soplay/core/discord/discord_presence_service.dart';
import 'package:soplay/features/profile/presentation/widgets/discord_preview_card.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Where somebody turns Discord Rich Presence on, and on a phone hands over
/// the credential it needs.
///
/// ## Why this is its own screen
///
/// Every other switch in the app changes what the viewer sees. This one
/// changes what OTHER PEOPLE see, and on mobile it asks for a credential with
/// full access to their Discord account. A row in a list with a one-line
/// subtitle is the wrong shape for that: there is no room to say what is
/// actually being asked for, and a switch somebody flicks without reading is
/// exactly the outcome to avoid here.
///
/// So the risk is on the screen, above the control, in plain words — not in a
/// help article and not in grey text under a toggle.
class DiscordSettingsPage extends StatefulWidget {
  const DiscordSettingsPage({super.key});

  @override
  State<DiscordSettingsPage> createState() => _DiscordSettingsPageState();
}

class _DiscordSettingsPageState extends State<DiscordSettingsPage> {
  final HiveService _hive = getIt<HiveService>();
  DiscordPresenceService get _discord => getIt<DiscordPresenceService>();

  late bool _enabled;
  final TextEditingController _token = TextEditingController();
  bool _hasToken = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _enabled = _hive.discordPresenceEnabled;
    _loadToken();
  }

  Future<void> _loadToken() async {
    final saved = await _discord.readToken();
    if (!mounted) return;
    // The token itself is never shown back, not even masked. There is nothing
    // a viewer can do with seeing it that they cannot do by replacing it, and
    // a credential on screen is a credential in a screenshot.
    setState(() => _hasToken = saved != null && saved.isNotEmpty);
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _setEnabled(bool value) async {
    setState(() {
      _enabled = value;
      _busy = true;
    });
    await _hive.setDiscordPresenceEnabled(value);
    if (value) {
      await _discord.start();
    } else {
      await _discord.stop();
    }
    if (mounted) setState(() => _busy = false);
  }

  /// One path for a token however it arrived — signed in for, or pasted.
  Future<void> _applyToken(String value) async {
    if (value.isEmpty) return;
    setState(() => _busy = true);
    await _discord.saveToken(value);
    _token.clear();
    if (_enabled) {
      await _discord.stop();
      await _discord.start();
    }
    await _loadToken();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveToken() => _applyToken(_token.text.trim());

  /// The route pops with the token once Discord's own page has signed in, or
  /// with nothing if the viewer backed out — in which case nothing changes.
  Future<void> _signIn() async {
    final token = await context.push<String>('/discord/login');
    if (token == null || token.isEmpty || !mounted) return;
    await _applyToken(token);
  }

  Future<void> _forget() async {
    setState(() => _busy = true);
    await _discord.forget();
    await _loadToken();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = DiscordPresenceService.isDesktop;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('discord.title'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _BrandHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              'discord.what_it_does'.tr(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),

          // The card their friends see, live. It answers "what exactly
          // appears" and "is it working" at once, and it is the connection
          // indicator — no separate claim has to be believed.
          DiscordPreviewCard(
            activity: _discord.currentActivity,
            connected: _discord.isConnected,
          ),
          const SizedBox(height: 18),
          const SettingsDivider(),
          SettingsSwitchTile(
            icon: Icons.record_voice_over_rounded,
            title: 'discord.enable'.tr(),
            subtitle: desktop
                ? 'discord.enable_desktop_desc'.tr()
                : 'discord.enable_mobile_desc'.tr(),
            value: _enabled,
            // The tile takes a plain callback, so the switch is held during
            // the connect rather than by disabling the tile — a switch that
            // stops responding reads as broken.
            onChanged: (value) {
              if (_busy) return;
              unawaited(_setEnabled(value));
            },
          ),

          // Desktop needs nothing else — the Discord client is already signed
          // in and does the talking.
          if (!desktop) ...[
            const SizedBox(height: 20),
            _RiskNotice(),
            // Signing in on Discord's page is the way in for everyone who is
            // not going to open devtools — which was the step the paste field
            // alone lost people at. It sits below the warning on purpose: the
            // risk is the same whichever way the token arrives.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: DiscordBrand.mark(size: 18),
                label: Text('discord.sign_in'.tr()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'discord.sign_in_desc'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Row(
                children: [
                  Expanded(child: Divider(color: AppColors.surfaceVariant)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'discord.or_paste'.tr(),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.surfaceVariant)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'discord.token_label'.tr(),
                  hintText: _hasToken
                      ? 'discord.token_saved'.tr()
                      : 'discord.token_hint'.tr(),
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _saveToken,
                      child: Text('discord.token_save'.tr()),
                    ),
                  ),
                  if (_hasToken) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _forget,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        child: Text('discord.token_forget'.tr()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The warning, stated once and stated plainly.
///
/// Not collapsible, not a link, not below the fold. Somebody about to paste an
/// account credential into a third-party app should have read this without
/// choosing to.
class _RiskNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppColors.error),
              const SizedBox(width: 8),
              Text(
                'discord.risk_title'.tr(),
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'discord.risk_body'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Discord mark on its own colour, at the top of the screen.
///
/// A brand panel rather than a plain title because this screen is asking for
/// trust — on mobile, for an account credential. A page that looks like the
/// service it is talking to is a page somebody can place; an unstyled form
/// asking for a Discord token is exactly what a phishing screen looks like.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DiscordBrand.blurple,
            Color.lerp(DiscordBrand.blurple, Colors.black, 0.35)!,
          ],
        ),
      ),
      child: Row(
        children: [
          DiscordBrand.mark(size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'discord.brand_title'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'discord.brand_subtitle'.tr(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
