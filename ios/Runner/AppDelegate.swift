import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// iOS 16+ scene-based lifecycle doesn't reliably forward Flutter's
  /// `SystemChrome.setPreferredOrientations` to the view controller, so we
  /// own the mask here. Updated from Flutter via the `app/orientation`
  /// channel; defaults to portrait so the rest of the app keeps its existing
  /// behavior.
  static var orientationLock: UIInterfaceOrientationMask = .portrait

  // Seek-preview frame generator (`soplay/preview` channel). AVAssetImageGenerator
  // samples frames from progressive AND HLS sources — so iOS gets working scrub
  // thumbnails even for CloudStream-style m3u8 streams (Android's
  // MediaMetadataRetriever can't do HLS).
  private var previewGenerator: AVAssetImageGenerator?
  private var previewURL: String?
  // bucketed-position -> JPEG bytes; holds the warm-up frame and any already
  // generated frames so repeat scrubs return instantly. Only touched on
  // previewQueue (serial), so no extra locking is needed.
  private var previewCache: [Int64: Data] = [:]
  private let previewQueue = DispatchQueue(label: "soplay.preview", qos: .userInitiated)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return AppDelegate.orientationLock
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppOrientation") else {
      return
    }
    let deeplinkChannel = FlutterMethodChannel(
      name: "soplay/deeplink_settings",
      binaryMessenger: registrar.messenger()
    )
    deeplinkChannel.setMethodCallHandler { call, result in
      guard call.method == "openDefaultLinksSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        } else {
          result(false)
        }
      }
    }

    // "Open with Sozo" on an extension index file. Same channel name and
    // contract as the Android host, so the Flutter side is platform-agnostic.
    RepoFileImport.register(messenger: registrar.messenger())
    SystemControls.register(with: registrar)
    NativePip.register(messenger: registrar.messenger())

    let previewChannel = FlutterMethodChannel(
      name: "soplay/preview",
      binaryMessenger: registrar.messenger()
    )
    previewChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "open":
        let urlStr = (args?["url"] as? String) ?? ""
        let headers = (args?["headers"] as? [String: String]) ?? [:]
        let warmMs = (args?["warmMs"] as? NSNumber)?.int64Value ?? -1
        self.previewQueue.async {
          self.openPreview(urlStr, headers, warmMs)
          DispatchQueue.main.async { result(true) }
        }
      case "frame":
        let posMs = (args?["posMs"] as? NSNumber)?.int64Value ?? 0
        self.previewQueue.async {
          let data = self.previewFrame(posMs)
          DispatchQueue.main.async {
            result(data == nil ? nil : FlutterStandardTypedData(bytes: data!))
          }
        }
      case "close":
        self.previewQueue.async {
          self.closePreview()
          DispatchQueue.main.async { result(true) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let channel = FlutterMethodChannel(
      name: "app/orientation",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "set",
            let args = call.arguments as? [String: Any],
            let modes = args["modes"] as? [String] else {
        result(FlutterMethodNotImplemented)
        return
      }

      var mask: UIInterfaceOrientationMask = []
      for mode in modes {
        switch mode {
        case "portraitUp":     mask.insert(.portrait)
        case "portraitDown":   mask.insert(.portraitUpsideDown)
        // Flutter's landscape naming is mirrored vs UIKit's, so swap.
        case "landscapeLeft":  mask.insert(.landscapeRight)
        case "landscapeRight": mask.insert(.landscapeLeft)
        default: break
        }
      }
      if mask.isEmpty { mask = .portrait }
      AppDelegate.orientationLock = mask

      DispatchQueue.main.async {
        if #available(iOS 16.0, *) {
          UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
              scene.requestGeometryUpdate(
                .iOS(interfaceOrientations: mask)
              ) { _ in }
              scene.windows.forEach { window in
                window.rootViewController?
                  .setNeedsUpdateOfSupportedInterfaceOrientations()
              }
            }
        } else {
          UIViewController.attemptRotationToDeviceOrientation()
        }
        result(nil)
      }
    }
  }

  // MARK: - Seek-preview frame generation

  private func openPreview(
    _ urlStr: String, _ headers: [String: String], _ warmMs: Int64 = -1
  ) {
    if previewURL == urlStr && previewGenerator != nil { return }
    closePreview()
    guard let url = URL(string: urlStr) else { return }
    var options: [String: Any] = [:]
    // Pass playback headers (Referer/User-Agent/cookies) so protected CDNs serve
    // the asset to the generator the same way the player gets it.
    if !headers.isEmpty {
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    let asset = AVURLAsset(url: url, options: options)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: 360, height: 360)
    // Allow a couple seconds of tolerance so it can snap to the nearest decodable
    // frame quickly instead of decoding an exact (slow) position.
    gen.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
    gen.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
    previewGenerator = gen
    previewURL = urlStr
    // Warm the generator at the start/resume position so the first scrub there is
    // already decoded and cached instead of cold-starting on first drag.
    if warmMs >= 0 { _ = previewFrame(warmMs) }
  }

  private func previewFrame(_ posMs: Int64) -> Data? {
    if let cached = previewCache[posMs] { return cached }
    guard let gen = previewGenerator else { return nil }
    let time = CMTime(value: posMs, timescale: 1000)
    do {
      let cg = try gen.copyCGImage(at: time, actualTime: nil)
      let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.78)
      if let data = data { previewCache[posMs] = data }
      return data
    } catch {
      return nil
    }
  }

  private func closePreview() {
    previewGenerator?.cancelAllCGImageGeneration()
    previewGenerator = nil
    previewURL = nil
    previewCache.removeAll()
  }
}
