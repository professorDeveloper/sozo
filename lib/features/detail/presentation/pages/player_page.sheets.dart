// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// The player's sheets, dressed as iOS 26's on the native controls' path
/// ([showPlayerSheet], [PlayerSheetLook]); the same sheets as ever
/// everywhere else, widget for widget.
extension _PlayerSheets on _PlayerPageState {
  bool get _iosSheets => _nativeControls;

  Future<T?> _showSheet<T>({
    required WidgetBuilder builder,
    double desktopMaxWidth = 460,
  }) => showPlayerSheet<T>(
    context: context,
    ios: _iosSheets,
    desktopMaxWidth: desktopMaxWidth,
    builder: builder,
  );

  /// A sheet's title: the icon, the words and the rule under them, or iOS's
  /// centred title with its close button.
  List<Widget> _sheetHead(IconData icon, String title) => _iosSheets
      ? [IosSheetHeader(title: title)]
      : [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
        ];

  /// [rows] as one inset group on the iOS path, as they were elsewhere.
  List<Widget> _sheetGroup(List<Widget> rows, {double inset = 16}) => _iosSheets
      ? [IosSheetGroup(separatorInset: inset, children: rows)]
      : rows;
}
