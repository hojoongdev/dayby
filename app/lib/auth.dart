import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A signed-in session. The access token is short-lived; the refresh token is how
/// a parent stays signed in instead of being logged out at 3am.
class AuthTokens {
  const AuthTokens({required this.access, required this.refresh});

  final String access;
  final String refresh;
}

class AuthUser {
  const AuthUser({required this.id, this.email, this.name});

  final String id;
  final String? email;
  final String? name;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String?,
        name: json['name'] as String?,
      );
}

class Session {
  const Session({required this.tokens, required this.user, this.familyId});

  final AuthTokens tokens;
  final AuthUser user;

  /// Null until this user creates a family or joins one with an invite code.
  final String? familyId;

  Session withTokens(AuthTokens tokens) =>
      Session(tokens: tokens, user: user, familyId: familyId);

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        tokens: AuthTokens(
          access: json['access_token'] as String,
          refresh: json['refresh_token'] as String,
        ),
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        familyId: json['family_id'] as String?,
      );
}

/// Which sign-in the server expects, if any.
class AuthConfig {
  const AuthConfig({this.enabled = false, this.provider = 'none'});

  final bool enabled;
  final String provider;

  factory AuthConfig.fromJson(Map<String, dynamic> json) => AuthConfig(
        enabled: json['enabled'] as bool? ?? false,
        provider: json['provider'] as String? ?? 'none',
      );
}

/// Where the refresh token lives between launches. An interface because the
/// Keychain is platform code, and tests should not need one.
abstract class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

/// The Keychain on iOS, the Keystore on Android, WebCrypto on the web.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore([this._storage = const FlutterSecureStorage()]);

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    try {
      final access = await _storage.read(key: _accessKey);
      final refresh = await _storage.read(key: _refreshKey);
      if (access == null || refresh == null) return null;
      return AuthTokens(access: access, refresh: refresh);
    } catch (_) {
      // No keychain here (an unsupported browser, a test). Signed out is the
      // safe answer, and the worst it costs is one sign-in.
      return null;
    }
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.access);
    await _storage.write(key: _refreshKey, value: tokens.refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
