import UIKit

/// The rows Dart sends for a hosted button's menu, as UIKit's menu elements
/// (lib/core/native/native_glass_bar.dart, `NativeMenuRow`).
///
/// A row is `{title, subtitle?, symbol?, checked?, breakBefore, section?,
/// destructive, disabled}`. Each run of rows between two breaks is an inline
/// group of its own, so UIKit draws the separator between them; a run's
/// first row may name it (`section`).
enum NativeMenuRows {
  /// [choose] is told the row's index, in the list as it was sent.
  static func elements(
    _ rows: [[String: Any]], choose: @escaping (Int) -> Void
  ) -> [UIMenuElement] {
    var groups: [(title: String, rows: [UIMenuElement])] = [("", [])]
    for (i, row) in rows.enumerated() {
      if row["breakBefore"] as? Bool == true, !(groups.last?.rows.isEmpty ?? true) {
        groups.append(("", []))
      }
      if groups[groups.count - 1].rows.isEmpty, let section = row["section"] as? String {
        groups[groups.count - 1].title = section
      }
      groups[groups.count - 1].rows.append(element(row, index: i, choose: choose))
    }
    if groups.count == 1, groups[0].title.isEmpty { return groups[0].rows }
    return groups.map { UIMenu(title: $0.title, options: .displayInline, children: $0.rows) }
  }

  private static func element(
    _ row: [String: Any], index: Int, choose: @escaping (Int) -> Void
  ) -> UIMenuElement {
    let title = row["title"] as? String ?? ""
    let image = (row["symbol"] as? String).flatMap { NativeSymbol.image($0) }
    let action = UIAction(title: title, image: image) { _ in choose(index) }
    if #available(iOS 16.0, *), let subtitle = row["subtitle"] as? String, !subtitle.isEmpty {
      action.subtitle = subtitle
    }
    if row["destructive"] as? Bool == true { action.attributes.insert(.destructive) }
    if row["disabled"] as? Bool == true { action.attributes.insert(.disabled) }
    if let checked = row["checked"] as? Bool { action.state = checked ? .on : .off }
    return action
  }
}

/// An SF Symbol by name, never nothing: a name this system lacks falls back
/// to its stem (`gobackward.7` → `gobackward`, `x.y.rotate` → `x.y`) and at
/// last to a plain circle, so a wrong name costs a glyph, not the button.
enum NativeSymbol {
  static func image(
    _ name: String, configuration: UIImage.SymbolConfiguration? = nil
  ) -> UIImage? {
    if name.isEmpty { return nil }
    if let image = UIImage(systemName: name, withConfiguration: configuration) {
      return image
    }
    assertionFailure("No SF Symbol named \(name)")
    var parts = name.split(separator: ".")
    while parts.count > 1 {
      parts.removeLast()
      if let image = UIImage(
        systemName: parts.joined(separator: "."), withConfiguration: configuration)
      {
        return image
      }
    }
    return UIImage(systemName: "circle", withConfiguration: configuration)
  }
}
