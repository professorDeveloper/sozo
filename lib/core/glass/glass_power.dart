import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'glass_step_down.dart';

export 'glass_step_down.dart';

/// What an Android phone can actually spend on the glass.
///
/// The refraction reads the screen under every glass on every frame and
/// bends it in a shader, so a phone that cannot keep up with it draws the
/// blur instead ([affordsRefraction] false): the recipe's frost under its
/// thicker tint, the same tint, rim and geometry — a plainer version of the
/// same glass, not a different one.
///
/// This used to be one field, `isLowRamDevice`. That is a flag the maker
/// sets to say the phone shipped as an Android Go phone; it is not a
/// measurement, and it answered the question wrong in both directions. A
/// 2019 mid-range phone with 6 GB and a GPU that cannot bend a bar sixty
/// times a second does not carry the flag and dropped frames; a current
/// 4 GB phone whose maker sets it loses the glass for nothing. So the phone
/// now sends what can be read off it
/// (android/app/src/main/kotlin/com/soplay/sozo/GlassPower.kt) and the
/// decision is made here, where it can be tested.
///
/// What is asked of each reading, and why it and not something else:
///
/// * **Vulkan 1.1 and API 29** — Impeller's Vulkan backend starts at API 29
///   and wants a Vulkan 1.1 driver. Below either, Impeller draws through
///   GL ES, where reading the screen back for a backdrop costs far more per
///   glass than it does through Vulkan. This is the signal that actually
///   tracks the cost of the refraction, which is why it comes first.
/// * **GL ES 3** — below it the shader cannot be compiled at all, whatever
///   the renderer says.
/// * **Memory, measured** — `totalMem`, the thing the Go flag stands in for.
///   Under [leastMemoryBytes] the phone is small by measurement rather than
///   by a maker's word.
/// * **The Go flag, kept** — a phone that shipped as a Go phone is running a
///   build tuned for a phone with nothing to spare, whatever it measures.
/// * **Battery Saver** — the user has asked this phone to spend less. The
///   most expensive thing on the screen is the first thing to give way, and
///   it comes back when they turn it off ([GlassPower] is told as it turns).
///
/// Two things are read and deliberately *not* gated on. The refresh rate is
/// not a pass or a fail — it is the frame budget, and it is handed to
/// [GlassStepDown] instead. The core count is carried for the same reason a
/// log line is: it says which phone a report came from, and nothing is
/// decided by it, because a core count has never predicted a GPU.
///
/// Anything the phone did not send is taken generously, so that a half
/// answer — an older build of the bridge, a maker's ROM with a service
/// missing — never takes the glass away.
@immutable
final class GlassPowerReading {
  const GlassPowerReading({
    this.lowRam = false,
    this.memoryBytes,
    this.sdk,
    this.vulkan11 = true,
    this.glEs,
    this.refreshHz,
    this.powerSave = false,
    this.cores,
  });

  /// What a phone that has not answered — an iPhone, a test, a build without
  /// the bridge — is taken to have: enough.
  static const GlassPowerReading ample = GlassPowerReading();

  /// Read off the channel's map; anything missing or of the wrong kind keeps
  /// its generous default, so a half answer never takes the glass away.
  factory GlassPowerReading.fromChannel(Object? answer) {
    if (answer is! Map) return ample;
    T? typed<T>(String key) {
      final value = answer[key];
      return value is T ? value : null;
    }

    return GlassPowerReading(
      lowRam: typed<bool>('lowRam') ?? false,
      memoryBytes: typed<int>('memoryBytes'),
      sdk: typed<int>('sdk'),
      vulkan11: typed<bool>('vulkan11') ?? true,
      glEs: typed<int>('glEs'),
      refreshHz: typed<num>('refreshHz')?.toDouble(),
      powerSave: typed<bool>('powerSave') ?? false,
      cores: typed<int>('cores'),
    );
  }

  /// `ActivityManager.isLowRamDevice`: the phone's maker says it is one of
  /// the phones Android Go is for.
  final bool lowRam;

  /// `MemoryInfo.totalMem`, in bytes: the phone's RAM as the phone measures
  /// it. Null where it could not be read.
  final int? memoryBytes;

  /// `Build.VERSION.SDK_INT`.
  final int? sdk;

