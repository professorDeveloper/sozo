import 'package:soplay/features/profile/data/datasources/provider_data_source.dart';
import 'package:soplay/features/profile/data/models/provider_model.dart';

class ProviderRegistry {
  final ProviderDataSource source;
  List<ProviderModel>? _cache;
  Future<List<ProviderModel>>? _loading;

  ProviderRegistry({required this.source});

  Future<ProviderModel?> getById(String id) async {
    if (id.isEmpty) return null;
    final list = await _ensure();
    for (final p in list) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> preload() async {
    await _ensure();
  }

  Future<List<ProviderModel>> _ensure() {
    if (_cache != null) return Future.value(_cache);
    return _loading ??= source
        .getProviders()
        .then((list) {
          _cache = list;
          _loading = null;
          return list;
        })
        .catchError((Object _) {
          _loading = null;
          return <ProviderModel>[];
        });
  }

  void invalidate() {
    _cache = null;
    _loading = null;
  }
}
