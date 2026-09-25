import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';
import 'package:soplay/features/profiles/presentation/profile_flows.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_pin_page.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';

/// Creates a profile when [profile] is null, edits it otherwise.
class HouseholdProfileEditPage extends StatefulWidget {
  const HouseholdProfileEditPage({super.key, this.profile, this.session});

  final HouseholdProfile? profile;
  final ProfileSession? session;

  @override
  State<HouseholdProfileEditPage> createState() =>
      _HouseholdProfileEditPageState();
}

enum _PinEdit { keep, set, remove }

class _HouseholdProfileEditPageState extends State<HouseholdProfileEditPage> {
  late final ProfileSession _session =
      widget.session ?? getIt<ProfileSession>();
  late final HouseholdProfile? _original = widget.profile;
  late final TextEditingController _name = TextEditingController(
    text: _original?.name ?? '',
  );
  late String? _avatar =
      _original?.avatar ?? (_original == null ? _nextAvatar() : null);
  late String? _color =
      _original?.color ??
      (_original == null
          ? ProfileAvatars.imageColors[_avatar] ?? _nextColor()
          : null);
  late bool _kids = _original?.isKids ?? false;
  _PinEdit _pinEdit = _PinEdit.keep;
  String? _newPin;
  bool _saving = false;
  bool _deleting = false;
  String? _nameError;

  bool get _creating => _original == null;
  bool get _hasPin => switch (_pinEdit) {
    _PinEdit.keep => _original?.hasPin ?? false,
    _PinEdit.set => true,
    _PinEdit.remove => false,
  };

  String _nextAvatar() {
    final used = {for (final p in _session.profiles) p.avatar};
    return ProfileAvatars.images.firstWhere(
      (id) => !used.contains(id),
      orElse: () => ProfileAvatars.images.first,
    );
  }

  String _nextColor() {
    final used = {for (final p in _session.profiles) p.color};
    return ProfileAvatars.colors.firstWhere(
      (c) => !used.contains(c),
      orElse: () => ProfileAvatars.colors.first,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _editPin() async {
    final choice = _hasPin
        ? await showModalBottomSheet<_PinEdit>(
            context: context,
            backgroundColor: AppColors.surface,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.pin_rounded),
                    title: Text('profiles.pin_change'.tr()),
                    onTap: () => Navigator.of(ctx).pop(_PinEdit.set),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.lock_open_rounded,
                      color: AppColors.error,
                    ),
                    title: Text(
                      'profiles.pin_remove'.tr(),
                      style: TextStyle(color: AppColors.error),
                    ),
                    onTap: () => Navigator.of(ctx).pop(_PinEdit.remove),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          )
        : _PinEdit.set;
    if (choice == null || !mounted) return;
    if (choice == _PinEdit.remove) {
      setState(() {
        _pinEdit = (_original?.hasPin ?? false)
            ? _PinEdit.remove
            : _PinEdit.keep;
        _newPin = null;
      });
      return;
    }
    final pin = await ProfilePinPage.create(context, header: _preview(72));
    if (pin == null || !mounted) return;
    setState(() {
      _pinEdit = _PinEdit.set;
      _newPin = pin;
    });
  }

  Future<String?> _askCurrentPin(HouseholdProfile original) => askProfilePin(
    context,
    _session,
    original,
    title: 'profiles.pin_current_title'.tr(),
    subtitle: 'profiles.pin_current_subtitle'.tr(),
  );

