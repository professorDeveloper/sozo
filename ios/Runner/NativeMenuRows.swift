import UIKit

/// The rows Dart sends for a hosted button's menu, as UIKit's menu elements
/// (lib/core/native/native_glass_bar.dart, `NativeMenuRow`).
///
/// A row is `{title, symbol?, checked?, breakBefore, destructive}`. Each run
/// of rows between two breaks is an inline group of its own, so UIKit draws
/// the separator between them.
enum NativeMenuRows {
  /// [choose] is told the row's index, in the list as it was sent.
  static func elements(
    _ rows: [[String: Any]], choose: @escaping (Int) -> Void
  ) -> [UIMenuElement] {
    var groups: [[UIMenuElement]] = [[]]
    for (i, row) in rows.enumerated() {
      if row["breakBefore"] as? Bool == true, !(groups.last?.isEmpty ?? true) {
        groups.append([])
      }
      groups[groups.count - 1].append(element(row, index: i, choose: choose))
    }
    if groups.count == 1 { return groups[0] }
    return groups.map { UIMenu(options: .displayInline, children: $0) }
  }

  private static func element(
    _ row: [String: Any], index: Int, choose: @escaping (Int) -> Void
  ) -> UIMenuElement {
    let title = row["title"] as? String ?? ""
    let image = (row["symbol"] as? String).flatMap { UIImage(systemName: $0) }
    let action = UIAction(title: title, image: image) { _ in choose(index) }
    if row["destructive"] as? Bool == true { action.attributes.insert(.destructive) }
    if let checked = row["checked"] as? Bool { action.state = checked ? .on : .off }
    return action
  }
}
