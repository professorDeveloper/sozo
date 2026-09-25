import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/notifications/data/notification_prefs.dart';

void main() {
  group('quiet hours', () {
    DateTime at(int h, int m) => DateTime(2026, 9, 24, h, m);

    test('off means never quiet', () {
      expect(const QuietHours().contains(at(2, 0)), isFalse);
    });

    test('a window across midnight', () {
      const q = QuietHours(enabled: true, from: 23 * 60, to: 7 * 60);
      expect(q.contains(at(23, 0)), isTrue);
      expect(q.contains(at(2, 30)), isTrue);
      expect(q.contains(at(6, 59)), isTrue);
      expect(q.contains(at(7, 0)), isFalse);
      expect(q.contains(at(12, 0)), isFalse);
      expect(q.contains(at(22, 59)), isFalse);
    });

    test('a window inside one day', () {
      const q = QuietHours(enabled: true, from: 13 * 60, to: 14 * 60);
      expect(q.contains(at(13, 30)), isTrue);
      expect(q.contains(at(14, 0)), isFalse);
      expect(q.contains(at(12, 59)), isFalse);
    });

    test('equal ends mean all day', () {
      const q = QuietHours(enabled: true, from: 600, to: 600);
      expect(q.contains(at(3, 0)), isTrue);
    });
  });

  group('per-type switches gate by push type', () {
    test('a switched-off type is not shown', () {
      final p = const NotificationPrefs().withCategory(
        NotificationCategory.releases,
        false,
      );
      expect(p.allows('new_release'), isFalse);
      expect(p.allows('library_update'), isFalse);
      expect(p.allows('friend_request'), isTrue);
    });

    test('the master switch silences everything, uncategorised too', () {
      const p = NotificationPrefs(master: false);
      expect(p.allows('system_ban'), isFalse);
      expect(p.allows('new_release'), isFalse);
    });

    test('an unknown type answers only to the master switch', () {
      final p = const NotificationPrefs().withCategory(
        NotificationCategory.announcements,
        false,
      );
      expect(p.allows('system_ban'), isTrue);
      expect(p.allows('admin_broadcast'), isFalse);
    });

    test('round-trips', () {
      final p = const NotificationPrefs(
        quiet: QuietHours(enabled: true, from: 60, to: 120),
      ).withCategory(NotificationCategory.streak, false);
      final back = NotificationPrefs.fromJson(p.toJson());
      expect(back.isOn(NotificationCategory.streak), isFalse);
      expect(back.quiet.enabled, isTrue);
      expect(back.quiet.to, 120);
    });
  });
}
