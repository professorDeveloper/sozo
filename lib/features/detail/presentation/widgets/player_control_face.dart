import 'package:flutter/widgets.dart';
import 'package:soplay/core/native/native_glass_bar.dart';
import 'package:soplay/core/native/sf_symbols.dart';
import 'package:soplay/features/detail/presentation/widgets/player_menus.dart';

/// One player control as it stands on a bar right now: what it shows, what it
/// does, whether it is on. The player builds one per control and draws it
/// either as its Flutter button or as a native glass button
/// ([toNative]), so the two can never disagree about what a control is.
///
/// Named a face, not a spec: `PlayerControlSpec` is the catalogue's entry
/// (where a control may go), this is what it looks like where it went.
@immutable
class PlayerControlFace {
  const PlayerControlFace({
    required this.id,
    required this.icon,
    required this.semanticLabel,
    this.symbol,
    this.label,
    this.compactLabel,
    this.compact = false,
    this.pill = false,
    this.tooltip,
    this.onTap,
    this.onLongPress,
    this.active = false,
    this.enabled = true,
    this.menu,
    this.menuPrimary = false,
    this.onMenu,
  });

  final String id;
  final IconData icon;
  final String semanticLabel;

  /// The SF Symbol; null takes the control's own ([playerSymbol]).
  final String? symbol;

  /// Words beside the glyph: the bottom row's live value, the language pill.
  final String? label;

  /// Drawn instead of the glyph on a compact row.
  final String? compactLabel;
  final bool compact;

  /// The language pill rather than a round button.
  final bool pill;

  /// The Flutter button's tooltip.
  final String? tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;
  final bool enabled;

  /// The rows a hold opens on the native button.
  final List<NativeMenuRow>? menu;

  /// The native button opens [menu] on a tap as well ([NativeBarItem.menuPrimary]).
  final bool menuPrimary;
  final ValueChanged<int>? onMenu;

  bool get labelled => label != null;

  /// This face with [menu] as its native pull-down: a tap on the native
  /// button opens it. Null leaves the face as it is.
  PlayerControlFace withMenu(PlayerMenu? menu) => menu == null
      ? this
      : PlayerControlFace(
          id: id,
          icon: icon,
          semanticLabel: semanticLabel,
          symbol: symbol,
          label: label,
          compactLabel: compactLabel,
          compact: compact,
          pill: pill,
          tooltip: tooltip,
          onTap: onTap,
          onLongPress: onLongPress,
          active: active,
          enabled: enabled,
          menu: menu.rows,
          menuPrimary: true,
          onMenu: menu.pick,
        );

  NativeBarItem toNative({int group = 0}) {
    final wordsOnly = compact && compactLabel != null;
    final title = pill
        ? label
        : wordsOnly
        ? compactLabel
        : compact
        ? null
        : label;
    return NativeBarItem(
      id: id,
      symbol: symbol ?? playerSymbol(id, active: active),
      title: title,
      semanticLabel: semanticLabel,
      enabled: enabled,
      active: active,
      hasGlyph: !wordsOnly,
      fontSize: pill ? 11 : 12,
      glyph: pill ? 14 : 20,
      group: group,
      onPressed: onTap,
      onLongPress: onLongPress,
      menu: menu,
      menuPrimary: menuPrimary,
      onMenuSelected: onMenu,
    );
  }
}
