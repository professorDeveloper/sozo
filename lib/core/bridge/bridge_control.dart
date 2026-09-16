import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class BridgeControl {
  BridgeControl._();

  static const MethodChannel _ch = MethodChannel('soplay/bridge');

  static bool get canHost => Platform.isAndroid;

  static Future<BridgeStatus> getStatus() async {
    if (!canHost) return const BridgeStatus(enabled: false, link: null);
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getStatus');
      return BridgeStatus.fromMap(m);
    } catch (_) {
      return const BridgeStatus(enabled: false, link: null);
    }
  }

  static Future<BridgeStatus> setEnabled(bool enabled) async {
    if (!canHost) return const BridgeStatus(enabled: false, link: null);
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('setEnabled', {
        'enabled': enabled,
      });
      return BridgeStatus.fromMap(m);
    } catch (_) {
      return const BridgeStatus(enabled: false, link: null);
    }
  }

  static Future<SharedSelection> getSharedProviders() async {
    if (!canHost) return const SharedSelection(shareAll: true, ids: {});
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>(
        'getSharedProviders',
      );
      return SharedSelection.fromMap(m);
    } catch (_) {
      return const SharedSelection(shareAll: true, ids: {});
    }
  }

  static Future<SharedSelection> setSharedProviders({
    required bool shareAll,
    required Set<String> ids,
  }) async {
    if (!canHost) return const SharedSelection(shareAll: true, ids: {});
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>(
        'setSharedProviders',
        {'shareAll': shareAll, 'ids': ids.toList()},
      );
      return SharedSelection.fromMap(m);
    } catch (_) {
      return SharedSelection(shareAll: shareAll, ids: ids);
    }
  }
}

class SharedSelection {
  const SharedSelection({required this.shareAll, required this.ids});

  final bool shareAll;
  final Set<String> ids;

  factory SharedSelection.fromMap(Map<String, dynamic>? m) => SharedSelection(
    shareAll: m?['shareAll'] != false,
    ids: ((m?['ids'] as List?) ?? const []).map((e) => e.toString()).toSet(),
  );
}

class BridgeStatus {
  const BridgeStatus({required this.enabled, required this.link});

  final bool enabled;

  final String? link;

  factory BridgeStatus.fromMap(Map<String, dynamic>? m) =>
      BridgeStatus(enabled: m?['enabled'] == true, link: m?['link'] as String?);
}
