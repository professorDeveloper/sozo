import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:soplay/features/onboarding/data/onboarding_store.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';

/// The setup's state: which flow, which step, and what has been picked.
///
/// Every change is written through to [OnboardingStore], so an app killed on
/// the genres screen reopens on the genres screen with the same chips lit.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required OnboardingStore store,
    required bool Function() isSignedIn,
    bool Function()? notificationsSupported,
    Future<bool> Function()? notificationsGranted,
  }) : _store = store,
       _isSignedIn = isSignedIn,
       _notificationsSupported = notificationsSupported ?? (() => false),
       _notificationsGranted = notificationsGranted {
    _restore();
  }

  static const int minGenres = 3;

  final OnboardingStore _store;
  final bool Function() _isSignedIn;
  final bool Function() _notificationsSupported;
  final Future<bool> Function()? _notificationsGranted;

  bool _active = false;
  OnboardingFlow _flow = OnboardingFlow.firstRun;
  OnboardingStep _step = OnboardingStep.welcome;
  List<TasteKind> _kinds = const [];
  List<TasteGenre> _genres = const [];
  String? _namespace;
  int _followed = 0;
  int _listed = 0;
  bool? _notificationsOn;
  bool _granted = false;

  bool get active => _active;
  OnboardingFlow get flow => _flow;
  OnboardingStep get step => _step;
  List<TasteKind> get kinds => _kinds;
  List<TasteGenre> get genres => _genres;

  /// The profile a [OnboardingFlow.profile] run is for.
  String? get namespace => _namespace;
  int get importedFollowed => _followed;
  int get importedListed => _listed;
  bool? get notificationsOn => _notificationsOn;

  bool get canLeaveKinds => _kinds.isNotEmpty;
  bool get canLeaveGenres => _genres.length >= minGenres;

  TasteProfile get taste => TasteProfile(
    kinds: _kinds,
    genres: _genres,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );

  OnboardingConditions get conditions => OnboardingConditions(
    signedIn: _isSignedIn(),
    hasKinds: _kinds.isNotEmpty,
    notificationsSupported: _notificationsSupported(),
    notificationsGranted: _granted,
  );

  double get progress => flowProgress(_flow, _step, conditions);

  bool get isFirstStep => stepBefore(_flow, _step, conditions) == null;

  void _restore() {
    final raw = _store.read();
    if (raw == null) return;
    try {
      _flow = OnboardingFlow.fromName(raw['flow'] as String?);
      // A Settings run is not resumed: after a relaunch the person is in the
      // app, and a stale run would only catch the next sign-in.
      if (_flow != OnboardingFlow.firstRun) {
        _flow = OnboardingFlow.firstRun;
        unawaited(_store.write(null));
        return;
      }
      _step =
          OnboardingStep.fromName(raw['step'] as String?) ?? _flow.steps.first;
      _kinds = [
        for (final id in (raw['kinds'] as List? ?? const []))
          ?TasteKind.fromId(id.toString()),
      ];
      _genres = [
        for (final g in (raw['genres'] as List? ?? const []))
          if (g is Map) TasteGenre.fromJson(g.cast<String, dynamic>()),
      ];
      _namespace = raw['namespace'] as String?;
      _followed = (raw['followed'] as num?)?.toInt() ?? 0;
      _listed = (raw['listed'] as num?)?.toInt() ?? 0;
      _notificationsOn = raw['notificationsOn'] as bool?;
      _active = true;
    } catch (_) {
      _active = false;
    }
  }

  Map<String, dynamic> _snapshot() => {
    'flow': _flow.name,
    'step': _step.name,
    'kinds': [for (final k in _kinds) k.id],
    'genres': [for (final g in _genres) g.toJson()],
    'namespace': ?_namespace,
    'followed': _followed,
    'listed': _listed,
    'notificationsOn': ?_notificationsOn,
  };

  Future<void> _changed() async {
    notifyListeners();
    await _store.write(_snapshot());
  }

  /// Starts [flow] from its first step, forgetting any earlier run.
  Future<void> begin(
    OnboardingFlow flow, {
    String? namespace,
    TasteProfile? seed,
  }) async {
    _active = true;
    _flow = flow;
    _step = flow.steps.first;
    _kinds = List.unmodifiable(seed?.kinds ?? const <TasteKind>[]);
    _genres = List.unmodifiable(seed?.genres ?? const <TasteGenre>[]);
    _namespace = namespace;
    _followed = 0;
    _listed = 0;
    _notificationsOn = null;
    await _changed();
  }

  /// A first run that is not under way yet is started; one that is, is kept.
  Future<void> ensureFirstRun() async {
    if (_active && _flow == OnboardingFlow.firstRun) return;
    await begin(OnboardingFlow.firstRun);
  }

  /// Where a relaunch should land.
  String resumePath() {
    if (!_active || _flow != OnboardingFlow.firstRun) {
      return OnboardingStep.welcome.path;
    }
    if (isStepAvailable(_step, conditions)) return _step.path;
    return (stepAfter(_flow, _step, conditions) ?? OnboardingStep.done).path;
  }

  Future<void> refreshNotificationState() async {
    final check = _notificationsGranted;
    if (check == null || !_notificationsSupported()) return;
    try {
      _granted = await check();
    } catch (_) {
      _granted = false;
    }
  }

  /// Moves on, and returns the step now current — null when the flow is over.
  Future<OnboardingStep?> advance() async {
    await refreshNotificationState();
    final next = stepAfter(_flow, _step, conditions);
    if (next == null) return null;
    _step = next;
    await _changed();
    return next;
  }

  /// Moves back, and returns the step now current — null at the start.
  Future<OnboardingStep?> retreat() async {
    final previous = stepBefore(_flow, _step, conditions);
    if (previous == null) return null;
    _step = previous;
    await _changed();
    return previous;
  }

  /// For a screen reached some other way than [advance] — a resume, or a
  /// route opened directly.
  Future<void> arrive(OnboardingStep step) async {
    if (!_active || _step == step || !_flow.steps.contains(step)) return;
    _step = step;
    await _changed();
  }

  Future<void> toggleKind(TasteKind kind) async {
    _kinds = List.unmodifiable(
      _kinds.contains(kind)
          ? [
              for (final k in _kinds)
                if (k != kind) k,
            ]
          : [..._kinds, kind],
    );
    // A genre only the dropped kind offered is no longer on screen to untick,
    // yet would still count towards the three.
    final offered = {for (final k in _kinds) k.catalogue.kind};
    _genres = List.unmodifiable([
      for (final g in _genres)
        if (g.catalogues.isEmpty || g.catalogues.any(offered.contains)) g,
    ]);
    await _changed();
  }

  Future<void> toggleGenre(TasteGenre genre) async {
    _genres = List.unmodifiable(
      _genres.contains(genre)
          ? [
              for (final g in _genres)
                if (g != genre) g,
            ]
          : [..._genres, genre],
    );
    await _changed();
  }

  /// Refreshes what the picked genres know — covers and catalogues — from a
  /// newer fetch, without changing which are picked.
  Future<void> refreshGenres(List<TasteGenre> fetched) async {
    if (_genres.isEmpty) return;
    final bySlug = {for (final g in fetched) g.slug: g};
    _genres = List.unmodifiable([
      for (final g in _genres) bySlug[g.slug]?.mergedWith(g) ?? g,
    ]);
    await _changed();
  }

  Future<void> recordImport({required int followed, required int listed}) {
    _followed += followed;
    _listed += listed;
    return _changed();
  }

  Future<void> recordNotifications(bool on) {
    _notificationsOn = on;
    return _changed();
  }

  /// Forgets the run. The caller saves what should outlive it first.
  Future<void> end() async {
    _active = false;
    _flow = OnboardingFlow.firstRun;
    _step = OnboardingStep.welcome;
    _kinds = const [];
    _genres = const [];
    _namespace = null;
    _followed = 0;
    _listed = 0;
    _notificationsOn = null;
    notifyListeners();
    await _store.write(null);
  }
}
