const String kApiBaseUrl =
    String.fromEnvironment('DAYBY_API', defaultValue: 'http://localhost:8000');

/// The same server, over a WebSocket: http -> ws, https -> wss.
String get kWsBaseUrl => kApiBaseUrl.replaceFirst(RegExp('^http'), 'ws');
