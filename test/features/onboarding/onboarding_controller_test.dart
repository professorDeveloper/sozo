import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/onboarding/data/onboarding_store.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';

void main() {
  late MemoryOnboardingStore store;
  var signedIn = false;
  var supported = true;
  var granted = false;

  OnboardingController make() => OnboardingController(
    store: store,
    isSignedIn: () => signedIn,
    notificationsSupported: () => supported,
    notificationsGranted: () async => granted,
  );

  const action = TasteGenre(
    slug: 'action',
    label: 'Action',
    catalogues: {'anilist'},
  );
  const drama = TasteGenre(
    slug: 'drama',
    label: 'Drama',
    catalogues: {'anilist'},
  );
  const mecha = TasteGenre(
    slug: 'mecha',
    label: 'Mecha',
    catalogues: {'anilist'},
  );

  setUp(() {
    store = MemoryOnboardingStore();
    signedIn = false;
    supported = true;
    granted = false;
  });

  test('a fresh install has no setup running and starts at welcome', () {
    final c = make();
    expect(c.active, isFalse);
    expect(c.resumePath(), '/onboarding');
  });

  test('a guest walks every step, account included, import skipped', () async {
    final c = make();
    await c.begin(OnboardingFlow.firstRun);
    final seen = [c.step];
    for (var next = await c.advance(); next != null; next = await c.advance()) {
      if (next == OnboardingStep.kinds) await c.toggleKind(TasteKind.anime);
      seen.add(next);
    }
    expect(seen, [
      OnboardingStep.welcome,
      OnboardingStep.language,
      OnboardingStep.kinds,
      OnboardingStep.genres,
      OnboardingStep.account,
      OnboardingStep.notifications,
      OnboardingStep.done,
    ]);
  });

  test('signing in swaps the account step for import', () async {
    final c = make();
    await c.begin(OnboardingFlow.firstRun);
    await c.toggleKind(TasteKind.movies);
    while (c.step != OnboardingStep.genres) {
      await c.advance();
    }
    expect(await c.advance(), OnboardingStep.account);
    signedIn = true;
    expect(await c.advance(), OnboardingStep.import);
    // Going back no longer passes through the account step.
    expect(await c.retreat(), OnboardingStep.genres);
  });

  test('no kinds picked skips the genres step both ways', () async {
    final c = make();
    await c.begin(OnboardingFlow.firstRun);
    await c.advance();
    await c.advance();
    expect(c.step, OnboardingStep.kinds);
    expect(await c.advance(), OnboardingStep.account);
    expect(await c.retreat(), OnboardingStep.kinds);
  });

  test(
    'notifications are skipped where unsupported or already allowed',
    () async {
      supported = false;
      final c = make();
      await c.begin(OnboardingFlow.personalize);
      signedIn = true;
      await c.toggleKind(TasteKind.anime);
      expect(await c.advance(), OnboardingStep.genres);
      expect(await c.advance(), OnboardingStep.import);
      expect(await c.advance(), OnboardingStep.done);

      supported = true;
      granted = true;
      await c.begin(OnboardingFlow.personalize);
      await c.toggleKind(TasteKind.anime);
      await c.advance();
      await c.advance();
      expect(c.step, OnboardingStep.import);
      expect(await c.advance(), OnboardingStep.done);
    },
  );

  test('a killed app resumes on the same step with the same picks', () async {
    final c = make();
    await c.begin(OnboardingFlow.firstRun);
    await c.advance();
    await c.advance();
    await c.toggleKind(TasteKind.manga);
    await c.toggleKind(TasteKind.anime);
    await c.advance();
    await c.toggleGenre(action);
    await c.toggleGenre(drama);

    final again = make();
    expect(again.active, isTrue);
    expect(again.flow, OnboardingFlow.firstRun);
    expect(again.step, OnboardingStep.genres);
    expect(again.kinds, [TasteKind.manga, TasteKind.anime]);
    expect(again.genres.map((g) => g.slug), ['action', 'drama']);
    expect(again.resumePath(), '/onboarding/genres');
  });

  test('a resume on the account step after signing in moves past it', () async {
    final c = make();
    await c.begin(OnboardingFlow.firstRun);
    await c.arrive(OnboardingStep.account);
    signedIn = true;
    expect(make().resumePath(), '/onboarding/import');
  });

  test('only a first run is resumed at launch', () async {
    final c = make();
    await c.begin(OnboardingFlow.personalize);
    await c.advance();
    expect(make().resumePath(), '/onboarding');
  });

  test('genres need three, kinds need one', () async {
    final c = make();
    await c.begin(OnboardingFlow.firstRun);
    expect(c.canLeaveKinds, isFalse);
    await c.toggleKind(TasteKind.novels);
    expect(c.canLeaveKinds, isTrue);
    await c.toggleGenre(action);
    await c.toggleGenre(drama);
    expect(c.canLeaveGenres, isFalse);
    await c.toggleGenre(mecha);
    expect(c.canLeaveGenres, isTrue);
    await c.toggleGenre(drama);
    expect(c.canLeaveGenres, isFalse);
  });

  test('kinds keep the order they were picked in', () async {
    final c = make();
    await c.begin(OnboardingFlow.firstRun);
    await c.toggleKind(TasteKind.manga);
    await c.toggleKind(TasteKind.anime);
    await c.toggleKind(TasteKind.manga);
    await c.toggleKind(TasteKind.movies);
    expect(c.kinds, [TasteKind.anime, TasteKind.movies]);
    expect(c.taste.primary, TasteKind.anime);
  });

  test('ending forgets the run', () async {
    final c = make();
    await c.begin(OnboardingFlow.profile, namespace: 'kid1');
    expect(store.value, isNotNull);
    await c.end();
    expect(store.value, isNull);
    expect(make().active, isFalse);
  });

  test('a Settings run starts from what the profile already picked', () async {
    final c = make();
    await c.begin(
      OnboardingFlow.personalize,
      seed: const TasteProfile(kinds: [TasteKind.movies], genres: [action]),
    );
    expect(c.step, OnboardingStep.kinds);
    expect(c.kinds, [TasteKind.movies]);
    expect(c.genres, [action]);
    expect(c.isFirstStep, isTrue);
  });

  test('progress runs from 0 to 1 over the steps shown', () async {
    final c = make();
    await c.begin(OnboardingFlow.profile);
    expect(c.progress, 0);
    await c.toggleKind(TasteKind.anime);
    await c.advance();
    expect(c.progress, 0.5);
    await c.advance();
    expect(c.progress, 1);
  });
}
