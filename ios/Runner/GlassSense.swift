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
