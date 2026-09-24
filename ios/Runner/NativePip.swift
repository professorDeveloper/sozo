import AVFoundation
import AVKit
import Flutter
import UIKit

/// Picture-in-picture on iOS (`soplay/ios_pip`).
///
/// The in-app player draws through a Flutter texture, and neither video
/// engine it can use exposes a picture-in-picture controller — so the PiP
/// button did nothing on an iPhone. This hands the episode to a player of its
/// own: an AVPlayer on the same address with the same headers, at the same
/// second and speed, whose layer the system lifts into its window. When the
/// window closes the Flutter side is told where it got to and carries on
/// from there.
final class NativePip: NSObject, AVPictureInPictureControllerDelegate {
  static let shared = NativePip()

  private var channel: FlutterMethodChannel?
  private var player: AVPlayer?
  private var host: UIView?
  private var controller: AVPictureInPictureController?
  private var possible: NSKeyValueObservation?
  private var pending: FlutterResult?
  private var timeout: DispatchWorkItem?
  private var restored = false

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "soplay/ios_pip", binaryMessenger: messenger)
    shared.channel = channel
    channel.setMethodCallHandler { call, result in
      shared.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "start":
      let args = call.arguments as? [String: Any] ?? [:]
      DispatchQueue.main.async { self.start(args, result: result) }
    case "stop":
      DispatchQueue.main.async {
        self.controller?.stopPictureInPicture()
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(_ args: [String: Any], result: @escaping FlutterResult) {
    guard AVPictureInPictureController.isPictureInPictureSupported(),
          let raw = args["url"] as? String,
          let url = URL(string: raw)
    else {
      result(false)
      return
    }
    teardown()
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)

    let headers = args["headers"] as? [String: String] ?? [:]
    let asset = AVURLAsset(
      url: url,
      options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
    )
    let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    let position = (args["positionMs"] as? NSNumber)?.doubleValue ?? 0
    let rate = (args["rate"] as? NSNumber)?.floatValue ?? 1

    // The layer has to be in a window for the system to take it. It sits
    // behind the Flutter view, where nobody sees it, until the system lifts
    // its picture into the floating window.
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) })
      .first?.rootViewController?.view
    else {
      result(false)
      return
    }
    let host = UIView(frame: root.bounds)
    host.isUserInteractionEnabled = false
    host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let layer = AVPlayerLayer(player: player)
    layer.frame = host.bounds
    layer.videoGravity = .resizeAspect
    host.layer.addSublayer(layer)
    root.insertSubview(host, at: 0)

    guard let pip = AVPictureInPictureController(playerLayer: layer) else {
      host.removeFromSuperview()
      result(false)
      return
    }
    pip.delegate = self
    if #available(iOS 14.2, *) {
      pip.canStartPictureInPictureAutomaticallyFromInline = false
    }
    self.player = player
    self.host = host
    self.controller = pip
    self.pending = result
    self.restored = false

    player.seek(
      to: CMTime(value: CMTimeValue(position), timescale: 1000),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    )
    player.playImmediately(atRate: rate > 0 ? rate : 1)

    // Possible once the layer has a picture; started then.
    possible = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
      [weak self] pip, _ in
      guard pip.isPictureInPicturePossible else { return }
      DispatchQueue.main.async {
        self?.possible = nil
        pip.startPictureInPicture()
      }
    }
    let giveUp = DispatchWorkItem { [weak self] in
      guard let self = self, self.pending != nil else { return }
      self.finishPending(false)
      self.teardown()
    }
    timeout = giveUp
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: giveUp)
  }

  private func finishPending(_ ok: Bool) {
    timeout?.cancel()
    timeout = nil
    pending?(ok)
    pending = nil
  }

  private func positionMs() -> Int {
    guard let t = player?.currentTime(), t.isValid, t.isNumeric else { return 0 }
    return Int(CMTimeGetSeconds(t) * 1000)
  }

  private func teardown() {
    possible = nil
    player?.pause()
    player = nil
    controller = nil
    host?.removeFromSuperview()
    host = nil
  }

  // MARK: AVPictureInPictureControllerDelegate

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    finishPending(true)
    channel?.invokeMethod("started", arguments: nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    finishPending(false)
    channel?.invokeMethod("failed", arguments: error.localizedDescription)
    teardown()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    restored = true
    completionHandler(true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    let playing = (player?.rate ?? 0) > 0
    channel?.invokeMethod("stopped", arguments: [
      "positionMs": positionMs(),
      "playing": playing,
      "restored": restored,
    ])
    teardown()
  }
}
