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

/// Asks for [profile]'s PIN and checks it with the server. Returns the PIN,
/// or null if the viewer gave up.
Future<String?> askProfilePin(
  BuildContext context,
  ProfileSession session,
  HouseholdProfile profile, {
  String? title,
  String? subtitle,
}) => ProfilePinPage.verify(
  context,
  title: title ?? 'profiles.pin_enter_title'.tr(),
  subtitle: subtitle ?? 'profiles.pin_enter_subtitle'.tr(args: [profile.name]),
  header: ProfileAvatar.of(profile, size: 84, showLock: false),
  onSubmit: (pin) async {
    try {
      await session.verifyPin(profile.id, pin);
      return null;
    } catch (e) {
      return profileErrorText(e);
    }
  },
);

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
