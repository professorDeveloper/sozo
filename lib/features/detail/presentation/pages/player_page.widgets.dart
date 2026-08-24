part of 'player_page.dart';

/// The controls sit directly on the frame, so a white-on-video label can land
/// on a blown-out highlight and disappear. A tight drop shadow restores the
/// edge without putting a container behind the control.
const List<Shadow> _kControlShadow = <Shadow>[
  Shadow(color: Color(0xB3000000), blurRadius: 6, offset: Offset(0, 1)),
];

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.3).animate(_c),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: Color(0xFFFF3B30),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _FittedVideo extends StatelessWidget {
  const _FittedVideo({required this.controller, required this.fit});
  final PlayerController controller;
  final _PlayerFit fit;

  @override
  Widget build(BuildContext context) {
    if (controller.letterboxesInternally) {
      final boxFit = switch (fit) {
        _PlayerFit.contain => BoxFit.contain,
        _PlayerFit.cover => BoxFit.cover,
        _PlayerFit.fill => BoxFit.fill,
      };
      return controller.buildView(fit: boxFit);
    }

    final size = controller.value.size;
    final hasSize = size.width > 0 && size.height > 0;
    final natW = hasSize ? size.width : 1920.0;
    final natH = hasSize ? size.height : 1080.0;
    final aspect = natW / natH;

    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final boxH = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final boxAspect = boxH == 0 ? aspect : boxW / boxH;

        double targetW;
        double targetH;
        switch (fit) {
          case _PlayerFit.contain:
            if (aspect > boxAspect) {
              targetW = boxW;
              targetH = boxW / aspect;
            } else {
              targetH = boxH;
              targetW = boxH * aspect;
            }
          case _PlayerFit.cover:
            if (aspect > boxAspect) {
              targetH = boxH;
              targetW = boxH * aspect;
            } else {
              targetW = boxW;
              targetH = boxW / aspect;
            }
          case _PlayerFit.fill:
            targetW = boxW;
            targetH = boxH;
        }

        return ClipRect(
          child: SizedBox(
            width: boxW,
            height: boxH,
            child: Center(
              child: SizedBox(
                width: targetW,
                height: targetH,
                child: controller.buildView(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ControlsScrim extends StatelessWidget {
  const _ControlsScrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // The bottom band has to cover the whole seek row *and* the action
          // row beneath it, which reach ~30% up the screen in landscape — the
          // old 0.82 stop left both of them sitting on bare video.
          colors: [
            Color(0xD9000000),
            Color(0x4D000000),
            Color(0x00000000),
            Color(0x59000000),
            Color(0xE6000000),
          ],
          stops: [0.0, 0.20, 0.46, 0.70, 1.0],
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.stage, required this.title});

  final _LoadingStage stage;
  final String title;

  String get _label {
    switch (stage) {
      case _LoadingStage.resolving:
        return 'player.extracting_media'.tr();
      case _LoadingStage.loading:
        return 'player.loading_video'.tr();
    }
  }

  String get _hint {
    switch (stage) {
      case _LoadingStage.resolving:
        return 'player.fetching_link'.tr();
      case _LoadingStage.loading:
        return 'player.preparing_stream'.tr();
    }
  }

  IconData get _icon {
    switch (stage) {
      case _LoadingStage.resolving:
        return Icons.cloud_download_outlined;
      case _LoadingStage.loading:
        return Icons.movie_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(_icon, color: Colors.white70, size: 36),
            const SizedBox(height: 14),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Column(
                key: ValueKey(stage),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap, this.color});
  final IconData icon;
  final VoidCallback onTap;

  /// When set, tints the icon (and gives a subtle matching background) — used
  /// to show an "active" state, e.g. the Watch Party button while in a party.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return _tvRing(
      circle: true,
      Material(
        color: color != null
            ? color!.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              color: color ?? Colors.white,
              size: 18,
              shadows: _kControlShadow,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopVolumeControl extends StatelessWidget {
  const _DesktopVolumeControl({
    required this.volume,
    required this.onChanged,
    required this.onToggleMute,
  });

  final double volume;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;

  IconData get _icon => volume <= 0.001
      ? Icons.volume_off_rounded
      : volume < 0.5
          ? Icons.volume_down_rounded
          : Icons.volume_up_rounded;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          final step = e.scrollDelta.dy < 0 ? 0.05 : -0.05;
          onChanged((volume + step).clamp(0.0, 1.0));
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconButton(icon: _icon, onTap: onToggleMute),
          SizedBox(
            width: 104,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: volume.clamp(0.0, 1.0),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  const _LangPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Every one of its neighbours in the top bar draws a focus ring; without
    // one this pill took D-pad focus with nothing to show for it.
    return _tvRing(
      radius: 20,
      Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.translate_rounded,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _CenterIconButton extends StatelessWidget {
  const _CenterIconButton({
    required this.icon,
    required this.onTap,
    this.large = false,
    this.busy = false,
    this.focusNode,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool large;

  /// Draws the buffering ring on the button's own rim. Swapping the whole
  /// cluster out for a spinner made the controls jump on every micro-stall and,
  /// on TV, unmounted the node the remote was parked on.
  final bool busy;

  /// Supplied only on TV, so the remote can be parked on this button whenever
  /// the overlay reappears. Null everywhere else — the InkWell then manages its
  /// own node exactly as it does today.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 52.0;
    final iconSize = large ? 42.0 : 28.0;
    return _tvRing(
      circle: true,
      Material(
        // These buttons sit at the vertical centre, where the scrim is fully
        // transparent — 32% black left a white glyph invisible on a bright shot.
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          focusNode: focusNode,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: iconSize,
                  shadows: _kControlShadow,
                ),
                if (busy)
                  const Positioned.fill(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomTextButton extends StatelessWidget {
  const _BottomTextButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white : Colors.white38;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: _tvRing(
        radius: 6,
        InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18, shadows: _kControlShadow),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  shadows: _kControlShadow,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.isActive,
    required this.onTap,
  });

  final EpisodeEntity episode;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = episode.label.trim().isEmpty
        ? 'player.episode_n'.tr(args: ['${episode.episode}'])
        : episode.label;
    return InkWell(
      onTap: onTap,
      // On TV the panel opens with the remote already on the episode being
      // watched, so OK re-plays it and up/down walks the list from there.
      autofocus: isTvPlatform && isActive,
      focusColor: _kTvFocusFill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                episode.episode.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: isActive ? AppColors.primary : Colors.white54,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (isActive)
              Icon(
                Icons.play_arrow_rounded,
                color: AppColors.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.source,
    required this.isActive,
    required this.onTap,
  });

  final VideoSourceEntity source;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      autofocus: isTvPlatform && isActive,
      focusColor: _kTvFocusFill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              isActive
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isActive ? AppColors.primary : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                source.quality,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (source.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'player.default'.tr(),
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      focusColor: _kTvFocusFill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              color: disabled ? Colors.white38 : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 14),
            // Both halves flex: a fixed-width label overflowed the row as soon
            // as a translation ran long, and took the value with it.
            Expanded(
              flex: 3,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: disabled ? Colors.white54 : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (value.isNotEmpty) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: disabled ? Colors.white38 : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            if (!disabled) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white54,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      // Land the remote on the value that is already active, the way the
      // episode and quality rows in the side panel do. Without it the sheet
      // opened with focus on the first row, so "change the subtitle track"
      // started by moving *away* from the current one — and if nothing else
      // claimed focus the D-pad appeared dead entirely.
      autofocus: isTvPlatform && selected,
      focusColor: _kTvFocusFill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppColors.primary : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SubtitlePreview extends StatelessWidget {
  const _SubtitlePreview({required this.style});
  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    final color = Color(style.textColor);
    final weight = style.bold ? FontWeight.w800 : FontWeight.w500;
    final hasBg = style.bgOpacity > 0.01;

    List<Shadow>? shadows;
    Paint? strokePaint;
    switch (style.edge) {
      case SubtitleEdge.none:
        break;
      case SubtitleEdge.shadow:
        shadows = const [
          Shadow(
            color: Color(0xCC000000),
            offset: Offset(0, 1.5),
            blurRadius: 4,
          ),
        ];
      case SubtitleEdge.outline:
        strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF000000);
    }

    Widget textWidget = Text(
      'The quick brown fox',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: style.fontSize,
        fontWeight: weight,
        height: 1.3,
        shadows: shadows,
      ),
    );

    if (strokePaint != null) {
      textWidget = Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'The quick brown fox',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: style.fontSize,
              fontWeight: weight,
              height: 1.3,
              foreground: strokePaint,
            ),
          ),
          textWidget,
        ],
      );
    }

    Widget body = textWidget;
    if (hasBg) {
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: style.bgOpacity),
          borderRadius: BorderRadius.circular(6),
        ),
        child: textWidget,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1F2A44),
              Color(0xFF2D1B36),
              Color(0xFF1A1A1A),
            ],
          ),
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
        child: body,
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dot = AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? AppColors.primary : Colors.white24,
            width: selected ? 3 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
    );
    if (!isTvPlatform) return GestureDetector(onTap: onTap, child: dot);
    // A bare GestureDetector cannot take focus, which would make the subtitle
    // colour swatches unreachable by remote. InkWell is focusable; the ripple
    // it adds is TV-only, so the phone sheet is pixel-identical.
    return _tvRing(
      circle: true,
      Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: dot,
        ),
      ),
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _Chip(
              label: items[i].$2,
              selected: items[i].$1 == value,
              onTap: () => onChanged(items[i].$1),
            ),
          ),
          if (i < items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.18)
          : Colors.white10,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        focusColor: _kTvFocusFill,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratedFramePreview extends StatefulWidget {
  const _GeneratedFramePreview({
    required this.url,
    required this.headers,
    required this.positionMs,
  });

  final String url;
  final Map<String, String> headers;
  final int positionMs;

  @override
  State<_GeneratedFramePreview> createState() => _GeneratedFramePreviewState();
}

class _GeneratedFramePreviewState extends State<_GeneratedFramePreview> {
  static const double _w = 160;
  static const double _h = 90;
  Uint8List? _bytes;
  bool _failed = false;

  int get _bucket => widget.positionMs ~/ FramePreviewService.bucketMs;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_GeneratedFramePreview old) {
    super.didUpdateWidget(old);
    if (old.positionMs ~/ FramePreviewService.bucketMs != _bucket ||
        old.url != widget.url) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final bytes = await FramePreviewService.previewFrame(
        widget.url, widget.headers, widget.positionMs);
    if (!mounted) return;
    if (bytes != null) {
      setState(() {
        _bytes = bytes;
        _failed = false;
      });
    } else if (_bytes == null && !_failed) {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b != null) {
      return Image.memory(
        b,
        width: _w,
        height: _h,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }
    if (_failed) return const SizedBox.shrink();
    return Container(
      width: _w,
      height: _h,
      color: Colors.black54,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      ),
    );
  }
}
