import 'package:google_sign_in/google_sign_in.dart';

import 'config.dart';

/// Where the app gets a Google ID token to hand the server, which then verifies it
/// against Google's own keys. The app never sees anything it could forge.
abstract class GoogleIdentity {
  /// Whether this build can even offer it: a client id compiled in, on a platform
  /// whose sign-in flow this package drives. (On the web it does not — that needs a
  /// rendered Google button, and the web build is the one that signs in with the
  /// mock provider anyway.)
  bool get isAvailable;

  /// The ID token Google issued, or null if the caregiver backed out.
  Future<String?> idToken();
}

class RealGoogleIdentity implements GoogleIdentity {
  bool _initialized = false;

  @override
  bool get isAvailable =>
      kGoogleClientId.isNotEmpty && GoogleSignIn.instance.supportsAuthenticate();

  @override
  Future<String?> idToken() async {
    if (!_initialized) {
      await GoogleSignIn.instance.initialize(clientId: kGoogleClientId);
      _initialized = true;
    }

    try {
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      // Backing out of the Google sheet is not a failure worth a red banner.
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}