  /// Whether the driver offers Vulkan 1.1 — the most the engine could have
  /// chosen to draw with.
  final bool vulkan11;

  /// The major OpenGL ES version the driver requires.
  final int? glEs;

  /// The default display's refresh rate, in hertz: the frame budget, not a
  /// gate ([budget]).
  final double? refreshHz;

  /// Battery Saver is on. The one reading that changes while the app runs.
  final bool powerSave;

  /// `Runtime.availableProcessors`: carried for a report, decided on by
  /// nothing.
  final int? cores;

  /// The least RAM, measured, a phone may have and still bend the screen:
  /// 3 GiB. A 4 GB phone — the floor of a current budget phone — passes, and
  /// the 2 GB phones that cannot keep a bar and a page and a decoder in
  /// memory at once do not. Not 4 GiB: a 4 GB phone measures a little under
  /// it once the kernel and the GPU have taken their share.
  static const int leastMemoryBytes = 3 * 1024 * 1024 * 1024;

  /// The API level Impeller's Vulkan backend starts at.
  static const int leastSdk = 29;

  /// Whether the phone may draw the refraction's shader at all.
  bool get affordsRefraction {
    if (lowRam) return false;
    if (powerSave) return false;
    if (sdk != null && sdk! < leastSdk) return false;
    if (!vulkan11) return false;
    if (glEs != null && glEs! < 3) return false;
    if (memoryBytes != null && memoryBytes! < leastMemoryBytes) return false;
    return true;
  }

  /// What one frame has on this phone's panel ([GlassStepDown]).
  /// Whether the always-on blurs (nav bars, scroll headers) should give way
  /// to a plain translucent fill. Narrower than [affordsRefraction]: a phone
  /// that only lacks Vulkan blurs fine, while a small, Go or GL ES 2 phone, or
  /// one in Battery Saver, pays for every blurred frame.
  bool get reducesEffects {
    if (lowRam) return true;
    if (powerSave) return true;
    if (glEs != null && glEs! < 3) return true;
    if (memoryBytes != null && memoryBytes! < leastMemoryBytes) return true;
    return false;
  }

  GlassFrameBudget get budget => refreshHz == null
      ? GlassFrameBudget.sixty
      : GlassFrameBudget.ofRefreshRate(refreshHz!);

  /// The same reading with Battery Saver turned as the phone has just said.
  GlassPowerReading withPowerSave(bool saving) => GlassPowerReading(
    lowRam: lowRam,
    memoryBytes: memoryBytes,
    sdk: sdk,
    vulkan11: vulkan11,
    glEs: glEs,
    refreshHz: refreshHz,
    powerSave: saving,
    cores: cores,
  );

  @override
  bool operator ==(Object other) =>
      other is GlassPowerReading &&
      other.lowRam == lowRam &&
      other.memoryBytes == memoryBytes &&
      other.sdk == sdk &&
      other.vulkan11 == vulkan11 &&
      other.glEs == glEs &&
      other.refreshHz == refreshHz &&
      other.powerSave == powerSave &&
      other.cores == cores;

  @override
  int get hashCode => Object.hash(
    lowRam,
    memoryBytes,
    sdk,
    vulkan11,
    glEs,
    refreshHz,
    powerSave,
    cores,
  );

  @override
  String toString() =>
      'GlassPowerReading(lowRam: $lowRam, memoryBytes: $memoryBytes, '
      'sdk: $sdk, vulkan11: $vulkan11, glEs: $glEs, refreshHz: $refreshHz, '
      'powerSave: $powerSave, cores: $cores)';
}

/// Asks an Android phone what it can spend on the glass
/// ([GlassPowerReading]), watches whether the phone it let through is in
/// fact keeping up ([GlassFrameWatch]), and hands the answer to every glass
/// under it, as [GlassSense] hands down the iPhone's Reduce Transparency.
///
/// Asked over `soplay/glass_power`
/// (android/app/src/main/kotlin/com/soplay/sozo/GlassPower.kt) when the app
/// starts, and again whenever it comes back to the front — most of what it
/// asks is the phone's make, which does not change while the app runs, but
/// Battery Saver does, and can be thrown with the app behind. The phone also
/// says that one unasked as it turns. An iPhone is not asked: Apple's own
/// glass is the design there, and the gate for it is Apple's.
///
/// Wrapped round the whole app once; a test puts one round what it pumps,
/// and speaks for the phone on [channel].
class GlassPower extends StatefulWidget {
  const GlassPower({super.key, required this.child});

