import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';

import '../../domain/entities/linked_device.dart';
import '../bloc/link_tv_bloc.dart';

/// "Link a TV": scan the QR shown on the television, or type the code under it.
///
/// The TV cannot finish signing in on its own — it polls until this page approves
/// its pairing — so this is the second half of the flow, not a convenience.
class LinkTvPage extends StatelessWidget {
  /// Pre-filled when the page is opened from the `/link/<CODE>` deep link.
  final String? initialCode;

  const LinkTvPage({super.key, this.initialCode});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = LinkTvBloc(repository: getIt())
          ..add(const LinkTvDevicesRequested());
        final code = initialCode;
        if (code != null && code.isNotEmpty) {
          bloc.add(LinkTvCodeChanged(code));
        }
        return bloc;
      },
      child: const _LinkTvView(),
    );
  }
}

class _LinkTvView extends StatefulWidget {
  const _LinkTvView();

  @override
  State<_LinkTvView> createState() => _LinkTvViewState();
}

class _LinkTvViewState extends State<_LinkTvView> {
  final _codeController = TextEditingController();
  MobileScannerController? _scanner;

  @override
  void dispose() {
    _codeController.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  void _startScanner() {
    setState(() {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
      );
    });
  }

  void _stopScanner() {
    final scanner = _scanner;
    if (scanner == null) return;
    setState(() => _scanner = null);
    // Disposed after the frame that removes the MobileScanner widget: tearing the
    // controller down while its widget is still mounted throws.
    WidgetsBinding.instance.addPostFrameCallback((_) => scanner.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LinkTvBloc, LinkTvState>(
      listenWhen: (prev, next) =>
          prev.approved != next.approved ||
          prev.errorKey != next.errorKey ||
          prev.errorMessage != next.errorMessage ||
          prev.code != next.code,
      listener: (context, state) {
        if (state.code != _codeController.text) {
          _codeController.value = TextEditingValue(
            text: state.code,
            selection: TextSelection.collapsed(offset: state.code.length),
          );
        }
        if (state.approved) {
          _stopScanner();
          HapticFeedback.mediumImpact();
        }
        if (state.hasError) {
          // Keep the camera up: the usual cause is a stale code, and the user's
          // next move is to press Refresh on the TV and scan the new one.
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(_errorText(state)),
                backgroundColor: AppColors.error,
              ),
            );
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            title: Text('link_tv.title'.tr(),
                style: const TextStyle(color: AppColors.textPrimary)),
            iconTheme: const IconThemeData(color: AppColors.textPrimary),
            actions: [
              // Reached from here because this is where the TVs are: pairing
              // one and then driving it are the same errand.
              IconButton(
                tooltip: 'remote.title'.tr(),
                onPressed: () => context.push('/tv-remote'),
                icon: const Icon(Icons.settings_remote_rounded),
              ),
            ],
          ),
          body: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async =>
                context.read<LinkTvBloc>().add(const LinkTvDevicesRequested()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (state.approved)
                  _ApprovedCard(deviceName: state.approvedDeviceName)
                else ...[
                  Text('link_tv.subtitle'.tr(),
                      style: const TextStyle(
                          color: AppColors.textSecondary, height: 1.4)),
                  const SizedBox(height: 20),
                  _ScannerCard(
                    controller: _scanner,
                    onStart: _startScanner,
                    onStop: _stopScanner,
                    onDetect: (raw) => context
                        .read<LinkTvBloc>()
                        .add(LinkTvApprove(code: raw)),
                  ),
                  const SizedBox(height: 24),
                  _ManualEntry(controller: _codeController, state: state),
                ],
                const SizedBox(height: 32),
                _LinkedDevices(state: state),
              ],
            ),
          ),
        );
      },
    );
  }

  String _errorText(LinkTvState state) {
    final key = state.errorKey;
    if (key != null) return key.tr();
    return state.errorMessage ?? 'link_tv.error_generic'.tr();
  }
}

class _ScannerCard extends StatelessWidget {
  final MobileScannerController? controller;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<String> onDetect;

  const _ScannerCard({
    required this.controller,
    required this.onStart,
    required this.onStop,
    required this.onDetect,
  });

