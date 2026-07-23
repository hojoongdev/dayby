/// The default backend the app talks to. A build can bake one in with
/// --dart-define=DAYBY_API=…, but it is only a default now: the address is editable
/// at runtime (Settings → Server), so anyone can point the app at their own server.
const String kApiBaseUrl =
    String.fromEnvironment('DAYBY_API', defaultValue: 'http://localhost:8000');

/// The same server over a WebSocket: http -> ws, https -> wss.
String wsFromHttp(String httpUrl) => httpUrl.replaceFirst(RegExp('^http'), 'ws');

String get kWsBaseUrl => wsFromHttp(kApiBaseUrl);

/// The OAuth client the app signs in with. It has to be the same client the server
/// verifies tokens against (GOOGLE_CLIENT_ID), which is why it is not guessed:
///
///   flutter run --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
///
/// A client id is public by design, but it is nobody's business but the owner's
/// which one this app is, so it is not committed either.
const String kGoogleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
