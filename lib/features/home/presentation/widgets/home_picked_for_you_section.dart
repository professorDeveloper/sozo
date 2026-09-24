import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/home/presentation/widgets/home_movie_section.dart';
import 'package:soplay/features/onboarding/data/genre_catalog.dart';
import 'package:soplay/features/onboarding/data/picked_for_you.dart';

/// The "Picked for you" band: titles from one of the genres this profile
/// picked, a different one each day. Draws nothing until genres are picked.
class HomePickedForYouSection extends StatefulWidget {
  const HomePickedForYouSection({super.key});

  @override
  State<HomePickedForYouSection> createState() =>
      _HomePickedForYouSectionState();
}

class _HomePickedForYouSectionState extends State<HomePickedForYouSection> {
  final HiveService _hive = getIt<HiveService>();
  final PickedForYouSource _source = getIt<PickedForYouSource>();
  PickedForYou? _data;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _hive.tasteChanged.addListener(_load);
    _hive.contentModeChanged.addListener(_load);
    _load(initial: true);
  }

  @override
  void dispose() {
    _hive.tasteChanged.removeListener(_load);
    _hive.contentModeChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    final taste = _hive.getTasteProfile();
    final mode = ContentMode.fromId(_hive.getContentMode());
    final generation = ++_generation;
    final cached = _source.peek(taste, mode);
    final hasTargets = taste.browseTargets(mode).isNotEmpty;
    void apply() {
      _data = cached;
      _loading = cached == null && hasTargets;
    }

    initial ? apply() : setState(apply);
    if (cached != null || !hasTargets) return;
    final data = await _source.fetch(taste, mode);
    if (!mounted || generation != _generation) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return _loading ? const CollectionLoadingRow() : const SizedBox.shrink();
    }
    return MovieSection(
      title:
          '${'home_rails.picked_for_you'.tr()} · ${genreDisplayName(data.genre)}',
      movies: data.items,
      type: 'catalogue-genre',
      slug: data.slug,
    );
  }
}
