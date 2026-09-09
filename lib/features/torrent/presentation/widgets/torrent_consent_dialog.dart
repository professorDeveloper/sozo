import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// The privacy warning shown before the first torrent of an install.
///
/// This is not boilerplate. Everything else the app streams is a normal HTTP
/// request to a server; a torrent is the one thing that makes the user's device
/// *upload* to strangers and exposes their IP to every peer in the swarm. That
/// is a materially different bargain and it deserves an explicit yes.
///
/// Two deliberate differences from how CloudStream does it:
///
///   * The answer is persisted, so declining is recoverable from Settings
///     rather than requiring an app restart.
///   * It is dismissible. A non-cancellable dialog to enforce a decision is a
///     dark pattern; backing out is simply a no.
abstract final class TorrentConsent {
  static Box get _box => Hive.box(AppConstants.settingsBox);

  static bool get granted =>
      _box.get(AppConstants.torrentConsentKey, defaultValue: false) as bool;

  static Future<void> revoke() =>
      _box.put(AppConstants.torrentConsentKey, false);

  /// Returns true when the user may proceed, asking only if they have not
  /// already agreed.
  static Future<bool> ensure(BuildContext context) async {
    if (granted) return true;
    if (!context.mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => const _TorrentConsentDialog(),
    );
    if (accepted != true) return false;

    await _box.put(AppConstants.torrentConsentKey, true);
    return true;
  }
}

class _TorrentConsentDialog extends StatelessWidget {
  const _TorrentConsentDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      icon: Icon(Icons.hub_outlined, color: AppColors.primary, size: 30),
      title: Text(
        'torrent.consent_title'.tr(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        'torrent.consent_body'.tr(),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'general.cancel'.tr(),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('torrent.consent_accept'.tr()),
        ),
      ],
    );
  }
}
