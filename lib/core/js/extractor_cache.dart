import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';

class ExtractorCache {
  final Box _box = Hive.box(AppConstants.extractorsBox);

  String _codeKey(String name, int version) => 'code:$name:v$version';
  String _versionKey(String name) => 'ver:$name';

  String? readCode(String name, int version) {
    final v = _box.get(_codeKey(name, version));
    return v is String ? v : null;
  }

  int? readVersion(String name) {
    final v = _box.get(_versionKey(name));
    return v is int ? v : null;
  }

  Future<void> writeCode({
    required String name,
    required int version,
    required String code,
  }) async {
    final previous = readVersion(name);
    if (previous != null && previous != version) {
      await _box.delete(_codeKey(name, previous));
    }
    await _box.put(_codeKey(name, version), code);
    await _box.put(_versionKey(name), version);
  }

  Future<void> clear(String name) async {
    final version = readVersion(name);
    if (version != null) await _box.delete(_codeKey(name, version));
    await _box.delete(_versionKey(name));
  }
}
