import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../domain/home_content_kind.dart';
import '../../domain/entities/view_all.dart';

class HomeMediumDiscovery extends StatelessWidget {
  const HomeMediumDiscovery({super.key, required this.kind});
  final HomeContentKind kind;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'home.explore_${kind.name}'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('AniList', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const [
                  ('trending', 'search.discovery.trending', Icons.trending_up),
                  ('rating', 'search.discovery.highest', Icons.star_outline),
                  ('releasing', 'search.discovery.releasing', Icons.update),
                ])
                  ActionChip(
                    avatar: Icon(entry.$3, size: 18),
                    label: Text(entry.$2.tr()),
                    onPressed: () => context.push(
                      '/view-all',
                      extra: ViewAllEntity(
                        type: 'catalogue-discover',
                        slug: '${kind.catalogueKind}:${entry.$1}',
                        name:
                            '${'home.explore_${kind.name}'.tr()} · ${entry.$2.tr()}',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
