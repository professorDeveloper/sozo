import Flutter
import UIKit

/// The player's controls as the phone's own glass buttons, hosted in Flutter
/// (lib/core/native/native_glass_bar.dart).
///
/// One view holds a whole group of controls — the top bar's actions, the
/// cluster round play, the bottom row — rather than one view per button:
/// each hosted view is a composition seam, and fifteen of them over 60 fps
/// video was the cost the shader path never had.
///
/// Dart lays the bar out and sends every slot's rect; this side only places
/// buttons there. Two looks:
/// - `capsule`: one clear glass capsule per group, plain buttons on it, as an
///   iOS 26 toolbar groups its items;
/// - `cluster`: each button its own glass circle (`.glass()`, or
///   `.prominentGlass()` for an item sent `prominent`), melting into its
///   neighbour when they are close.
///
/// Channel `soplay/native_player_bar/<id>`:
/// - Flutter → here: `setItems {items, look, dir, axis, capsules}` (buttons
///   rebuilt only when the ids change), `setItem {id, …changed}`,
///   `setShown {shown, ms}`.
/// - here → Flutter: `press id`, `longPress id`, `select {id, row}` once the
///   menu has gone, `menuOpen id`, `menuClose id`.
///
/// Flutter owns semantics: none of these buttons is an accessibility element.
enum NativePlayerBar {
  static let viewType = "soplay/native_player_bar"

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      NativePlayerBarFactory(messenger: registrar.messenger()), withId: viewType)
  }

  /// How many bars UIKit has really built since launch, for
  /// integration_test/native_glass_test.dart (`glassControlsBuilt`).
  static var built = 0
}

final class NativePlayerBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    guard #available(iOS 26.0, *) else { return EmptyBarView(frame: frame) }
    let args = args as? [String: Any] ?? [:]
    return MainActor.assumeIsolated {
      NativePlayerBarView(frame: frame, id: viewId, args: args, messenger: messenger)
    }
  }
}

/// Never reached: Dart asks only where `glassControls` is true.
private final class EmptyBarView: NSObject, FlutterPlatformView {
  private let box: UIView

  init(frame: CGRect) {
    box = UIView(frame: frame)
    box.backgroundColor = .clear
    box.isUserInteractionEnabled = false
  }

  func view() -> UIView { box }
}

/// Answers a finger only over a button; the gaps are Flutter's page.
@available(iOS 26.0, *)
private final class BarRoot: UIView {
  var buttons: [BarButton] = []

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    guard alpha > 0.01 else { return false }
    return buttons.contains {
      !$0.isHidden && $0.point(inside: convert(point, to: $0), with: event)
    }
  }
}

@available(iOS 26.0, *)
private final class BarButton: UIButton {
  var itemId = ""
  let hold = UILongPressGestureRecognizer()
  var onOpen: (() -> Void)?
  var onClose: (() -> Void)?
  var onSelect: ((Int) -> Void)?

  private var menuUp = false
  private var chosen: Int?

  private let ring = CAShapeLayer()

  var busy = false {
    didSet {
      guard busy != oldValue else { return }
      busy ? spin() : stop()
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    ring.fillColor = UIColor.clear.cgColor
    ring.strokeColor = UIColor.white.withAlphaComponent(0.7).cgColor
    ring.lineWidth = 2.5
    ring.lineCap = .round
    ring.strokeEnd = 0.28
    ring.isHidden = true
    layer.addSublayer(ring)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let inset = ring.lineWidth / 2
    // Over the glass the configuration lays in after it.
    layer.addSublayer(ring)
    ring.frame = bounds
    ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
  }

  private func spin() {
    ring.isHidden = false
    let turn = CABasicAnimation(keyPath: "transform.rotation.z")
    turn.fromValue = 0
    turn.toValue = CGFloat.pi * 2
    turn.duration = 0.9
    turn.repeatCount = .infinity
    ring.add(turn, forKey: "spin")
  }

  private func stop() {
    ring.removeAnimation(forKey: "spin")
    ring.isHidden = true
  }

  /// A row chosen while the menu is still leaving is said once it has gone:
  /// a sheet presented from it meanwhile is dropped by UIKit.
  func choose(_ row: Int) {
    if menuUp { chosen = row } else { onSelect?(row) }
  }

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willDisplayMenuFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    super.contextMenuInteraction(
      interaction, willDisplayMenuFor: configuration, animator: animator)
    menuUp = true
    onOpen?()
  }

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    super.contextMenuInteraction(
      interaction, willEndFor: configuration, animator: animator)
    if let animator {
      // The row's action may run just after the dismissal's completion.
      animator.addCompletion { [weak self] in
        DispatchQueue.main.async { self?.menuGone() }
      }
    } else {
      DispatchQueue.main.async { [weak self] in self?.menuGone() }
    }
  }

  private func menuGone() {
    guard menuUp else { return }
    menuUp = false
    if let row = chosen {
      chosen = nil
      onSelect?(row)
    }
    onClose?()
  }
}

