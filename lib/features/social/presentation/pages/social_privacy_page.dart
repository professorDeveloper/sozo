import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/social/data/social_service.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/social/presentation/widgets/social_widgets.dart';

/// Who sees what. Sharing is off until the viewer turns it on here, knowing
/// what it covers.
class SocialPrivacyPage extends StatefulWidget {
  const SocialPrivacyPage({super.key});

  @override
  State<SocialPrivacyPage> createState() => _SocialPrivacyPageState();
}

class _SocialPrivacyPageState extends State<SocialPrivacyPage> {
  final SocialService _social = getIt<SocialService>();
  SocialSettings? _settings;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await _social.remote.settings();
      if (mounted) setState(() => _settings = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save({
    ProfileVisibility? visibility,
    bool? shareActivity,
    RequestPolicy? allowRequests,
  }) async {
    final before = _settings;
    if (before == null || _saving) return;
    setState(() {
      _saving = true;
      _settings = before.copyWith(
        visibility: visibility,
        shareActivity: shareActivity,
        allowRequests: allowRequests,
      );
    });
    try {
      final saved = await _social.remote.updateSettings(
        visibility: visibility,
        shareActivity: shareActivity,
        allowRequests: allowRequests,
      );
      if (mounted) setState(() => _settings = saved);
      _social.revision.value++;
    } catch (e) {
      if (!mounted) return;
      setState(() => _settings = before);
      showSocialSnack(context, socialErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setShare(bool on) async {
    final ok = await confirmSocial(
      context,
      title: on ? 'social.share_on_title'.tr() : 'social.share_off_title'.tr(),
      body: on ? 'social.share_on_body'.tr() : 'social.share_off_body'.tr(),
      confirm: on
          ? 'social.share_on_confirm'.tr()
          : 'social.share_off_confirm'.tr(),
      destructive: !on,
    );
    if (ok) await _save(shareActivity: on);
  }

  static String _visibilityLabel(ProfileVisibility v) => switch (v) {
    ProfileVisibility.public => 'social.visibility_public'.tr(),
    ProfileVisibility.friends => 'social.visibility_friends'.tr(),
    ProfileVisibility.private => 'social.visibility_private'.tr(),
  };

  static String _requestsLabel(RequestPolicy p) => switch (p) {
    RequestPolicy.everyone => 'social.requests_everyone'.tr(),
    RequestPolicy.nobody => 'social.requests_nobody'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (s == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'social.privacy_title'.tr(),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        body: _error == null
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SocialStateView.error(_error, _load),
      );
    }
    final username = _social.myUsername;
    final privateProfile = s.visibility == ProfileVisibility.private;
    return SettingsPageScaffold(
      title: 'social.privacy_title'.tr(),
      children: [
        SettingsLabel('social.section_activity'.tr()),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.podcasts_rounded,
              title: 'social.share_title'.tr(),
              subtitle: privateProfile
                  ? 'social.share_private_note'.tr()
                  : 'social.share_desc'.tr(),
              value: s.shareActivity,
              enabled: !_saving,
              onChanged: _setShare,
            ),
            if (username != null && username.isNotEmpty) ...[
              const SettingsDivider(),
              SettingsNavTile(
                icon: Icons.history_rounded,
                title: 'social.my_activity'.tr(),
                subtitle: 'social.my_activity_desc'.tr(),
                onTap: () =>
                    context.push('/u/${Uri.encodeComponent(username)}'),
              ),
            ],
          ],
        ),
        SettingsFootnote(
          ProfileScope.namespace == null
              ? 'social.share_footnote'.tr()
              : 'social.share_footnote_profile'.tr(),
        ),
        const SizedBox(height: 20),
        SettingsLabel('social.section_profile'.tr()),
        SettingsCard(
          children: [
            SettingsDropdownTile<ProfileVisibility>(
              icon: Icons.visibility_outlined,
              title: 'social.visibility_title'.tr(),
              value: s.visibility,
              options: ProfileVisibility.values,
              labelOf: _visibilityLabel,
              enabled: !_saving,
              onChanged: (v) {
                if (v != s.visibility) _save(visibility: v);
              },
            ),
            const SettingsDivider(),
            SettingsDropdownTile<RequestPolicy>(
              icon: Icons.person_add_alt_outlined,
              title: 'social.requests_title'.tr(),
              value: s.allowRequests,
              options: RequestPolicy.values,
              labelOf: _requestsLabel,
              enabled: !_saving,
              onChanged: (v) {
                if (v != s.allowRequests) _save(allowRequests: v);
              },
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.block_rounded,
              title: 'social.blocked_title'.tr(),
              onTap: () => context.push('/friends/blocked'),
            ),
          ],
        ),
        SettingsFootnote(switch (s.visibility) {
          ProfileVisibility.public => 'social.visibility_public_desc'.tr(),
          ProfileVisibility.friends => 'social.visibility_friends_desc'.tr(),
          ProfileVisibility.private => 'social.visibility_private_desc'.tr(),
        }),
      ],
    );
  }
}

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  final SocialService _social = getIt<SocialService>();
  List<FriendEntry>? _items;
  Object? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _social.remote.blocks();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _unblock(SocialUser user) async {
    setState(() => _busy.add(user.id));
    try {
      await _social.unblock(user.id);
      if (!mounted) return;
      setState(
        () => _items = _items?.where((e) => e.user.id != user.id).toList(),
      );
      showSocialSnack(context, 'social.unblocked_snack'.tr(args: [user.name]));
    } catch (e) {
      if (mounted) showSocialSnack(context, socialErrorText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    Widget body;
    if (items == null) {
      body = _error == null
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SocialStateView.error(_error, _load);
    } else if (items.isEmpty) {
      body = SocialStateView(
        icon: Icons.block_rounded,
        title: 'social.blocked_empty'.tr(),
        body: 'social.blocked_empty_body'.tr(),
      );
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final user = items[i].user;
          return SocialUserTile(
            key: ValueKey(user.id),
            user: user,
            trailing: SocialPillButton(
              label: 'social.action_unblock'.tr(),
              busy: _busy.contains(user.id),
              onPressed: () => _unblock(user),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'social.blocked_title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: body,
      ),
    );
  }
}