  /// The channel the Android phone answers on.
  static const MethodChannel channel = MethodChannel('soplay/glass_power');

  final Widget child;

  /// What the phone over [context] said; [GlassPowerReading.ample] with no
  /// [GlassPower] above it, or before the phone has answered. [context]
  /// is told again only when [GlassPowerReading.affordsRefraction] turns.
  static GlassPowerReading readingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassPowerScope>()?.reading ??
      GlassPowerReading.ample;

  /// Whether glass at [context] may draw the refraction, as far as the
  /// phone's power goes (`GlassPickScope.liquidAt` asks the renderer).
  ///
  /// Both halves of the judgement are here: what the phone said before a
  /// frame was drawn, and what the frames it drew then showed
  /// ([GlassFrameWatch]). Both are read off the scope rather than one off a
  /// static, so that a glass depending on this is told when either turns.
  /// See [GlassPowerReading.reducesEffects].
  static bool reducesEffectsAt(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GlassPowerScope>()
          ?.reading
          .reducesEffects ??
      false;

  /// Puts [reading] in scope without asking the platform.
  @visibleForTesting
  static Widget withReading(GlassPowerReading reading, {required Widget child}) =>
      _GlassPowerScope(reading: reading, steppedDown: false, child: child);

  static bool affordsAt(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassPowerScope>()?.affords ??
      true;

  @override
  State<GlassPower> createState() => _GlassPowerState();
}

class _GlassPowerState extends State<GlassPower> with WidgetsBindingObserver {
  GlassPowerReading _reading = GlassPowerReading.ample;

  /// Only an Android phone has the bridge: asking anything else would be an
  /// error logged on every launch.
  bool get _asks => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (!_asks) return;
    WidgetsBinding.instance.addObserver(this);
    GlassPower.channel.setMethodCallHandler(_told);
    GlassFrameWatch.down.addListener(_onStepDown);
    unawaited(_ask());
  }

  @override
  void dispose() {
    if (_asks) {
      WidgetsBinding.instance.removeObserver(this);
      GlassPower.channel.setMethodCallHandler(null);
      GlassFrameWatch.down.removeListener(_onStepDown);
    }
    super.dispose();
  }

  /// Battery Saver can be thrown while the app is behind, and a build where
  /// the phone's own broadcast does not reach us is covered by asking again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_ask());
  }

  /// The phone saying, unasked, that Battery Saver has turned.
  Future<void> _told(MethodCall call) async {
    if (call.method == 'powerSave' && call.arguments is bool) {
      _set(_reading.withPowerSave(call.arguments as bool));
    }
  }

  Future<void> _ask() async {
    try {
      _set(
        GlassPowerReading.fromChannel(
          await GlassPower.channel.invokeMethod<Object?>('read'),
        ),
      );
    } on MissingPluginException {
      // A runner without the bridge: the glass as the renderer allows.
    } on PlatformException {
      // Nothing to read: as above.
    }
  }

  void _set(GlassPowerReading reading) {
    if (!mounted) return;
    // The step-down measures against this phone's panel, not against sixty —
    // set whether or not the rest of the reading has changed, since this is
    // the only place the panel's rate is ever learnt.
    GlassFrameWatch.budget = reading.budget;
    if (reading == _reading) return;
    setState(() => _reading = reading);
  }

  void _onStepDown() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => _GlassPowerScope(
    reading: _reading,
    steppedDown: GlassFrameWatch.down.value,
    child: widget.child,
  );
}

class _GlassPowerScope extends InheritedWidget {
  const _GlassPowerScope({
    required this.reading,
    required this.steppedDown,
    required super.child,
  });

  final GlassPowerReading reading;

  /// The frames this phone drew said no, whatever its make said
  /// ([GlassFrameWatch]).
  final bool steppedDown;

  /// The whole judgement, both halves: what the phone said it could do and
  /// what it then did.
  bool get affords => reading.affordsRefraction && !steppedDown;

  /// Only a change of the answer that matters wakes the glass. A reading
  /// that changed in some field the gate does not look at — a core count, a
  /// refresh rate — is no reason to build every glass on the screen again.
  @override
  bool updateShouldNotify(_GlassPowerScope old) =>
      old.affords != affords ||
      old.reading.reducesEffects != reading.reducesEffects;
}

