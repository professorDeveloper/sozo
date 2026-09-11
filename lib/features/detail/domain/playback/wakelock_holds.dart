import 'package:wakelock_plus/wakelock_plus.dart';

/// Who is keeping the screen awake.
///
/// The player, the reader and the in-process downloader each want the screen
/// on, and each used to switch WakelockPlus on and off by itself — so whichever
/// finished first switched it off for the rest. A download completing in the
/// middle of an episode let the phone doze under the video; closing the player
/// let a desktop machine sleep in the middle of a download.
///
/// One set of holders instead: the lock goes on with the first and off with
/// the last, and nobody can release a hold they did not take.
class WakelockHolds {
  WakelockHolds._();

  static final Set<Object> _holders = <Object>{};

  static bool get isHeld => _holders.isNotEmpty;

  static Future<void> acquire(Object holder) async {
    final wasEmpty = _holders.isEmpty;
    if (!_holders.add(holder) || !wasEmpty) return;
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  static Future<void> release(Object holder) async {
    if (!_holders.remove(holder) || _holders.isNotEmpty) return;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
