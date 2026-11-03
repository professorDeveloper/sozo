import Flutter
import UIKit

/// The phone's own glass, handed to Flutter as a hosted view
/// (lib/core/glass/native_glass.dart).
///
/// Everything else in the app approximates Liquid Glass in a shader
/// (lib/core/glass/glass_surface.dart): it bends the page it reads under a
/// frost and lights a rim by hand, because that is the only way a Flutter
/// layer can be glass. From iOS 26 the system draws the material itself —
/// `UIGlassEffect` — and what it draws is the reference the shader is
/// measured against: the real specular rim, the real dynamic tint over
/// whatever moves beneath, the real behaviour under Reduce Transparency and
/// Increase Contrast, all of it maintained by the platform rather than by
/// us. So where a surface can afford to be a hosted view, it should be the
/// system's material and not our imitation of it.
///
/// Two things are registered here:
///
/// * the view factory `soplay/native_glass`, which Flutter mounts through
///   `UiKitView`; and
/// * `glassCapability` on the existing `soplay/glass` channel
///   (GlassSense.swift calls into `capability()`), so Dart learns what this
///   particular phone will actually give instead of inferring it from a
///   version string. The app's floor is iOS 15 and the SDK is iOS 27, so
///   the answer is genuinely different on the phones we ship to and a
///   wrong guess here is a blank rectangle on somebody's screen.
///
/// The degradation is by what the running OS has, not by what we were built
/// against: `UIGlassEffect` where it exists, a system blur material where
/// it does not, and in both cases a `UIVisualEffectView` — never a nil
/// effect, which renders as an invisible view and reads as a bug rather
/// than as a fallback.
enum NativeGlass {
  /// The view type Flutter mounts. Named like the channel so a `grep` for
  /// `soplay/` finds every bridge the app has.
  static let viewType = "soplay/native_glass"

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(NativeGlassFactory(), withId: viewType)
  }

  /// What this phone can give, read at runtime and answered as a plain map
  /// so Dart can branch on capabilities rather than on `systemVersion`.
  ///
  /// `materials` is reported as the names Dart passes back in, not as the
  /// `UIBlurEffect.Style` raw values: the raw values are an ABI detail that
  /// has been renumbered before, and a number that shifts under us would
  /// silently pick a different material.
  static func capability() -> [String: Any] {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    var styles: [String] = []
    if #available(iOS 26.0, *) {
      // Both styles ship together; there is no partial adoption to probe
      // for, so the availability check *is* the probe.
      styles = ["regular", "clear"]
    }
    return [
      "systemVersion": UIDevice.current.systemVersion,
      "majorVersion": os.majorVersion,
      "minorVersion": os.minorVersion,
      // Whether `UIGlassEffect` exists on the phone running this, which is
      // the one fact Dart cannot work out for itself.
      "systemGlass": !styles.isEmpty,
      "glassStyles": styles,
      // The blur materials the fallback may ask for. All of these are
      // iOS 13+, so on anything that can run this app the list is the same
      // — it is sent anyway so that a phone which ever stops offering one
      // can say so without a new app build.
      "materials": Array(NativeGlassFactory.materials.keys).sorted(),
      // Repeated from `reduceTransparency` so a caller that only wants to
      // know "may I host glass at all" needs one round trip, not two.
      "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
    ]
  }
}

/// Makes a [NativeGlassView] for each `UiKitView` Flutter mounts.
final class NativeGlassFactory: NSObject, FlutterPlatformViewFactory {
  /// The blur materials the fallback can name, keyed by what Dart sends.
  /// Dark variants only: the app's glass is dark everywhere (GlassRecipe in
  /// lib/core/glass/app_glass.dart), and the automatic `.systemMaterial`
  /// would follow the phone's appearance and turn white on a light phone
  /// over our dark page.
  static let materials: [String: UIBlurEffect.Style] = [
    "ultraThin": .systemUltraThinMaterialDark,
    "thin": .systemThinMaterialDark,
    "regular": .systemMaterialDark,
    "thick": .systemThickMaterialDark,
    "chrome": .systemChromeMaterialDark,
  ]

