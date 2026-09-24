import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';

/// Shows the profile picker when it is due but nobody navigated to it: after
/// a sign-in to an account with several profiles, or when the active profile
/// was deleted on another device.
///
/// It waits for Home: sign-in pages route to `/main` themselves, and the
/// picker must land on top of that rather than be replaced by it.
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.child});

  final Widget child;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  final ProfileSession _session = getIt<ProfileSession>();
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _session.pickRequests.addListener(_request);
    AppRouter.router.routerDelegate.addListener(_tryShow);
  }

  @override
  void dispose() {
    _session.pickRequests.removeListener(_request);
    AppRouter.router.routerDelegate.removeListener(_tryShow);
    super.dispose();
  }

  void _request() {
    _pending = true;
    _tryShow();
  }

  void _tryShow() {
    if (!_pending) return;
    if (!_session.shouldPick) {
      _pending = false;
      return;
    }
    final path = AppRouter.router.routerDelegate.currentConfiguration.uri.path;
    if (path == '/profiles') {
      _pending = false;
    } else if (path == '/main') {
      _pending = false;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => AppRouter.router.go('/profiles'),
      );
    }
  }

  Future<void> _onSignedIn() async {
    await _session.refresh();
    if (mounted && _session.shouldPick) _request();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, next) => prev is! AuthLoaded && next is AuthLoaded,
      listener: (_, _) => _onSignedIn(),
      child: widget.child,
    );
  }
}