  @override
  Widget build(BuildContext context) {
    final scanner = controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: scanner == null
            ? _ScannerPlaceholder(onStart: onStart)
            : Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: scanner,
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        final value = barcode.rawValue;
                        if (value != null && value.isNotEmpty) {
                          onDetect(value);
                          return;
                        }
                      }
                    },
                    errorBuilder: (context, error) => _ScannerError(
                      error: error,
                      onRetry: onStart,
                    ),
                  ),
                  const _ScannerReticle(),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: onStop,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ScannerPlaceholder extends StatelessWidget {
  final VoidCallback onStart;

  const _ScannerPlaceholder({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onStart,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner,
                size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            Text('link_tv.scan_button'.tr(),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text('link_tv.scan_hint'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textHint, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;

  const _ScannerError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    // A denied camera permission is the common case and is not recoverable by
    // retrying — say so, and leave the manual code entry below as the way through.
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography_outlined,
                  size: 48, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(
                denied
                    ? 'link_tv.camera_denied'.tr()
                    : 'link_tv.camera_error'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (!denied) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onRetry,
                  child: Text('general.retry'.tr()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerReticle extends StatelessWidget {
  const _ScannerReticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.7,
          heightFactor: 0.7,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManualEntry extends StatelessWidget {
  final TextEditingController controller;
  final LinkTvState state;

  const _ManualEntry({required this.controller, required this.state});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LinkTvBloc>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('link_tv.manual_title'.tr(),
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          enabled: !state.submitting,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          maxLength: LinkTvBloc.codeLength,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            letterSpacing: 8,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'ABCD2345',
            hintStyle: const TextStyle(color: AppColors.textHint, letterSpacing: 8),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
          ],
          onChanged: (value) => bloc.add(LinkTvCodeChanged(value)),
          onSubmitted: (_) => bloc.add(const LinkTvApprove()),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed:
                state.canSubmit ? () => bloc.add(const LinkTvApprove()) : null,
            child: state.submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text('link_tv.confirm'.tr()),
          ),
        ),
      ],
    );
  }
}

class _ApprovedCard extends StatelessWidget {
  final String? deviceName;

  const _ApprovedCard({this.deviceName});

  @override
  Widget build(BuildContext context) {
    final name = deviceName;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 56),
          const SizedBox(height: 12),
          Text(
            name == null || name.isEmpty
                ? 'link_tv.approved'.tr()
                : 'link_tv.approved_named'.tr(args: [name]),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('link_tv.approved_hint'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _LinkedDevices extends StatelessWidget {
  final LinkTvState state;

  const _LinkedDevices({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('link_tv.linked_devices'.tr(),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (state.loadingDevices)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textHint),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.devices.isEmpty && !state.loadingDevices)
          Text('link_tv.no_devices'.tr(),
              style: const TextStyle(color: AppColors.textHint))
        else
          ...state.devices.map(
            (device) => _DeviceRow(
              device: device,
              unlinking: state.unlinkingId == device.id,
            ),
          ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final LinkedDevice device;
  final bool unlinking;

  const _DeviceRow({required this.device, required this.unlinking});

  @override
  Widget build(BuildContext context) {
    final lastSeen = device.lastSeenAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(Icons.tv, color: AppColors.primary),
        title: Text(
          device.deviceName?.isNotEmpty == true
              ? device.deviceName!
              : 'link_tv.unnamed_device'.tr(),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        subtitle: lastSeen == null
            ? null
            : Text(
                'link_tv.last_seen'.tr(
                    args: [DateFormat.yMMMd().add_Hm().format(lastSeen)]),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
        trailing: unlinking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textHint),
              )
            : IconButton(
                icon: const Icon(Icons.link_off, color: AppColors.textSecondary),
                onPressed: () => _confirmUnlink(context),
              ),
      ),
    );
  }

  Future<void> _confirmUnlink(BuildContext context) async {
    final bloc = context.read<LinkTvBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('link_tv.unlink_title'.tr(),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text('link_tv.unlink_message'.tr(),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('link_tv.unlink_confirm'.tr(),
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) bloc.add(LinkTvUnlinkRequested(device.id));
  }
}
