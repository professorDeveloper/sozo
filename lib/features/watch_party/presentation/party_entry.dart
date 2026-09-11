import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_code_sheet.dart';

/// Watch Party is auth-gated on the server (REST + socket). Returns true when a
/// user is signed in; otherwise routes to login and reports the result.
Future<bool> _ensurePartyLogin(BuildContext context) async {
  if (getIt<HiveService>().isLoggedIn) return true;
  await context.push('/login');
  return getIt<HiveService>().isLoggedIn;
}

/// Navigation payload for `/watch-party` (passed via `GoRouter` `state.extra`).
class WatchPartyArgs {
  const WatchPartyArgs({this.code, this.content});

  final String? code;
  final PartyContent? content;
}

/// Opens the "create a watch party" bottom sheet / dialog. The sheet creates the
/// room (REST + socket) and lets the host copy / share the invite before opening
/// the lobby.
Future<void> showCreatePartySheet(
  BuildContext context, {
  PartyContent? content,
}) async {
  if (!await _ensurePartyLogin(context) || !context.mounted) return;
  await showAdaptiveModal<void>(
    context: context,
    backgroundColor: KaizokuColors.cyberObsidian,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PartyCreateSheet(content: content),
  );
}

/// Opens the "join a watch party" bottom sheet / dialog (code entry).
Future<void> showJoinPartySheet(BuildContext context) async {
  if (!await _ensurePartyLogin(context) || !context.mounted) return;
  await showAdaptiveModal<void>(
    context: context,
    backgroundColor: KaizokuColors.cyberObsidian,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const PartyJoinSheet(),
  );
}

/// Opens the Watch Party entry chooser (Create / Join by code). Used where there
/// is no content context yet — e.g. the home top bar.
Future<void> showPartyEntrySheet(BuildContext context) async {
  if (!await _ensurePartyLogin(context) || !context.mounted) return;
  final choice = await showAdaptiveModal<String>(
    context: context,
    backgroundColor: KaizokuColors.cyberObsidian,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _PartyEntrySheet(),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'create') {
    await showCreatePartySheet(context);
  } else if (choice == 'join') {
    await showJoinPartySheet(context);
  }
}

class _PartyEntrySheet extends StatelessWidget {
  const _PartyEntrySheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    KaizokuColors.neonCrimson,
                    KaizokuColors.neonCrimson.withValues(alpha: 0.55),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: KaizokuColors.neonCrimson.withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(Icons.groups_rounded, color: Colors.white, size: 30),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'watch_party.title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'watch_party.entry_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KaizokuColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          _EntryCard(
            icon: Icons.add_rounded,
            title: 'watch_party.entry_create'.tr(),
            hint: 'watch_party.entry_create_hint'.tr(),
            primary: true,
            onTap: () => Navigator.of(context).pop('create'),
          ),
          const SizedBox(height: 12),
          _EntryCard(
            icon: Icons.login_rounded,
            title: 'watch_party.entry_join'.tr(),
            hint: 'watch_party.entry_join_hint'.tr(),
            primary: false,
            onTap: () => Navigator.of(context).pop('join'),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.hint,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary
          ? KaizokuColors.neonCrimson.withValues(alpha: 0.12)
          : KaizokuColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary
                  ? KaizokuColors.neonCrimson.withValues(alpha: 0.55)
                  : KaizokuColors.cardBorder,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary
                      ? KaizokuColors.neonCrimson
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: const TextStyle(
                        color: KaizokuColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: KaizokuColors.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