  Future<void> _save() async {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _nameError = 'profiles.name_required'.tr());
      return;
    }
    setState(() => _nameError = null);
    final original = _original;
    HouseholdProfile? created;
    try {
      if (original == null) {
        setState(() => _saving = true);
        created = await _session.create(
          name: name,
          avatar: _avatar,
          color: _color,
          isKids: _kids,
          pin: _pinEdit == _PinEdit.set ? _newPin : null,
        );
      } else {
        final changes = <String, dynamic>{
          if (name != original.name) 'name': name,
          if (_avatar != original.avatar) 'avatar': _avatar,
          if (_color != original.color) 'color': _color,
          if (_kids != original.isKids) 'isKids': _kids,
          if (_pinEdit == _PinEdit.set) 'pin': _newPin,
          if (_pinEdit == _PinEdit.remove) 'pin': null,
        };
        if (changes.isEmpty) {
          if (mounted) context.pop();
          return;
        }
        final sensitive =
            changes.containsKey('isKids') || changes.containsKey('pin');
        String? currentPin;
        if (sensitive && needsCurrentPin(_session, original)) {
          currentPin = await _askCurrentPin(original);
          if (currentPin == null || !mounted) return;
        }
        setState(() => _saving = true);
        final kidsChanged = changes.containsKey('isKids');
        await _session.update(original.id, changes, currentPin: currentPin);
        if (kidsChanged && original.id == _session.active?.id && mounted) {
          _reloadCatalogue();
        }
      }
      if (!mounted) return;
      showProfileSnack(context, 'profiles.saved'.tr());
      final router = GoRouter.of(context);
      final personalize =
          created != null && await offerProfilePersonalize(context, created);
      if (!mounted) return;
      context.pop();
      if (personalize) await startProfilePersonalize(router, created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final code = e is ProfileException ? e.code : null;
      if (code == 'PROFILE_NAME_TAKEN') {
        setState(() => _nameError = profileErrorText(e));
      } else {
        showProfileSnack(context, profileErrorText(e, max: _session.max));
      }
    }
  }

  void _reloadCatalogue() {
    try {
      context.read<HomeBloc>().add(HomeLoad(silent: true));
    } catch (_) {}
    try {
      context.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
  }

  Future<void> _delete() async {
    final original = _original;
    if (original == null || original.isDefault) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('profiles.delete_title'.tr(args: [original.name])),
        content: Text(
          'profiles.delete_body'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'profiles.delete'.tr(),
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    String? currentPin;
    if (needsCurrentPin(_session, original)) {
      currentPin = await _askCurrentPin(original);
      if (currentPin == null || !mounted) return;
    }
    setState(() => _deleting = true);
    final wasActive = original.id == _session.active?.id;
    try {
      await _session.delete(original.id, currentPin: currentPin);
      if (!mounted) return;
      if (wasActive) {
        _reloadCatalogue();
        context.go(_session.shouldPick ? '/profiles' : '/main');
      } else {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showProfileSnack(context, profileErrorText(e));
    }
  }

  Widget _preview(double size) => ProfileAvatar(
    name: _name.text.trim().isEmpty ? '?' : _name.text,
    avatar: _avatar,
    color: _color,
    isKids: _kids,
    size: size,
  );

  @override
  Widget build(BuildContext context) {
    final original = _original;
    final isDefault = original?.isDefault ?? false;
    final busy = _saving || _deleting;
    return SettingsPageScaffold(
      title: _creating ? 'profiles.new_title'.tr() : 'profiles.edit'.tr(),
      children: [
        const SizedBox(height: 8),
        Center(child: _preview(104)),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _nameError = null),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            labelText: 'profiles.name'.tr(),
            hintText: 'profiles.name_hint'.tr(),
            errorText: _nameError,
            filled: true,
            fillColor: AppColors.surface,
            counterStyle: const TextStyle(color: AppColors.textHint),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SettingsLabel('profiles.avatar'.tr()),
        _AvatarGrid(
          selected: _avatar,
          color: _color,
          name: _name.text,
          onSelected: (id) => setState(() {
            _avatar = id;
            _color = ProfileAvatars.imageColors[id] ?? _color;
          }),
        ),
        // An illustrated avatar brings its own colour.
        if (ProfileAvatars.imageFor(_avatar) == null) ...[
          const SizedBox(height: 20),
          SettingsLabel('profiles.color'.tr()),
          _ColorRow(
            selected: _color,
            onSelected: (c) => setState(() => _color = c),
          ),
        ],
        const SizedBox(height: 24),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.child_care_rounded,
              title: 'profiles.kids'.tr(),
              subtitle: isDefault
                  ? 'profiles.kids_default_blocked'.tr()
                  : 'profiles.kids_desc'.tr(),
              value: _kids,
              enabled: !isDefault && !busy,
              onChanged: (v) => setState(() => _kids = v),
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.pin_rounded,
              title: 'profiles.pin'.tr(),
              subtitle: 'profiles.pin_desc'.tr(),
              value: _hasPin ? 'profiles.pin_on'.tr() : 'profiles.pin_off'.tr(),
              valueColor: _hasPin ? AppColors.primary : null,
              enabled: !busy,
              onTap: busy ? null : _editPin,
            ),
          ],
        ),
        const SizedBox(height: 28),
        AppPrimaryButton(
          label: 'profiles.save'.tr(),
          loading: _saving,
          onPressed: busy ? null : _save,
        ),
        if (!_creating && !isDefault) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: TextButton.icon(
              onPressed: busy ? null : _delete,
              icon: _deleting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.error,
                      ),
                    )
                  : Icon(Icons.delete_outline_rounded, color: AppColors.error),
              label: Text(
                'profiles.delete'.tr(),
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AvatarGrid extends StatelessWidget {
  const _AvatarGrid({
    required this.selected,
    required this.color,
    required this.name,
    required this.onSelected,
  });

  final String? selected;
  final String? color;
  final String name;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    // A profile still on an old icon keeps it offered, so opening the page
    // does not silently change it.
    final ids = <String?>[
      if (selected != null && !ProfileAvatars.images.contains(selected))
        selected,
      ...ProfileAvatars.images,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 520 ? 6 : 4;
        final size = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final id in ids)
              Semantics(
                button: true,
                selected: id == selected,
                child: GestureDetector(
                  onTap: () => onSelected(id),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 140),
                    scale: id == selected ? 1 : 0.92,
                    child: ProfileAvatar(
                      name: name.trim().isEmpty ? '?' : name,
                      avatar: id,
                      color: color,
                      size: size,
                      selected: id == selected,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final hex in ProfileAvatars.colors)
          Semantics(
            button: true,
            selected: hex == selected,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelected(hex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ProfileAvatars.parse(hex, ''),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hex == selected ? Colors.white : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: hex == selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 20,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
