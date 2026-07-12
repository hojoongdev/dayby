import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// The face or the fingerprint standing between someone holding the phone and a
/// record of a child's every feed, illness and photograph.
abstract class AppLock {
  /// Whether this device can ask at all. There is no point offering the setting
  /// on a laptop with no sensor.
  Future<bool> isAvailable();

  Future<bool> unlock();
}

class BiometricAppLock implements AppLock {
  BiometricAppLock([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> unlock() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Dayby',
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      // No sensor, no enrolment, or a cancelled prompt: still locked.
      return false;
    }
  }
}
