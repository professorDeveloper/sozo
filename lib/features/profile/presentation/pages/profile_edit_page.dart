import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import 'package:soplay/features/auth/domain/repositories/auth_repository.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/widgets/auth_widgets.dart';

/// Name, username and picture.
///
/// The picture is uploaded on its own, before Save: it travels straight to R2
/// on a presigned url, and holding the bytes until Save would mean one button
/// doing a large upload and a small write with no way to report which failed.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.user});

  final UserEntity user;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final _displayName = TextEditingController(
    text: widget.user.displayName ?? '',
  );
  late final _username = TextEditingController(text: widget.user.username);

  late String? _photoUrl = widget.user.photoURL;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.textSecondary,
              ),
              title: Text('profile.pick_from_gallery'.tr()),
              onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: AppColors.textSecondary,
              ),
              title: Text('profile.take_photo'.tr()),
              onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
            ),
            if (_photoUrl != null && _photoUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
                title: Text(
                  'profile.remove_photo'.tr(),
                  style: const TextStyle(color: AppColors.error),
                ),
                onTap: () => Navigator.of(sheet).pop(null),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (source == null) {
      // Either the sheet was dismissed or "remove" was chosen; only the second
      // should clear the picture, and a dismiss returns before this runs.
      return;
    }

    // Bounded on the way in: a 12MP camera file is thirty times larger than
    // anything a 66px avatar can show, and the phone pays for every byte.
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
    } on PlatformException catch (e) {
      // A denied permission and a missing plugin channel both surface here.
      // Unhandled, they leave the sheet closed with nothing said and the
      // failure only visible in Crashlytics.
      if (!mounted) return;
      setState(() => _error = e.message ?? 'profile.photo_pick_failed'.tr());
      return;
    }
    if (picked == null || !mounted) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    final result = await getIt<AuthRepository>().uploadAvatar(
      File(picked.path),
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() {
          _photoUrl = value;
          _uploading = false;
        });
      case Failure(:final error):
        setState(() {
          _uploading = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final username = _username.text.trim();
    final displayName = _displayName.text.trim();
    final result = await getIt<AuthRepository>().updateProfile(
      username: username == widget.user.username ? null : username,
      displayName: displayName,
      photoUrl: _photoUrl ?? '',
    );
    if (!mounted) return;

    switch (result) {
      case Success():
        // The bloc holds the copy every other screen reads, so it has to be
        // told rather than left to notice on the next launch.
        context.read<AuthBloc>().add(const AuthProfileRefreshRequested());
        context.pop();
      case Failure(:final error):
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _uploading;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('profile.edit_profile'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _AvatarPicker(
                    photoUrl: _photoUrl,
                    fallback: widget.user.displayIdentifier,
                    uploading: _uploading,
                    onTap: busy ? null : _pickPhoto,
                  ),
                ),
                const SizedBox(height: 28),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      AuthTextField(
                        controller: _displayName,
                        hint: 'profile.display_name_hint'.tr(),
                        icon: Icons.badge_outlined,
                        textInputAction: TextInputAction.next,
                        enabled: !busy,
                        validator: (value) {
                          if ((value ?? '').trim().length > 60) {
                            return 'profile.display_name_too_long'.tr();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: _username,
                        hint: 'auth.username_hint'.tr(),
                        icon: Icons.alternate_email_rounded,
                        textInputAction: TextInputAction.done,
                        enabled: !busy,
                        onFieldSubmitted: (_) => _save(),
                        validator: (value) {
                          final name = (value ?? '').trim();
                          if (name.isEmpty) return 'auth.username'.tr();
                          if (name.length < 3) {
                            return 'auth.invalid_username'.tr();
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.user.email,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 24),
                AuthErrorBanner(message: _error),
                AuthPrimaryButton(
                  label: 'general.save'.tr(),
                  loading: _saving,
                  onPressed: busy ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.photoUrl,
    required this.fallback,
    required this.uploading,
    required this.onTap,
  });

  final String? photoUrl;
  final String fallback;
  final bool uploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final initial = fallback.isEmpty ? 'S' : fallback[0].toUpperCase();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            clipBehavior: Clip.antiAlias,
            child: uploading
                ? Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2.4,
                      ),
                    ),
                  )
                : hasPhoto
                ? Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _Initial(initial: initial),
                  )
                : _Initial(initial: initial),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.background, width: 2.5),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 40,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
