import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_pin_page.dart';

String profileErrorText(Object error, {int max = 5}) {
  if (error is ProfileException) {
    switch (error.code) {
      case 'PIN_INVALID':
        return 'profiles.pin_wrong'.tr();
      case 'PIN_LOCKED':
        return _lockedText(error.retryAt);
      case 'PIN_NOT_ON_DEVICE':
        return 'profiles.pin_not_on_device'.tr();
      case 'PROFILE_LIMIT':
        return 'profiles.limit'.tr(args: ['$max']);
      case 'PROFILE_NAME_TAKEN':
        return 'profiles.name_taken'.tr();
      case 'KIDS_PROFILE':
        return 'profiles.kids_locked_body'.tr();
      case 'DEFAULT_PROFILE':
        return 'profiles.kids_default_blocked'.tr();
    }
    if (error.status == 429) return 'profiles.pin_too_many'.tr();
    if (error.isOffline) return 'profiles.offline'.tr();
  }
  return 'profiles.error_generic'.tr();
}

String _lockedText(DateTime? at) {
  if (at == null) return 'profiles.pin_too_many'.tr();
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  return 'profiles.pin_locked_until'.tr(args: ['$hh:$mm']);
}

/// Asks for [profile]'s PIN and checks it (with the server, or on the device
/// when offline). Returns the PIN, an empty string when biometrics unlocked
/// it instead, or null if the viewer gave up.
///
/// [allowBiometric] is false where the PIN itself is needed afterwards.
Future<String?> askProfilePin(
  BuildContext context,
  ProfileSession session,
  HouseholdProfile profile, {
  String? title,
  String? subtitle,
  bool allowBiometric = true,
}) async {
  final biometric =
      allowBiometric && await session.canUnlockWithBiometric(profile.id);
  if (!context.mounted) return null;
  final pin = await ProfilePinPage.verify(
    context,
    title: title ?? 'profiles.pin_enter_title'.tr(),
    subtitle:
        subtitle ?? 'profiles.pin_enter_subtitle'.tr(args: [profile.name]),
    header: ProfileAvatar.of(profile, size: 84, showLock: false),
    onSubmit: (pin) async {
      try {
        await session.verifyPin(profile.id, pin);
        return null;
      } catch (e) {
        return profileErrorText(e);
      }
    },
    onBiometric: biometric
        ? () => session.unlockWithBiometric(
            profile.id,
            'profiles.biometric_reason'.tr(args: [profile.name]),
          )
        : null,
  );
  if (allowBiometric && pin != null && pin.isNotEmpty && context.mounted) {
    await offerProfileBiometric(context, session, profile);
  }
  return pin;
}

/// Once per profile and device, after its PIN was accepted: offer to open it
/// with a fingerprint or face from now on.
Future<void> offerProfileBiometric(
  BuildContext context,
  ProfileSession session,
  HouseholdProfile profile,
) async {
  if (!await session.shouldOfferBiometric(profile.id)) return;
  if (!context.mounted) return;
  await session.markBiometricOffered(profile.id);
  if (!context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('profiles.biometric_offer_title'.tr()),
      content: Text('profiles.biometric_offer_body'.tr(args: [profile.name])),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('profiles.biometric_offer_no'.tr()),
        ),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('profiles.biometric_offer_yes'.tr()),
        ),
      ],
    ),
  );
  if (yes != true) return;
  await session.setBiometric(
    profile.id,
    true,
    reason: 'app_lock.biometric_enable_reason'.tr(),
  );
}

/// Whether changing [target]'s PIN or kids flag, or deleting it, needs its
/// current PIN: the server waives it only for the main profile acting on
/// another one.
bool needsCurrentPin(ProfileSession session, HouseholdProfile target) {
  if (!target.hasPin) return false;
  final requester = session.active;
  final requesterIsMain = requester == null || requester.isDefault;
  return !(requesterIsMain && !target.isDefault);
}

void showProfileSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