@available(iOS 26.0, *)
final class NativePlayerBarView: NSObject, FlutterPlatformView {
  private let root: BarRoot
  private let container: UIVisualEffectView
  private let channel: FlutterMethodChannel

  private var look = "capsule"
  private var ids: [String] = []
  private var items: [String: [String: Any]] = [:]
  private var buttons: [String: BarButton] = [:]
  private var capsules: [UIVisualEffectView] = []

  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    root = BarRoot(frame: frame)
    let effect = UIGlassContainerEffect()
    effect.spacing = 8
    container = UIVisualEffectView(effect: effect)
    channel = FlutterMethodChannel(
      name: "\(NativePlayerBar.viewType)/\(id)", binaryMessenger: messenger)
    super.init()
    root.backgroundColor = .clear
    // The player is dark whatever the phone is.
    root.overrideUserInterfaceStyle = .dark
    root.accessibilityElementsHidden = true
    container.frame = root.bounds
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    root.addSubview(container)
    setItems(args)
    let shown = args["shown"] as? Bool ?? true
    root.alpha = shown ? 1 : 0
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    NativePlayerBar.built += 1
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { root }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "setItems":
      setItems(args)
      result(nil)
    case "setItem":
      if let id = args["id"] as? String, var item = items[id] {
        item.merge(args) { _, new in new }
        items[id] = item
        if let button = buttons[id] { apply(item, to: button, animated: true) }
      }
      result(nil)
    case "setShown":
      let shown = args["shown"] as? Bool ?? true
      let ms = (args["ms"] as? NSNumber)?.doubleValue ?? 0
      let target: CGFloat = shown ? 1 : 0
      if ms <= 0 {
        root.alpha = target
      } else {
        UIView.animate(
          withDuration: ms / 1000, delay: 0,
          options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]
        ) { self.root.alpha = target }
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setItems(_ args: [String: Any]) {
    let list = args["items"] as? [[String: Any]] ?? []
    let newLook = args["look"] as? String ?? "capsule"
    root.semanticContentAttribute =
      args["dir"] as? String == "rtl" ? .forceRightToLeft : .forceLeftToRight
    let newIds = list.compactMap { $0["id"] as? String }
    items = Dictionary(
      list.compactMap { item in (item["id"] as? String).map { ($0, item) } },
      uniquingKeysWith: { _, last in last })
    let rebuild = newIds != ids || newLook != look
    look = newLook
    ids = newIds
    if rebuild { build() }
    placeCapsules(args["capsules"] as? [[NSNumber]] ?? [])
    for id in ids {
      if let button = buttons[id], let item = items[id] {
        apply(item, to: button, animated: !rebuild)
      }
    }
  }

  private func build() {
    buttons.values.forEach { $0.removeFromSuperview() }
    buttons = [:]
    capsules.forEach { $0.removeFromSuperview() }
    capsules = []
    var all: [BarButton] = []
    for id in ids {
      let button = BarButton(type: .system)
      button.itemId = id
      button.isAccessibilityElement = false
      button.preferredMenuElementOrder = .fixed
      button.showsMenuAsPrimaryAction = false
      button.addAction(
        UIAction { [weak self] _ in self?.say("press", id) }, for: .primaryActionTriggered)
      button.onOpen = { [weak self] in self?.say("menuOpen", id) }
      button.onClose = { [weak self] in self?.say("menuClose", id) }
      button.onSelect = { [weak self] row in
        self?.channel.invokeMethod("select", arguments: ["id": id, "row": row])
      }
      button.hold.addTarget(self, action: #selector(held(_:)))
      button.addGestureRecognizer(button.hold)
      buttons[id] = button
      all.append(button)
    }
    root.buttons = all
  }

  @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began,
      let button = recognizer.view as? BarButton
    else { return }
    say("longPress", button.itemId)
  }

  private func say(_ method: String, _ id: String) {
    channel.invokeMethod(method, arguments: id)
  }

  /// One clear glass capsule per group in the capsule look; none in the
  /// cluster look, where every button is its own glass.
  private func placeCapsules(_ rects: [[NSNumber]]) {
    guard look == "capsule" else {
      for id in ids {
        if let button = buttons[id], button.superview !== container.contentView {
          container.contentView.addSubview(button)
        }
      }
      return
    }
    while capsules.count < rects.count {
      let glass = UIGlassEffect(style: .clear)
      glass.isInteractive = false
      glass.tintColor = UIColor.black.withAlphaComponent(0.22)
      let capsule = UIVisualEffectView(effect: glass)
      capsule.cornerConfiguration = .capsule()
      container.contentView.addSubview(capsule)
      capsules.append(capsule)
    }
    while capsules.count > rects.count {
      capsules.removeLast().removeFromSuperview()
    }
    for (i, rect) in rects.enumerated() {
      let r = cgRect(rect)
      capsules[i].bounds = CGRect(origin: .zero, size: r.size)
      capsules[i].center = CGPoint(x: r.midX, y: r.midY)
    }
    for id in ids {
      guard let button = buttons[id] else { continue }
      let group = (items[id]?["group"] as? NSNumber)?.intValue ?? 0
      let host = capsules.indices.contains(group)
        ? capsules[group].contentView : container.contentView
      if button.superview !== host { host.addSubview(button) }
    }
  }

