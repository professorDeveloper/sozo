import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/data/extension_repo_repository.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';

/// The "Recommended" block shared by every sources page.
///
/// Previously each page carried its own hardcoded `const _recommended` list and
/// its own copy of the tile markup. They drifted (only the manga one was
/// localised, only the manga one had an NSFW gate) and, worse, a repo that moved
/// or died could only be fixed by shipping a build. This renders whatever the
/// backend serves for [kind], falling back to the compiled-in defaults.
class RecommendedReposSection extends StatefulWidget {
  const RecommendedReposSection({
    super.key,
    required this.kind,
    required this.installedUrls,
    required this.busy,
    required this.onInstall,
    required this.accent,
    required this.fallbackIcon,
    this.nsfwAllowed = false,
    this.title = 'RECOMMENDED',
  });

  final ExtensionRepoKind kind;

  /// Urls already installed, used to render the "Installed" chip. A Mangayomi
  /// entry counts as installed once *every* index it carries is present.
  final Set<String> installedUrls;
  final bool busy;

  /// Installs one entry. Receives every index url the entry carries, in order.
  final Future<void> Function(ExtensionRepoEntity repo) onInstall;

  final Color accent;
  final String fallbackIcon;
  final bool nsfwAllowed;
  final String title;

  @override
  State<RecommendedReposSection> createState() =>
      _RecommendedReposSectionState();
}

class _RecommendedReposSectionState extends State<RecommendedReposSection> {
  late Future<List<ExtensionRepoEntity>> _future = _load();
  bool _hidden = false;

  Future<List<ExtensionRepoEntity>> _load() => getIt<ExtensionRepoRepository>()
      .recommended(widget.kind, nsfwAllowed: widget.nsfwAllowed);

  @override
  void didUpdateWidget(RecommendedReposSection old) {
    super.didUpdateWidget(old);
    // The adult-sources toggle changes which entries are visible.
    if (old.nsfwAllowed != widget.nsfwAllowed || old.kind != widget.kind) {
      _future = _load();
    }
  }

  bool _isInstalled(ExtensionRepoEntity repo) =>
      repo.allUrls.every((u) => widget.installedUrls.contains(u.trim()));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ExtensionRepoEntity>>(
      future: _future,
      builder: (context, snap) {
        final repos = snap.data ?? const <ExtensionRepoEntity>[];
        // Nothing to show and nothing loading — render nothing rather than an
        // empty labelled block.
        if (repos.isEmpty && snap.connectionState == ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded, size: 15, color: widget.accent),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textHint,
                        letterSpacing: 1,
                      ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _hidden = !_hidden),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      _hidden ? 'general.show'.tr() : 'general.hide'.tr(),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (!_hidden) ...[
              const SizedBox(height: 8),
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                ...repos.map(_tile),
            ],
          ],
        );
      },
    );
  }

  Widget _tile(ExtensionRepoEntity repo) {
    final installed = _isInstalled(repo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: (widget.busy || installed) ? null : () => widget.onInstall(repo),
          splashColor: widget.accent.withValues(alpha: 0.12),
          highlightColor: widget.accent.withValues(alpha: 0.06),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: installed
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _icon(repo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              repo.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (repo.badge != null && repo.badge!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _Badge(text: repo.badge!, color: widget.accent),
                          ],
                          if (repo.nsfw) ...[
                            const SizedBox(width: 6),
                            const _Badge(text: '18+', color: Colors.redAccent),
                          ],
                        ],
                      ),
                      if (repo.description.isNotEmpty)
                        Text(
                          repo.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (installed)
                  const _InstalledChip()
                else
                  Icon(
                    Icons.download_rounded,
                    size: 20,
                    color: widget.busy ? AppColors.textHint : widget.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(ExtensionRepoEntity repo) {
    final url = (repo.iconUrl?.isNotEmpty ?? false)
        ? repo.iconUrl!
        : widget.fallbackIcon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(
        url,
        width: 30,
        height: 30,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 30,
          height: 30,
          color: Colors.white10,
          child: const Icon(Icons.extension_outlined,
              color: Colors.white54, size: 17),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _InstalledChip extends StatelessWidget {
  const _InstalledChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              'general.installed'.tr(),
              style: const TextStyle(
                color: Colors.green,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}
