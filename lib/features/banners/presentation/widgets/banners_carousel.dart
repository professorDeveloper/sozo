import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/banners/domain/entities/banner_item.dart';
import 'package:soplay/features/banners/presentation/bloc/banners_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

class BannersCarousel extends StatelessWidget {
  const BannersCarousel({
    super.key,
    required this.placement,
    this.height = 150,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  });

  final String placement;
  final double height;

  /// Applied only when the carousel actually has banners — an empty placement
  /// collapses to `SizedBox.shrink()` with no leftover gap in the feed.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<BannersBloc>()..add(BannersLoad(placement)),
      child: _CarouselView(height: height, padding: padding),
    );
  }
}

class _CarouselView extends StatefulWidget {
  const _CarouselView({required this.height, required this.padding});
  final double height;
  final EdgeInsets padding;

  @override
  State<_CarouselView> createState() => _CarouselViewState();
}

class _CarouselViewState extends State<_CarouselView> {
  final PageController _controller = PageController(viewportFraction: 0.92);
  final Set<String> _tracked = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trackView(BuildContext context, BannerItem item) {
    if (_tracked.add(item.id)) {
      context.read<BannersBloc>().add(BannersView(item.id));
    }
  }

  Future<void> _onTap(BuildContext context, BannerItem item) async {
    context.read<BannersBloc>().add(BannersClick(item.id));
    final link = item.link;
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BannersBloc, BannersState>(
      builder: (context, state) {
        if (state.loading && state.items.isEmpty) {
          return SizedBox(height: widget.height);
        }
        if (state.items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: widget.padding,
          child: SizedBox(
            height: widget.height,
            child: PageView.builder(
              controller: _controller,
              itemCount: state.items.length,
              onPageChanged: (index) {
                _trackView(context, state.items[index]);
              },
              itemBuilder: (context, index) {
                final item = state.items[index];
                if (index == 0) _trackView(context, item);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _BannerCard(
                    item: item,
                    onTap: () => _onTap(context, item),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.item, required this.onTap});
  final BannerItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: item.imageUrl,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => ColoredBox(
                color: AppColors.surfaceVariant,
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xCC000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
