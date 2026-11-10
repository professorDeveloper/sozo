import Flutter
import UIKit

/// Whether the phone asks for glass that cannot be seen through — Reduce
/// Transparency (lib/core/glass/glass_sense.dart). Flutter carries Reduce
/// Motion and Increase Contrast to the app but not this, so the app asks.
///
/// - `reduceTransparency` → Bool, asked when the app starts and whenever it
///   comes back to the front.
/// - The switch thrown while the app is in front (the accessibility
///   shortcut) is said unasked, as a `reduceTransparency` call with the new
///   value, so the glass turns opaque on the same frame.
/// - `glassCapability` → a map of what the phone's own glass can give
///   (NativeGlass.swift). It lives on this channel rather than on one of
///   its own because it answers the same question from the same place —
///   what this particular iPhone will let the glass be — and a second
///   channel would be a second thing to keep registered.
/// - `glassViewsBuilt` → how many hosted glass views UIKit has really
///   built. Flutter keeps a `UiKitView` in the tree whether or not the
///   native half of it was ever made, so this is the only way a test on a
///   device can tell a registered factory from a missing one.
enum GlassSense {
  private static var channel: FlutterMethodChannel?

  /// The one observer of the switch: registered once however many engines
  /// register the bridge (each later one only takes over the channel), and
  /// kept so it is never added twice.
  private static var observer: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "soplay/glass",
      binaryMessenger: registrar.messenger()
    )
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "reduceTransparency":
        result(UIAccessibility.isReduceTransparencyEnabled)
      case "glassCapability":
        result(NativeGlass.capability())
      case "glassViewsBuilt":
        result(NativeGlassView.built)
      case "glassControlsBuilt":
        result(NativePlayerBar.built)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    guard observer == nil else { return }
    observer = NotificationCenter.default.addObserver(
      forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      GlassSense.channel?.invokeMethod(
        "reduceTransparency",
        arguments: UIAccessibility.isReduceTransparencyEnabled
      )
    }
  }
}
