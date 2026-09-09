import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/pages/profile_page.dart'
    show openProviderPicker;

/// Slim strip shown while the Sozo backend is unreachable.
///
/// The distinction it exists to make: our API being down takes out the *cloud*
/// providers only. CloudStream / Aniyomi / Manga extensions run entirely on the
/// device and keep working. Without this the app just looked broken — the
/// provider silently changed and half the catalogue vanished with no
/// explanation — so users assumed the whole app was down and closed it.
///
/// Hidden entirely when there is nothing to say (online), and when there are no
/// on-device sources to point at it degrades to a plain "we're offline" notice
/// rather than advertising a feature the user hasn't set up.
class BackendOutageBanner extends StatefulWidget {
  const BackendOutageBanner({super.key});

  @override
  State<BackendOutageBanner> createState() => _BackendOutageBannerState();
}

class _BackendOutageBannerState extends State<BackendOutageBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderBloc, ProviderState>(
      buildWhen: (a, b) =>
          a is! ProviderLoaded ||
          b is! ProviderLoaded ||
          a.offline != b.offline,
      builder: (context, state) {
        if (state is! ProviderLoaded || !state.offline || _dismissed) {
          return const SizedBox.shrink();
        }
        final localCount = state.usableProviders.length;
        return Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 6, 9),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.orange.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    localCount > 0
                        ? 'outage.body_with_local'.tr(args: ['$localCount'])
                        : 'outage.body_no_local'.tr(),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ),
                if (localCount > 0)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: Colors.orange,
                    ),
                    onPressed: () => openProviderPicker(
                      context,
                      context.read<ProviderBloc>(),
                    ),
                    child: Text(
                      'outage.pick_source'.tr(),
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: Colors.orange,
                    ),
                    onPressed: () =>
                        context.read<ProviderBloc>().add(const ProviderLoad()),
                    child: Text(
                      'general.retry'.tr(),
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  // Was an unconstrained 4dp pad around a 15dp icon: a ~23dp
                  // target for the only way to get rid of this banner. 48 and
                  // not 44 because compact density takes 4 back off.
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(Icons.close_rounded,
                      size: 15, color: Colors.orange),
                  onPressed: () => setState(() => _dismissed = true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
