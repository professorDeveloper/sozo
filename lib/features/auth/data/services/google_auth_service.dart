import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:soplay/core/error/result.dart';

/// Google sign-in, exchanged for a Firebase ID token the backend can verify.
///
/// The backend already carries firebase-admin, so it verifies one kind of token
/// no matter which provider issued it — adding Apple or Facebook later stops at
/// this file rather than reaching the API.
class GoogleAuthService {
  GoogleAuthService({GoogleSignIn? googleSignIn, FirebaseAuth? firebaseAuth})
    : _injectedGoogleSignIn = googleSignIn,
      _injectedFirebaseAuth = firebaseAuth;

  final GoogleSignIn? _injectedGoogleSignIn;
  final FirebaseAuth? _injectedFirebaseAuth;

  // Resolved on first use, not in the constructor: DI is built before
  // Firebase.initializeApp() runs, and FirebaseAuth.instance throws until it has.
  GoogleSignIn get _googleSignIn =>
      _injectedGoogleSignIn ?? GoogleSignIn.instance;
  FirebaseAuth get _firebaseAuth =>
      _injectedFirebaseAuth ?? FirebaseAuth.instance;

  bool _initialized = false;

  /// The OAuth client an Apple build needs, when one is configured.
  ///
  /// Android finds it in google-services.json, which the Gradle plugin wires
  /// up. There is no equivalent here: this repo ships no GoogleService-Info
  /// .plist under ios/ or macos/ and no GIDClientID in either Info.plist, so
  /// nothing tells the plugin which client to use and `authenticate` throws the
  /// moment the button is tapped.
  static String? get _appleClientId => _env('GOOGLE_IOS_CLIENT_ID');

  /// dotenv before `load` throws rather than answering null.
  static String? _env(String key) {
    try {
      final value = dotenv.maybeGet(key);
      return value != null && value.isNotEmpty ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Whether to offer the button at all.
  ///
  /// The desktop and TV builds share these screens and have no Google plugin
  /// behind them, so the button has to disappear there rather than throw when
  /// tapped. Apple builds are the same case once you look: the button was shown
  /// and the flow could not complete, which is worse than no button — it reads
  /// as the account being broken rather than as the method not being offered.
  /// Configure GOOGLE_IOS_CLIENT_ID (or add the plist) and it appears.
  static bool get isSupported {
    if (Platform.isAndroid) return true;
    if (Platform.isIOS || Platform.isMacOS) return _appleClientId != null;
    return false;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    // Android reads the web client from google-services.json; the env override
    // is for builds that ship without it.
    await _googleSignIn.initialize(
      clientId: Platform.isAndroid ? null : _appleClientId,
      serverClientId: _env('GOOGLE_SERVER_CLIENT_ID'),
    );
    _initialized = true;
  }

  /// Runs the Google flow and returns a Firebase ID token.
  ///
  /// `Success(null)` means the user backed out — that is an ordinary outcome,
  /// not an error, and the caller must not show it as one.
  Future<Result<String?>> signIn() async {
    if (!isSupported) {
      return Failure(Exception('auth.google_unavailable'.tr()));
    }
    try {
      await _ensureInitialized();
      if (!_googleSignIn.supportsAuthenticate()) {
        return Failure(Exception('auth.google_unavailable'.tr()));
      }

      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        return Failure(Exception('auth.google_failed'.tr()));
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _firebaseAuth.signInWithCredential(credential);
      final firebaseToken = await result.user?.getIdToken();
      if (firebaseToken == null || firebaseToken.isEmpty) {
        return Failure(Exception('auth.google_failed'.tr()));
      }
      return Success(firebaseToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return const Success(null);
      }
      // Google's own text names SDK error codes, so it goes to the log and the
      // user gets the translated line instead.
      debugPrint('google sign-in failed: $e');
      return Failure(Exception('auth.google_failed'.tr()));
    } on FirebaseAuthException catch (e) {
      debugPrint('firebase sign-in failed: $e');
      return Failure(Exception('auth.google_failed'.tr()));
    } catch (e) {
      debugPrint('google sign-in failed: $e');
      return Failure(Exception('auth.google_failed'.tr()));
    }
  }

  /// Clears the Google and Firebase sessions so the next sign-in asks which
  /// account to use. Without it, signing out of Sozo silently signs the same
  /// person straight back in.
  Future<void> signOut() async {
    if (!isSupported) return;
    try {
      if (_initialized) await _googleSignIn.signOut();
      await _firebaseAuth.signOut();
    } catch (_) {
      // Sozo's own session is already gone by this point; a failure to tidy up
      // Google's must not turn logout into an error.
    }
  }
}
