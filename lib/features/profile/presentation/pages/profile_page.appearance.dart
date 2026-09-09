// ignore_for_file: unused_element
part of 'profile_page.dart';

/// Theme, accent and darkness controls.
class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection({this.showLabel = true});

  /// When false (the standalone Navigation-bar page), the "APPEARANCE" label
  /// and the redundant inner "Navigation bar" header are hidden.
  final bool showLabel;

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late bool _native = getIt<HiveService>().useNativeTitleBar;
  late String _navStyle = getIt<HiveService>().navStyle;

  Future<void> _toggle(bool value) async {
    setState(() => _native = value);
    await getIt<HiveService>().setUseNativeTitleBar(value);
    await DesktopWindow.setNativeTitleBar(value);
  }

  Future<void> _setNavStyle(String value) async {
    if (value == _navStyle) return;
    setState(() => _navStyle = value);
    await getIt<HiveService>().setNavStyle(value);
    // Push to the shared notifier so the floating nav rebuilds instantly.
    NavPrefs.navStyle.value = value;
  }

  // A tiny realistic mock of each nav style: solid/glass = a floating pill,
  // classic = a full-width bar — with mini tab icons (the first = selected,
  // in a little pill, like the real bar) instead of plain dots.
  Widget _navPreview(String value, Color accent) {
    const icons = [
      Icons.home_rounded,
      Icons.search_rounded,
      Icons.play_arrow_rounded,
      Icons.person_rounded,
    ];
    final muted = accent.withValues(alpha: 0.4);
    Widget miniIcon(int i) {
      if (i == 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 1),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icons[i], size: 9, color: accent),
        );
      }
      return Icon(icons[i], size: 9, color: muted);
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: miniIcon(i),
          ),
      ],
    );

    if (value == 'classic') {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          border: Border(
            top: BorderSide(color: accent.withValues(alpha: 0.4), width: 0.6),
          ),
        ),
        child: row,
      );
    }
    // solid / glass: floating rounded pill
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: value == 'glass'
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.26),
                  accent.withValues(alpha: 0.06),
                ],
              )
            : null,
        color: value == 'solid' ? accent.withValues(alpha: 0.16) : null,
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 0.8),
      ),
      child: row,
    );
  }

  Widget _navSegment(String value, String labelKey) {
    final selected = _navStyle == value;
    final accent = selected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setNavStyle(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.fromLTRB(6, 9, 6, 7),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 24,
                child: Center(child: _navPreview(value, accent)),
              ),
              const SizedBox(height: 7),
              Text(
                labelKey.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showLabel) ...[
            SettingsLabel('profile.section_appearance'.tr()),
          ],
          SettingsCard(
            children: [
              if (isDesktopPlatform)
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _native,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(
                    Icons.web_asset_rounded,
                    color: AppColors.textSecondary,
                  ),
                  title: Text(
                    'profile.native_window_bar'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    'profile.native_window_bar_subtitle'.tr(),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: _toggle,
                ),
              if (isMobilePlatform) ...[
                if (widget.showLabel)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.dashboard_customize_rounded,
                          size: 18,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'profile.nav_style'.tr(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _navSegment('solid', 'profile.nav_style_solid'),
                        _navSegment('glass', 'profile.nav_style_glass'),
                        _navSegment('classic', 'profile.nav_style_classic'),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: const Icon(
                        Icons.view_week_rounded,
                        color: AppColors.textSecondary,
                      ),
                      title: Text(
                        'nav_customize.entry_title'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'nav_customize.entry_subtitle'.tr(),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const SettingsChevron(),
                      onTap: () => showTabCustomizer(context),
                    ),
                  ),
                ),
                // Next to the tab customizer, because they are the same
                // question asked about two surfaces — what is on screen, and
                // in what order. Splitting them across two sections is how
                // somebody finds one and never learns the other exists.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: const Icon(
                        Icons.dashboard_customize_outlined,
                        color: AppColors.textSecondary,
                      ),
                      title: Text(
                        'home_rails.entry_title'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'home_rails.entry_subtitle'.tr(),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const SettingsChevron(),
                      onTap: () => showHomeRailCustomizer(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Standalone Navigation-bar settings page (tab-bar style + tab customizer),
/// opened from the Profile "Navigation bar" tile.
