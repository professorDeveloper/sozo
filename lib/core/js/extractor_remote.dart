import 'package:dio/dio.dart';

class ExtractorAsset {
  final String name;
  final int version;
  final String scope;
  final String url;

  const ExtractorAsset({
    required this.name,
    required this.version,
    required this.scope,
    required this.url,
  });
}

class ExtractorManifest {
  final ExtractorAsset runtime;
  final List<ExtractorAsset> items;

  const ExtractorManifest({required this.runtime, required this.items});

  ExtractorAsset? byName(String name) {
    for (final item in items) {
      if (item.name == name) return item;
    }
    return null;
  }
}

class ExtractorRemote {
  final Dio dio;
  const ExtractorRemote({required this.dio});

  Future<ExtractorManifest> fetchManifest() async {
    final response = await dio.get(
      '/extractors',
      options: Options(extra: const {'skipAuthInterceptor': true}),
    );
    final data = response.data as Map<String, dynamic>;
    final runtimeRaw = (data['runtime'] as Map?)?.cast<String, dynamic>();
    final itemsRaw = (data['items'] as List?) ?? const [];
    return ExtractorManifest(
      runtime: _asset(runtimeRaw ?? const {'name': 'runtime'}),
      items: itemsRaw
          .whereType<Map>()
          .map((e) => _asset(e.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  Future<({String code, int version})> fetchRuntime() async {
    final response = await dio.get<String>(
      '/extractors/runtime',
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAuthInterceptor': true},
      ),
    );
    return (code: response.data ?? '', version: _versionHeader(response));
  }

  Future<({String code, int version})> fetchExtractor(String name) async {
    final response = await dio.get<String>(
      '/extractors/$name',
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAuthInterceptor': true},
      ),
    );
    return (code: response.data ?? '', version: _versionHeader(response));
  }

  int _versionHeader(Response response) {
    final raw = response.headers.value('x-extractor-version');
    return int.tryParse(raw ?? '') ?? 0;
  }

  ExtractorAsset _asset(Map<String, dynamic> raw) {
    return ExtractorAsset(
      name: raw['name'] as String? ?? '',
      version: (raw['version'] as num?)?.toInt() ?? 0,
      scope: raw['scope'] as String? ?? '',
      url: raw['url'] as String? ?? '',
    );
  }
}
