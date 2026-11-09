import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Screen brightness and system volume for the player's swipe gestures.
///
/// The channel existed on Android only, so on iOS every call threw
/// MissingPluginException straight into a `catch (_) {}` in Dart: the swipe
/// indicator moved and nothing else happened, silently, which is worse than a
/// gesture that visibly does nothing.
///
/// Brightness is a plain public API. Volume is not — iOS has no supported way
/// for an app to set the system volume, so this drives the slider inside a
/// hidden `MPVolumeView`, which is the long-standing workaround every video app
/// uses. If Apple ever closes it, `setVolume` degrades to reporting the current
/// value rather than failing, and only the gesture stops working.
enum SystemControls {
  private static let channelName = "soplay/system_controls"

  /// Kept alive for the process: the slider must be in a window to work, and
  /// rebuilding it per call loses the first change of every gesture.
  private static var volumeView: MPVolumeView?

  /// The system brightness before the player first changed it. iOS has no
  /// per-window override: the change is global and outlives the app unless
  /// it is put back.
  private static var savedBrightness: CGFloat?
  private static var resignObserver: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )

    if resignObserver == nil {
      resignObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.willResignActiveNotification,
        object: nil,
        queue: .main
      ) { _ in restoreBrightness() }
    }

    channel.setMethodCallHandler { call, result in
      // UIScreen and UIWindow are main-thread only, and Flutter does not
      // promise which thread a call arrives on.
      DispatchQueue.main.async {
        switch call.method {
        case "getBrightness":
          result(Double(UIScreen.main.brightness))

        case "setBrightness":
          let value = doubleArg(call, "value") ?? 0.5
          if savedBrightness == nil { savedBrightness = UIScreen.main.brightness }
          UIScreen.main.brightness = CGFloat(max(0, min(1, value)))
          result(Double(UIScreen.main.brightness))

        case "resetBrightness":
          restoreBrightness()
          result(true)

        case "getVolume":
          result(Double(AVAudioSession.sharedInstance().outputVolume))

        case "setVolume":
          let value = doubleArg(call, "value") ?? 1.0
          setSystemVolume(Float(max(0, min(1, value))))
          result(Double(AVAudioSession.sharedInstance().outputVolume))

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private static func restoreBrightness() {
    guard let saved = savedBrightness else { return }
    savedBrightness = nil
    UIScreen.main.brightness = saved
  }

  private static func doubleArg(_ call: FlutterMethodCall, _ key: String) -> Double? {
    guard let args = call.arguments as? [String: Any] else { return nil }
    return (args[key] as? NSNumber)?.doubleValue
  }

  private static func setSystemVolume(_ value: Float) {
    let view = volumeView ?? makeVolumeView()
    guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
    // A tick late: setting `value` inside the same run loop turn the view was
    // added in is ignored, and the first swipe of a session would be lost.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
      slider.value = value
      slider.sendActions(for: .valueChanged)
    }
  }

  private static func makeVolumeView() -> MPVolumeView {
    // Off-screen rather than hidden: `isHidden` stops the slider responding at
    // all, so it has to be in the hierarchy and simply out of sight.
    let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
    view.alpha = 0.001
    view.isUserInteractionEnabled = false
    keyWindow()?.addSubview(view)
    volumeView = view
    return view
  }

  private static func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }
}