  private func apply(_ item: [String: Any], to button: BarButton, animated: Bool) {
    let enabled = item["enabled"] as? Bool ?? true
    let active = item["active"] as? Bool ?? false
    let accent = (item["accent"] as? NSNumber).map { color($0.uint32Value) } ?? .white
    let base: UIColor = active ? accent : .white
    let tint = enabled ? base : base.withAlphaComponent(0.38)
    let glyph = CGFloat((item["glyph"] as? NSNumber)?.doubleValue ?? 20)
    let fontSize = CGFloat((item["fontSize"] as? NSNumber)?.doubleValue ?? 12)
    let title = item["title"] as? String
    let prominent = item["prominent"] as? Bool ?? false

    var config: UIButton.Configuration
    if look == "cluster" {
      config = prominent ? .prominentGlass() : .glass()
      if prominent { config.baseBackgroundColor = accent }
    } else {
      config = .plain()
    }
    config.cornerStyle = .capsule
    config.contentInsets = .zero
    // The colour is baked into the glyph: a glass configuration recolours a
    // template image with its own foreground, which lost the active accent.
    if let name = item["symbol"] as? String, !name.isEmpty {
      let symbol = UIImage.SymbolConfiguration(pointSize: glyph, weight: .semibold)
      if let image = UIImage(systemName: name, withConfiguration: symbol) {
        config.image = image.withTintColor(tint, renderingMode: .alwaysOriginal)
      } else {
        assertionFailure("No SF Symbol named \(name)")
      }
      config.imagePlacement = .leading
      config.imagePadding = 4
    }
    if let title, !title.isEmpty {
      let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
      config.attributedTitle = AttributedString(
        title, attributes: AttributeContainer([.font: font, .foregroundColor: tint]))
      config.titleLineBreakMode = .byClipping
    }
    config.baseForegroundColor = tint

    let titleChanged = button.configuration?.attributedTitle.map { String($0.characters) }
      != title.flatMap { $0.isEmpty ? nil : $0 }
    let set = { button.configuration = config }
    if animated && titleChanged {
      UIView.transition(with: button, duration: 0.18, options: .transitionCrossDissolve) { set() }
    } else {
      set()
    }
    button.isEnabled = enabled
    button.semanticContentAttribute = root.semanticContentAttribute
    button.isHidden = item["hidden"] as? Bool ?? false
    button.busy = item["busy"] as? Bool ?? false

    if let rows = item["menu"] as? [[String: Any]], !rows.isEmpty {
      button.menu = UIMenu(children: NativeMenuRows.elements(rows) { [weak button] row in
        button?.choose(row)
      })
    } else {
      button.menu = nil
    }
    // A menu opens on its own hold; only a button without one hears this.
    button.hold.isEnabled = button.menu == nil && item["longPress"] as? Bool == true

    place(button, item)
  }

  /// Bounds and centre, never frame: the glass's swell under a finger is a
  /// transform on the button.
  private func place(_ button: BarButton, _ item: [String: Any]) {
    guard let raw = item["rect"] as? [NSNumber] else { return }
    var r = cgRect(raw)
    if look == "capsule" {
      let group = (item["group"] as? NSNumber)?.intValue ?? 0
      if capsules.indices.contains(group) {
        let c = capsules[group]
        r = r.offsetBy(
          dx: -(c.center.x - c.bounds.width / 2), dy: -(c.center.y - c.bounds.height / 2))
      }
      button.bounds = CGRect(origin: .zero, size: r.size)
    } else {
      let size = CGFloat((item["size"] as? NSNumber)?.doubleValue ?? Double(min(r.width, r.height)))
      button.bounds = CGRect(x: 0, y: 0, width: min(size, r.width), height: min(size, r.height))
    }
    button.center = CGPoint(x: r.midX, y: r.midY)
  }

  private func cgRect(_ raw: [NSNumber]) -> CGRect {
    guard raw.count == 4 else { return .zero }
    return CGRect(
      x: raw[0].doubleValue, y: raw[1].doubleValue,
      width: raw[2].doubleValue, height: raw[3].doubleValue)
  }

  private func color(_ argb: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}
