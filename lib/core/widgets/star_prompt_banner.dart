import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/player/player_dock.dart';
import 'package:soplay/core/system/star_prompt.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// The "star Sozo on GitHub" card. Nothing at all until [StarPrompt] says it
/// is due, and only on the route on top: the player is a route of its own, so
/// a banner on Home or Detail never appears over playback.
class StarPromptBanner extends StatefulWidget {
  const StarPromptBanner({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 0),
    this.safeBottom = false,
    this.tab,
  });

  final EdgeInsetsGeometry margin;
  final bool safeBottom;

  /// For a banner inside a main tab: tabs stay mounted behind the visible
  /// one, so the route alone does not say it can be seen.
  final TabId? tab;

  @override
  State<StarPromptBanner> createState() => _StarPromptBannerState();
}

class _StarPromptBannerState extends State<StarPromptBanner> {
  bool _visible = false;
  NavController? _nav;
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    StarPrompt.revision.addListener(_schedule);
    PlayerDock.instance.addListener(_schedule);
    if (widget.tab != null && getIt.isRegistered<NavController>()) {
      _nav = getIt<NavController>()..index.addListener(_schedule);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribes to isCurrent, so returning from the player re-checks.
    _route = ModalRoute.of(context);
    _schedule();
  }

  @override
  void dispose() {
    StarPrompt.revision.removeListener(_schedule);
    PlayerDock.instance.removeListener(_schedule);
    _nav?.index.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _check())
      ..ensureVisualUpdate();
  }

  void _check() {
    if (!mounted || _visible) return;
    final route = _route;
    if (route != null && !route.isCurrent) return;
    if (PlayerDock.instance.isDocked) return;
    final tab = widget.tab;
    if (tab != null && !(_nav?.isActive(tab) ?? false)) return;
    if (!StarPrompt.shouldShow) return;
    unawaited(StarPrompt.markShown());
    setState(() => _visible = true);
  }

  void _hide() {
    if (mounted) setState(() => _visible = false);
  }

  Future<void> _star() async {
    _hide();
    await StarPrompt.answered();
    try {
      await launchUrl(
        Uri.parse(AppConstants.sozoRepoUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _visible ? _card(context) : const SizedBox(width: double.infinity),
    );
  }

  Widget _card(BuildContext context) {
    final card = Padding(
      padding: widget.margin,
      child: Material(
        color: AppColors.surface,
        elevation: 6,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: AppColors.rating,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'star.title'.tr(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'star.body'.tr(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                children: [
                  TextButton(
                    onPressed: () {
                      _hide();
                      unawaited(StarPrompt.answered());
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textHint,
                    ),
                    child: Text('star.never'.tr()),
                  ),
                  TextButton(
                    onPressed: () {
                      _hide();
                      unawaited(StarPrompt.later());
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: Text('star.later'.tr()),
                  ),
                  TextButton.icon(
                    onPressed: _star,
                    icon: const Icon(Icons.star_rounded, size: 18),
                    label: Text('star.action'.tr()),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: widget.safeBottom ? SafeArea(top: false, child: card) : card,
    );
  }
}
