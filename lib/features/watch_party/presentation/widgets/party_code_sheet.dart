import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';

/// Builds the public invite link for a room code.
String partyInviteLink(String code) => 'https://sozo.azamov.me/party/$code';

/// Bottom-sheet content that creates a room, then shows the code with copy /
/// share affordances and a button to open the lobby.
class PartyCreateSheet extends StatefulWidget {
  const PartyCreateSheet({super.key, this.content});

  final PartyContent? content;

  @override
  State<PartyCreateSheet> createState() => _PartyCreateSheetState();
}

class _PartyCreateSheetState extends State<PartyCreateSheet> {
  final WatchPartyService _service = getIt<WatchPartyService>();

  bool _loading = true;
  String? _error;
  PartyRoom? _room;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = await _service.createParty(content: widget.content);
      if (!mounted) return;
      setState(() {
        _room = room;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'watch_party.error_generic'.tr();
        _loading = false;
      });
    }
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('watch_party.copied'.tr()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceVariant,
      ),
    );
  }

  void _share(String code) {
    Share.share(partyInviteLink(code));
  }

  void _openLobby(String code) {
    Navigator.of(context).pop();
    context.push('/watch-party', extra: WatchPartyArgs(code: code));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'watch_party.create'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          if (_loading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else if (_error != null)
            _ErrorRetry(message: _error!, onRetry: _create)
          else if (_room != null)
            _CodeReveal(
              code: _room!.code,
              onCopy: () => _copy(_room!.code),
              onShare: () => _share(_room!.code),
              onOpen: () => _openLobby(_room!.code),
            ),
        ],
      ),
    );
  }
}

class _CodeReveal extends StatelessWidget {
  const _CodeReveal({
    required this.code,
    required this.onCopy,
    required this.onShare,
    required this.onOpen,
  });

  final String code;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'watch_party.code_label'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Text(
            code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _GhostButton(
                icon: Icons.copy_rounded,
                label: 'watch_party.copy_code'.tr(),
                onTap: onCopy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GhostButton(
                icon: Icons.ios_share_rounded,
                label: 'watch_party.share_invite'.tr(),
                onTap: onShare,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: onOpen,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kButtonRadius),
              ),
            ),
            icon: const Icon(Icons.groups_rounded, size: 18),
            label: Text(
              'watch_party.title'.tr(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom-sheet content for joining a room via a typed code.
class PartyJoinSheet extends StatefulWidget {
  const PartyJoinSheet({super.key});

  @override
  State<PartyJoinSheet> createState() => _PartyJoinSheetState();
}

class _PartyJoinSheetState extends State<PartyJoinSheet> {
  static final RegExp _codeRe = RegExp(r'^[A-Z0-9]{4,12}$');

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim().toUpperCase();
    if (!_codeRe.hasMatch(code)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop();
    context.push('/watch-party', extra: WatchPartyArgs(code: code));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'watch_party.join'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'watch_party.join_hint'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            focusNode: _focus,
            autocorrect: false,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            maxLength: 12,
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
            onSubmitted: (_) => _submit(),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              _UpperCaseFormatter(),
            ],
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: AppColors.background,
              hintText: 'ABCD12',
              hintStyle: const TextStyle(
                color: AppColors.textHint,
                letterSpacing: 6,
                fontWeight: FontWeight.w700,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: _invalid ? AppColors.error : AppColors.border,
                  width: 0.8,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: _invalid ? AppColors.error : AppColors.primary,
                  width: 1.2,
                ),
              ),
            ),
          ),
          if (_invalid) ...[
            const SizedBox(height: 6),
            Text(
              'watch_party.invalid_code'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
              ),
              child: Text(
                'watch_party.join'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 34),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kButtonRadius),
              ),
            ),
            child: Text('general.try_again'.tr()),
          ),
        ),
      ],
    );
  }
}