/// The measured half of the gate: whether the phone the gate let through is
/// in fact drawing the refraction at the frame rate, and the decision to
/// stop if it is not.
///
/// The policy is [GlassStepDown]; this is only the wiring that feeds it.
/// `_GlassWatch` says when a refracting glass comes up on the screen and
/// when the last one goes ([refracting]), the engine says how long each
/// frame took, and when the policy has seen enough it turns [down], which
/// every glass reads through [GlassPower.affordsAt].
///
/// Armed on an Android phone only. On an iPhone the glass is the system's
/// own design drawn by the system's own gate, and a phone of Apple's that
/// misses frames is not a phone we take the design away from.
///
/// Armed in a release or profile build only, too. A debug build runs the app
/// from a JIT with every assertion on and misses frames on the fastest phone
/// made, for reasons that have nothing to do with the glass; a step-down
/// there would take the refraction off the developer's own desk and never
/// off a phone in anyone's hand. It is also why a frame cost measured in
/// debug says nothing: the cost of this glass has to be read in profile.
abstract final class GlassFrameWatch {
  static final ValueNotifier<bool> _down = ValueNotifier(false);

  /// Whether the glass has been stepped down to the blur for the rest of
  /// this run. Read by [GlassPower.affordsAt]; latches true.
  static ValueListenable<bool> get down => _down;

  static GlassStepDown? _policy;
  static bool _hooked = false;

  /// How many refracting glasses stand on the screen: the policy measures
  /// frames only while this is above zero.
  static int _up = 0;

  /// What one frame has on this phone's panel, as the phone said
  /// ([GlassPowerReading.budget]).
  ///
  /// It arrives late and has to reach a policy that already exists: the rate
  /// comes back over the channel, while the first refracting glass of the run
  /// is up and armed within the first frame, so by the time the phone has
  /// answered the policy has usually already been made with the assumed
  /// sixty hertz. Handing it on rather than only keeping it for the next
  /// policy is what makes the budget the panel's in a real run and not only
  /// in a test that sets it first.
  static GlassFrameBudget get budget => _budget;
  static set budget(GlassFrameBudget value) {
    _budget = value;
    _policy?.budget = value;
  }

  static GlassFrameBudget _budget = GlassFrameBudget.sixty;

  /// Whether this run watches frames at all.
  static bool get _watches =>
      !kIsWeb &&
      !kDebugMode &&
      defaultTargetPlatform == TargetPlatform.android;

  /// Said by `_GlassWatch` as a refracting glass comes up and goes.
  static void refracting(bool up) {
    if (!_watches) return;
    _up += up ? 1 : -1;
    assert(_up >= 0, 'A refracting glass went down twice over.');
    if (_up < 0) _up = 0;
    if (_down.value) return;
    // Only the first glass up and the last one down matter: the policy's
    // window is about the screen having a refraction on it at all, not about
    // how many pieces of it there are.
    if ((up && _up == 1) || (!up && _up == 0)) {
      _arm();
      _policy?.restart();
    }
  }

  static void _arm() {
    _policy ??= GlassStepDown(budget: budget);
    if (_hooked) return;
    _hooked = true;
    SchedulerBinding.instance.addTimingsCallback(_frames);
  }

  static void _frames(List<FrameTiming> timings) {
    final policy = _policy;
    if (policy == null || policy.down || _up == 0) return;
    for (final timing in timings) {
      // The whole span, build and raster together: the glass costs in both —
      // the layer walk in the build, the screen read in the raster — and
      // what the user sees is the sum.
      if (policy.frame(timing.totalSpan)) {
        _down.value = true;
        return;
      }
    }
  }

  /// Steps the glass down as if the frames had, and puts it back: the only
  /// way a test can reach a decision that is otherwise made by a real GPU
  /// over sixty real frames.
  @visibleForTesting
  static void debugStepDown({bool down = true}) {
    _down.value = down;
  }

  /// Everything this run has gathered, thrown away: a test that armed the
  /// watch leaves nothing behind for the next one.
  @visibleForTesting
  static void debugReset() {
    _down.value = false;
    _policy = null;
    _up = 0;
    budget = GlassFrameBudget.sixty;
  }
}
