// Home has to show the source that is actually selected.
//
// Two symptoms, one cause, and neither was reachable by the rules that were
// there:
//
//   * A cold start showed nothing. `HomePage.initState` fires a load the moment
//     the shell mounts — before ProviderBloc has resolved which source is
//     current — so the repository asked with no provider and got nothing. The
//     guard then saw a load in flight and declined to start another, so the
//     empty answer stood until somebody pulled to refresh.
//   * Coming back from Manga showed Watch's old rows. The rules compared the
//     incoming id against what they were last TOLD, not against what Home is
//     showing, so returning to a mode whose source had not changed in the
//     meantime was a no-op.
//
// The fix is to stop tracking either and compare against the one fact that
// cannot drift: `HomeLoaded.homeData.provider`, the source the rows on screen
// actually came from.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final shell = File(
    'lib/features/main/presentation/pages/main_page.dart',
  ).readAsStringSync();

  test('one rule, not one per route in', () {
    expect(shell, contains('void _reconcileHome(String providerId)'));
    // Both listeners go through it.
    expect(
      RegExp(r'_reconcileHome\(').allMatches(shell).length,
      greaterThanOrEqualTo(3),
      reason: 'the stored-provider and bloc listeners must both use it',
    );
  });

  test('it compares against what Home is SHOWING', () {
    expect(shell, contains('homeState.homeData.provider'));
    expect(shell, contains('if (showing == providerId) return;'));
  });

  test('and a load already running for the wrong source does not block it', () {
    // That guard is what made a cold start stick on empty. A stale load is the
    // reason to start the right one, not a reason to skip.
    expect(
      shell.contains('homeState is! HomeLoaded && homeState is! HomeLoading'),
      isFalse,
      reason: 'the in-flight guard is back',
    );
  });

  test('the first provider is no longer a special case', () {
    // It was the only branch that could decline to load at all.
    expect(
      shell.contains('the bloc\'s own listener owns that case'),
      isFalse,
    );
  });

  test('search reloads only when the source really moved', () {
    // Home reloading because it was stale must not throw away a query somebody
    // is in the middle of typing.
    expect(shell, contains('if (changed) context.read<SearchBloc>()'));
  });

  test('and the run token is what makes starting a second load safe', () {
    final bloc = File(
      'lib/features/home/presentation/bloc/home/home_bloc.dart',
    ).readAsStringSync();
    expect(bloc, contains('if (token != _runToken) return;'));
  });
}
