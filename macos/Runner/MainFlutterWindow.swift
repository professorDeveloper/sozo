import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// What the window was before it floated as the mini player (see the
  /// `sozo/pip_window` channel), put back when it stops floating.
  private var savedBehavior: NSWindow.CollectionBehavior = []
  private var savedLevel: NSWindow.Level = .normal
  private var floating = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The app is always dark (ThemeMode.dark, background 0xFF181818). Force a
    // dark window appearance so the native title bar / traffic-light region and
    // any window chrome render dark regardless of the macOS system Light/Dark
    // setting. Also paint the window background dark to avoid a white flash
    // before Flutter's first frame.
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = NSColor(
      red: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x18 / 255.0, alpha: 1.0)

    // Hover reaches the view even while another app is in front. The mini
    // player's controls appear on hover, and with the default (key window
    // only) they stayed hidden until the viewer clicked, which also brought
    // all of Sozo forward.
    flutterViewController.mouseTrackingMode = .always

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPipChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// The mini player floats the way Chrome's and Telegram's picture-in-picture
  /// windows do: above other apps, on every Space, and beside another app's
  /// full-screen window rather than being left behind on the desktop Space.
  /// window_manager's setAlwaysOnTop only raises the level, and sets none of
  /// the collection behaviour that decides which Spaces a window is on.
  private func registerPipChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "sozo/pip_window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "enterFloat":
        if !self.floating {
          self.savedBehavior = self.collectionBehavior
          self.savedLevel = self.level
          self.floating = true
        }
        var behavior = self.collectionBehavior
        // A window cannot both follow the active Space and be on all of them,
        // and one that may go full screen is not allowed beside another
        // app's full-screen window: auxiliary instead of primary.
        behavior.remove([.fullScreenPrimary, .moveToActiveSpace, .managed])
        behavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary])
        if #available(macOS 13.0, *) { behavior.insert(.canJoinAllApplications) }
        self.collectionBehavior = behavior
        // Above floating panels and other apps' always-on-top windows, as
        // Telegram's modal-panel level is.
        self.level = .modalPanel
        self.orderFrontRegardless()
        result(nil)
      case "exitFloat":
        if self.floating {
          // Back before anything asks for full screen again: without
          // .fullScreenPrimary the window refuses it.
          self.collectionBehavior = self.savedBehavior
          self.level = self.savedLevel
          self.floating = false
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
