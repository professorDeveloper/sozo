import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/services/provider_probe.dart';

/// Testing sources, all the way to a link that answers.
///
/// The recurring complaint about this app is not that a source is missing, it
/// is that one looks fine and will not play — and a viewer meets every version
/// of that as the same blank error. This runs the real pipeline against each
/// source and shows where it stopped, so "search works, the CDN refuses us" is
/// distinguishable from "the site is gone" without reading a log.
///
/// It is a diagnostic, not a health dashboard. Results are of this device, on
/// this network, at this moment — which is the only kind of answer that means
/// anything for sources bound to the caller's IP.
class ProviderTestPage extends StatefulWidget {
  const ProviderTestPage({required this.providers, super.key});

  final List<ProviderEntity> providers;

  static void open(BuildContext context, List<ProviderEntity> providers) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProviderTestPage(providers: providers),
      ),
    );
  }

  @override
  State<ProviderTestPage> createState() => _ProviderTestPageState();
}

class _ProviderTestPageState extends State<ProviderTestPage> {
  /// Two at a time.
  ///
  /// Every leg is a real request to a real site, and several of these resolve
  /// on the device through a headless WebView. Running the whole list at once
  /// makes the phone the bottleneck and the timings meaningless — and timings
  /// are half of what is being reported.
  static const int _concurrency = 2;

  final Map<String, ProviderProbeResult> _results = {};
  final Set<String> _running = {};
  bool _sweeping = false;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  List<ProviderEntity> get _testable => widget.providers
      // A source the backend already flags as unplayable would fail at the last
      // stage every time, correctly and uselessly. It is not news.
      .where((p) => !p.browseOnly)
      .toList();

  Future<void> _test(ProviderEntity p) async {
    if (_running.contains(p.id)) return;
    setState(() => _running.add(p.id));
    try {
      final result = await getIt<ProviderProbe>().run(p);
      if (!mounted || _cancelled) return;
      setState(() => _results[p.id] = result);
    } finally {
      if (mounted) setState(() => _running.remove(p.id));
    }
  }

  Future<void> _testAll() async {
    if (_sweeping) {
      setState(() => _cancelled = true);
      return;
    }
    setState(() {
      _sweeping = true;
      _cancelled = false;
      _results.clear();
    });

    final queue = List<ProviderEntity>.of(_testable);
    var next = 0;

    Future<void> worker() async {
      while (!_cancelled) {
        if (next >= queue.length) return;
        final p = queue[next++];
        await _test(p);
      }
    }

    await Future.wait(
      List.generate(_concurrency, (_) => worker()),
    );
    if (mounted) setState(() => _sweeping = false);
  }

  @override
  Widget build(BuildContext context) {
    final providers = _testable;
    final done = _results.length;
    final playable = _results.values.where((r) => r.playable).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('provider_test.title'.tr()),
        actions: [
          TextButton(
            onPressed: _testAll,
            child: Text(
              _sweeping ? 'provider_test.stop'.tr() : 'provider_test.run_all'.tr(),
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    done == 0
                        ? 'provider_test.intro'.tr()
                        : 'provider_test.summary'.tr(
                            args: ['$playable', '$done'],
                          ),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              itemCount: providers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = providers[i];
                return _ProviderTestTile(
                  provider: p,
                  result: _results[p.id],
                  running: _running.contains(p.id),
                  onTest: () => _test(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderTestTile extends StatelessWidget {
  const _ProviderTestTile({
    required this.provider,
    required this.result,
    required this.running,
    required this.onTest,
  });

  final ProviderEntity provider;
  final ProviderProbeResult? result;
  final bool running;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r == null
                          ? provider.mode
                          : '${provider.mode} · ${r.millis}ms · "${r.query}"',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (running)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  onPressed: onTest,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  color: Colors.white70,
                  tooltip: 'provider_test.run_one'.tr(),
                ),
            ],
          ),
          if (r != null) ...[
            const SizedBox(height: 10),
            for (final step in r.steps) _StepRow(step: step),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final ProbeStep step;

  static const Map<ProbeStage, String> _labels = {
    ProbeStage.catalogue: 'provider_test.stage_catalogue',
    ProbeStage.detail: 'provider_test.stage_detail',
    ProbeStage.stream: 'provider_test.stage_stream',
    ProbeStage.playback: 'provider_test.stage_playback',
  };

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = switch (step.outcome) {
      ProbeOutcome.ok => (Icons.check_circle_rounded, const Color(0xFF4CAF50)),
      // Amber, not red. "Answered, had nothing" is a healthy source that does
      // not carry the probe title, and colouring it as a failure would teach
      // people to distrust a list that is telling the truth.
      ProbeOutcome.empty => (Icons.remove_circle_outline, const Color(0xFFFFB300)),
      ProbeOutcome.failed => (Icons.cancel_rounded, const Color(0xFFE53935)),
      ProbeOutcome.skipped => (Icons.remove_rounded, Colors.white24),
    };

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 4, end: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: colour),
          const SizedBox(width: 8),
          SizedBox(
            width: 86,
            child: Text(
              _labels[step.stage]!.tr(),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              step.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          if (step.millis > 0)
            Text(
              '${step.millis}ms',
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
