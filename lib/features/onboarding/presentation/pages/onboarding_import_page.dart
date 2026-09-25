import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';
import 'package:soplay/features/onboarding/data/library_import_service.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/import_showcase.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// Bring an AniList or MyAnimeList list across: what is being watched is
/// followed, what is planned goes to My List.
class OnboardingImportPage extends StatefulWidget {
  const OnboardingImportPage({super.key});

  @override
  State<OnboardingImportPage> createState() => _OnboardingImportPageState();
}

class _OnboardingImportPageState extends State<OnboardingImportPage> {
  final OnboardingController _c = getIt<OnboardingController>();
  final AnilistService _anilist = getIt<AnilistService>();
  final MalService _mal = getIt<MalService>();
  late final LibraryImportService _service = LibraryImportService.fromApp();
  ImportSource? _running;

  /// The running import failed: its screen offers a retry, and the step has
  /// to be leavable without one.
  bool _failed = false;
  final Map<ImportSource, ImportProgress> _results = {};

  @override
  void initState() {
    super.initState();
    _anilist.addListener(_changed);
    _mal.addListener(_changed);
  }

  @override
  void dispose() {
    _anilist.removeListener(_changed);
    _mal.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final error = _anilist.consumeError() ?? _mal.consumeError();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
    setState(() {});
  }

  Future<void> _connect(ImportSource source) async {
    final opened = source == ImportSource.anilist
        ? await _anilist.beginLink()
        : await _mal.beginLink();
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('anilist.browser_failed'.tr())));
    }
  }

  void _import(ImportSource source) => setState(() {
    _running = source;
    _failed = false;
  });

  Future<void> _finished(ImportSource source, ImportProgress p) async {
    _results[source] = p;
    await _c.recordImport(followed: p.followed, listed: p.listed);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _running = null);
  }

  @override
  Widget build(BuildContext context) {
    final running = _running;
    final busy = running != null && !_failed;
    final imported = _results.isNotEmpty;
    return OnboardingScaffold(
      step: OnboardingStep.import,
      glow: kAnilistBlue,
      maxBodyWidth: 560,
      onSkip: busy ? null : () => onboardingNext(context),
      skipLabel: 'onboarding.not_now'.tr(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingHeading(
              title: 'onboarding.import_title'.tr(),
              subtitle: 'onboarding.import_subtitle'.tr(),
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: running != null
                  ? ImportShowcase(
                      key: ValueKey(running),
                      source: running,
                      service: _service,
                      accent: running == ImportSource.anilist
                          ? kAnilistBlue
                          : kMalBlue,
                      onFinished: (p) => _finished(running, p),
                      onFailed: () => setState(() => _failed = true),
                    )
                  : Column(
                      key: const ValueKey('cards'),
                      children: [
                        _ServiceCard(
                          logo: const AnilistLogo(size: 44, radius: 12),
                          name: 'AniList',
                          accent: kAnilistBlue,
                          connectedAs: _anilist.isConnected
                              ? (_anilist.viewer?.name ?? '')
                              : null,
                          busy: _anilist.linking,
                          result: _results[ImportSource.anilist],
                          autofocus: isTvPlatform,
                          onConnect: () => _connect(ImportSource.anilist),
                          onImport: () => _import(ImportSource.anilist),
                        ),
                        const SizedBox(height: 12),
                        _ServiceCard(
                          logo: const MalLogo(size: 44, radius: 12),
                          name: 'MyAnimeList',
                          accent: kMalBlue,
                          connectedAs: _mal.isConnected
                              ? (_mal.viewer?.name ?? '')
                              : null,
                          busy: _mal.linking,
                          result: _results[ImportSource.mal],
                          onConnect: () => _connect(ImportSource.mal),
                          onImport: () => _import(ImportSource.mal),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      footer: busy
          ? null
          : OnboardingFocusButton(
              child: imported
                  ? AppPrimaryButton(
                      label: 'onboarding.continue'.tr(),
                      onPressed: () => onboardingNext(context),
                    )
                  : AppSecondaryButton(
                      label: 'onboarding.import_later'.tr(),
                      onPressed: () => onboardingNext(context),
                    ),
            ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.logo,
    required this.name,
    required this.accent,
    required this.connectedAs,
    required this.busy,
    required this.result,
    required this.onConnect,
    required this.onImport,
    this.autofocus = false,
  });

  final Widget logo;
  final String name;
  final Color accent;
  final String? connectedAs;
  final bool busy;
  final ImportProgress? result;
  final VoidCallback onConnect;
  final VoidCallback onImport;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final connected = connectedAs != null;
    final done = result;
    final String status;
    if (done != null) {
      status = 'onboarding.import_result'.tr(
        args: ['${done.followed}', '${done.listed}'],
      );
    } else if (connected) {
      status = connectedAs!.isEmpty
          ? 'onboarding.import_connected'.tr()
          : 'onboarding.import_connected_as'.tr(args: [connectedAs!]);
    } else {
      status = 'onboarding.import_not_connected'.tr();
    }
    final action = busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          )
        : OnboardingFocusButton(
            autofocus: autofocus,
            child: connected
                ? AppPrimaryButton(
                    label: done == null
                        ? 'onboarding.import_action'.tr()
                        : 'onboarding.import_again'.tr(),
                    expand: false,
                    onPressed: onImport,
                  )
                : AppSecondaryButton(
                    label: 'onboarding.import_connect'.tr(),
                    expand: false,
                    onPressed: onConnect,
                  ),
          );
    final stacked =
        MediaQuery.sizeOf(context).width < 400 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.25;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.surface,
        border: Border.all(
          color: connected
              ? accent.withValues(alpha: 0.6)
              : const Color(0x1AFFFFFF),
        ),
        gradient: connected
            ? LinearGradient(
                colors: [accent.withValues(alpha: 0.16), AppColors.surface],
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              logo,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: OnbType.label,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (done != null || connected) ...[
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: done != null ? AppColors.success : accent,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            status,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: OnbType.small - 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!stacked) ...[const SizedBox(width: 10), action],
            ],
          ),
          if (stacked) ...[
            const SizedBox(height: 12),
            Align(alignment: AlignmentDirectional.centerEnd, child: action),
          ],
        ],
      ),
    );
  }
}
