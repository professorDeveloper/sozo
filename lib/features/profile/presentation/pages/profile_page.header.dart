part of 'profile_page.dart';

/// Who is signed in, and getting out.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final UserEntity? user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: user == null
            ? _GuestContent(onLogin: () => context.push('/login'))
            : _UserContent(user: user!),
      ),
    );
  }
}

class _GuestContent extends StatelessWidget {
  const _GuestContent({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.25),
                      AppColors.primaryDark.withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.primaryLight,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'profile.signin_account_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'profile.signin_account_subtitle'.tr(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Benefit(
            icon: Icons.sync_rounded,
            text: 'profile.guest_benefit_sync'.tr(),
          ),
          const SizedBox(height: 8),
          _Benefit(
            icon: Icons.local_fire_department_rounded,
            text: 'profile.guest_benefit_streak'.tr(),
          ),
          const SizedBox(height: 8),
          _Benefit(
            icon: Icons.link_rounded,
            text: 'profile.guest_benefit_trackers'.tr(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text('profile.sign_in'.tr()),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryLight),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserContent extends StatelessWidget {
  const _UserContent({required this.user});

  final UserEntity user;

  String _joined(BuildContext context, DateTime date) {
    String text;
    try {
      text = DateFormat.yMMM(context.locale.toString()).format(date);
    } catch (_) {
      text = DateFormat.yMMM('en').format(date);
    }
    return 'profile.joined_on'.tr(args: [text]);
  }

  @override
  Widget build(BuildContext context) {
    final display = user.displayName?.trim();
    final name = display != null && display.isNotEmpty
        ? display
        : user.displayIdentifier;
    final username = user.username?.trim();
    final handle = username != null && username.isNotEmpty
        ? '@$username'
        : user.email;
    final created = user.createdAt;
    final meta = <String>[
      if (created != null) _joined(context, created),
      if (user.authProvider != 'local') 'Google',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Avatar(user: user),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  handle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    meta,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _EditProfileButton(user: user),
        ],
      ),
    );
  }
}

/// Editing is what someone reaches for on their own profile; signing out is
/// something they do once. The header carries the first, the last section of
/// the page the second.
class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.user});

  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => context.push('/profile/edit', extra: user),
      icon: const Icon(Icons.edit_outlined, size: 19),
      color: AppColors.textPrimary,
      tooltip: 'profile.edit_profile'.tr(),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        fixedSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _SignOutSection extends StatelessWidget {
  const _SignOutSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SettingsCard(
        children: [
          SettingsNavTile(
            icon: Icons.logout_rounded,
            title: 'profile.sign_out'.tr(),
            destructive: true,
            trailing: const SizedBox.shrink(),
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'profile.sign_out'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'profile.sign_out_confirm'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AuthBloc>().add(const AuthLogoutRequested());
            },
            child: Text(
              'profile.sign_out'.tr(),
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoURL;
    final initials = _initials(user.displayIdentifier);

    // No coloured ring: a Google picture already arrives as a saturated tile,
    // and a red band around it read as an error state rather than a frame.
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(19),
        ),
        clipBehavior: Clip.antiAlias,
        child: photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => _Initials(initials: initials),
              )
            : _Initials(initials: initials),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isEmpty ? 'S' : name[0].toUpperCase();
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