  /// Creation parameters arrive as a Dart `Map`, so the standard codec
  /// rather than the default (which carries nothing).
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeGlassView(frame: frame, args: args as? [String: Any] ?? [:])
  }
}

/// One hosted glass surface.
///
/// The view is a `UIVisualEffectView` and nothing else: no subviews, no
/// content. What stands on the glass — a glyph, a label — stays in Flutter
/// and is drawn over this view, the same division the shader path keeps
/// (`GlassGroup` draws only the glass).
final class NativeGlassView: NSObject, FlutterPlatformView {
  /// How many of these UIKit has actually built since launch.
  ///
  /// Dart cannot otherwise tell a hosted view that was made from one that
  /// was not: when the factory is missing or the effect cannot be built,
  /// Flutter still keeps the `UiKitView` element in the tree and the
  /// failure is logged rather than thrown, so counting the Dart widgets
  /// proves only that Dart asked. This counter is what
  /// integration_test/native_glass_test.dart asserts on, and it is the
  /// reason that test can fail when the bridge is not registered.
  private(set) static var built = 0

  private let effectView: UIVisualEffectView

  init(frame: CGRect, args: [String: Any]) {
    let requestedStyle = args["style"] as? String ?? "regular"
    let requestedMaterial = args["material"] as? String ?? "regular"
    let radius = (args["cornerRadius"] as? NSNumber)?.doubleValue ?? 0
    let interactive = (args["interactive"] as? NSNumber)?.boolValue ?? false
    let tint = (args["tint"] as? NSNumber)?.uint32Value

    var effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      // `UIGlassEffect` is declared main-actor-bound, and Flutter calls the
      // view factory on the platform thread without saying so in the type
      // system, so the isolation is asserted rather than hopped to: a hop
      // would make this initialiser async, which the factory cannot await.
      effect = MainActor.assumeIsolated { () -> UIVisualEffect in
        let glass = UIGlassEffect(style: requestedStyle == "clear" ? .clear : .regular)
        // The system's own interactive glass reacts to touches landing on
        // the view. A hosted view that Flutter is gesturing over never
        // receives those touches (see `view()` below), so this is off
        // unless the caller has said the surface really is the touch
        // target.
        glass.isInteractive = interactive
        if let tint = tint {
          glass.tintColor = UIColor(argb: tint)
        }
        return glass
      }
    } else {
      let style = NativeGlassFactory.materials[requestedMaterial]
        ?? .systemThinMaterialDark
      effect = UIBlurEffect(style: style)
    }
    effectView = UIVisualEffectView(effect: effect)
    effectView.frame = frame
    // Flutter sizes the hosted view by changing its frame rather than by
    // laying it out, so the effect view has to follow its own bounds.
    effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    if radius > 0 {
      effectView.layer.cornerRadius = CGFloat(radius)
      // `.continuous` is the squircle UIKit uses for its own bars and
      // buttons; `.circular` next to a Flutter `BorderRadius` on the same
      // screen is visibly a different corner.
      effectView.layer.cornerCurve = .continuous
      effectView.clipsToBounds = true
    }

    // A tint on the pre-26 material is laid on by hand: `UIBlurEffect` has
    // no tint of its own, and without it the fallback is a plain blur where
    // the glass path has a grey over it.
    if #unavailable(iOS 26.0) {
      if let tint = tint {
        let wash = UIView(frame: effectView.bounds)
        wash.backgroundColor = UIColor(argb: tint)
        wash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wash.isUserInteractionEnabled = false
        effectView.contentView.addSubview(wash)
      }
    }

    super.init()
    NativeGlassView.built += 1
  }

  func view() -> UIView {
    // Flutter wraps a hosted view in a touch-intercepting view and asks the
    // native view whether it wants each touch. Glass is a surface, not a
    // control: letting it claim touches would take them away from the
    // Flutter button drawn on top of it, which is where every tap on glass
    // in this app actually belongs. So it claims none.
    effectView.isUserInteractionEnabled = false
    return effectView
  }
}

private extension UIColor {
  /// Dart hands colours over the channel as a packed ARGB int, which is how
  /// `Color.value` is laid out, so it is unpacked the same way here.
  convenience init(argb: UInt32) {
    self.init(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
