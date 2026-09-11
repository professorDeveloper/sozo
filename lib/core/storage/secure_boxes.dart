import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Opens the Hive boxes that hold secrets encrypted at rest.
///
/// `auth_box` carries the Sozo session and the AniList / MyAnimeList tokens,
/// and the private list is the one thing the app lock exists to hide. Both
/// were plain files in the app's data directory, readable by anything that
/// can read that directory — a rooted phone, an unencrypted desktop backup, a
/// copied home folder. They are now AES-encrypted by Hive with a key that
/// lives in the platform keystore (Keychain, Android Keystore-backed
/// EncryptedSharedPreferences, Credential Manager, libsecret).
///
/// Existing installs are migrated once, crash-safely: the plain box is copied
/// into an encrypted side box before anything is deleted, and a marker in
/// secure storage records how far the move got, so an interrupted launch
/// resumes it instead of losing the data. Hive would otherwise treat a plain
/// box opened with a cipher as corrupt and truncate it.
///
/// If secure storage cannot be used at all, the boxes open unencrypted as
/// before — signing someone out, or emptying their private list, because a
/// keyring is unavailable would be worse than the status quo.
class SecureBoxes {
  SecureBoxes._();

  static const String _keyName = 'hive_box_key';
  static String _stateKey(String box) => 'hive_box_state_$box';
  static String _sideBox(String box) => '${box}_enc_migrating';

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    // The file-based login keychain, not the data-protection one.
    //
    // The plugin defaults macOS to the data-protection keychain, which only
    // answers an app carrying a `keychain-access-groups` entitlement — and that
    // entitlement requires signing with a development certificate. Without one,
    // every read and write came back -34018 ("A required entitlement isn't
    // present"), the cipher was null, and both token boxes opened in plain
    // text. The encryption existed and never once ran on macOS.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  /// The shared cipher, creating and storing its key on first use; null when
  /// secure storage is unusable.
  static Future<HiveAesCipher?> cipher({
    FlutterSecureStorage storage = _defaultStorage,
  }) async {
    try {
      final existing = await storage.read(key: _keyName);
      if (existing != null && existing.isNotEmpty) {
        return HiveAesCipher(base64Url.decode(existing));
      }
      final key = Hive.generateSecureKey();
      await storage.write(key: _keyName, value: base64UrlEncode(key));
      // Read back: a keyring that accepts writes and forgets them (seen with
      // some Linux setups) must not end up encrypting with a lost key.
      final check = await storage.read(key: _keyName);
      if (check != base64UrlEncode(key)) return null;
      return HiveAesCipher(key);
    } catch (e) {
      debugPrint('[SecureBoxes] secure storage unavailable, boxes stay plain: $e');
      return null;
    }
  }

  /// Opens [name] encrypted with [cipher], migrating a plain copy first.
  /// With a null [cipher], opens it plain.
  static Future<Box<dynamic>> open(
    String name,
    HiveAesCipher? cipher, {
    FlutterSecureStorage storage = _defaultStorage,
  }) async {
    if (cipher == null) return Hive.openBox(name);
    // Whether the file under [name] is still the untouched plain box, and so
    // safe to fall back to. Once the move has started it is not: Hive would
    // read an encrypted file opened without the cipher as corrupt and
    // truncate it.
    var plainIntact = false;
    try {
      var state = await storage.read(key: _stateKey(name));
      plainIntact = state == null;
      if (state == 'done') {
        if (await Hive.boxExists(_sideBox(name))) {
          await Hive.deleteBoxFromDisk(_sideBox(name));
        }
        return await Hive.openBox(name, encryptionCipher: cipher);
      }

      if (state == null) {
        // Plain box on disk (or none yet): copy it aside, encrypted.
        final plain = await Hive.openBox(name);
        final snapshot = Map<dynamic, dynamic>.from(plain.toMap());
        final side = await Hive.openBox(_sideBox(name), encryptionCipher: cipher);
        await side.clear();
        await side.putAll(snapshot);
        await side.flush();
        await side.close();
        await storage.write(key: _stateKey(name), value: 'copied');
        plainIntact = false;
        await plain.deleteFromDisk();
        state = 'copied';
      }

      // 'copied': the side box is the source of truth; whatever sits under
      // [name] is either the old plain box or a half-written new one.
      final side = await Hive.openBox(_sideBox(name), encryptionCipher: cipher);
      final snapshot = Map<dynamic, dynamic>.from(side.toMap());
      await side.close();
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      await Hive.deleteBoxFromDisk(name);
      final box = await Hive.openBox(name, encryptionCipher: cipher);
      await box.putAll(snapshot);
      await box.flush();
      await storage.write(key: _stateKey(name), value: 'done');
      await Hive.deleteBoxFromDisk(_sideBox(name));
      return box;
    } catch (e) {
      debugPrint('[SecureBoxes] $name: encrypted open failed: $e');
      if (plainIntact) {
        if (Hive.isBoxOpen(name)) return Hive.box(name);
        return Hive.openBox(name);
      }
      // Leave the file alone for the next launch to retry, and run this one
      // on an empty in-memory box rather than not at all.
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      return Hive.openBox(name, bytes: Uint8List(0));
    }
  }
}
