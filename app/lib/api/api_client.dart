import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth.dart';
import '../config.dart';
import '../models/event.dart';
import '../models/family.dart';
import '../models/tip.dart';
import '../models/wrapped.dart';

class ApiClient {
  ApiClient({
    String baseUrl = kApiBaseUrl,
    String? familyId,
    AuthTokens? tokens,
    this.onTokensRefreshed,
  }) : _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    _tokens = tokens;
    setFamilyId(familyId);
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _authorize, onError: _refreshAndRetry),
    );
  }

  final Dio _dio;
  AuthTokens? _tokens;

  /// Called when a 401 was recovered by refreshing, so the new pair gets persisted.
  final void Function(AuthTokens)? onTokensRefreshed;

  void setFamilyId(String? familyId) {
    if (familyId == null || familyId.isEmpty) {
      _dio.options.headers.remove('X-Family-Id');
    } else {
      _dio.options.headers['X-Family-Id'] = familyId;
    }
  }

  void _authorize(RequestOptions options, RequestInterceptorHandler handler) {
    final tokens = _tokens;
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.access}';
    }
    handler.next(options);
  }

  /// An access token lives half an hour, and a parent's session lives months. When
  /// the short one lapses mid-request, renew it and let the request go through
  /// rather than throwing the caregiver back to a sign-in screen.
  Future<void> _refreshAndRetry(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final tokens = _tokens;
    final failed = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        tokens == null ||
        failed.extra.containsKey('retried')) {
      return handler.next(error);
    }

    try {
      final renewed = await refreshSession(tokens.refresh);
      _tokens = renewed.tokens;
      onTokensRefreshed?.call(renewed.tokens);

      failed.extra['retried'] = true;
      failed.headers['Authorization'] = 'Bearer ${renewed.tokens.access}';
      handler.resolve(await _dio.fetch<dynamic>(failed));
    } on DioException {
      // The refresh token is gone too: this really is a sign-in.
      handler.next(error);
    }
  }

  Future<AuthConfig> authConfig() async {
    final res = await _dio.get('/auth/config');
    return AuthConfig.fromJson(res.data as Map<String, dynamic>);
  }

  /// Trade an identity provider's token for a Dayby session. With the mock
  /// provider, the "token" is simply the email you claim to be.
  Future<Session> signIn(String providerToken) async {
    final res = await _dio.post('/auth/signin', data: {'token': providerToken});
    return Session.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Session> refreshSession(String refreshToken) async {
    final res = await _dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
    return Session.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Family> createFamily(String name) async {
    final res = await _dio.post('/families', data: {'name': name});
    return Family.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Family> joinFamily(String inviteCode) async {
    final res = await _dio.post('/families/join', data: {'invite_code': inviteCode});
    return Family.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Baby> addBaby({
    required String name,
    List<String> nicknames = const [],
    DateTime? birthdate,
    String? sex,
  }) async {
    final res = await _dio.post('/babies', data: {
      'name': name,
      'nicknames': nicknames,
      'birthdate': ?_dateOnly(birthdate),
      'sex': ?sex,
    });
    return Baby.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Baby>> listBabies() async {
    final res = await _dio.get('/babies');
    return (res.data as List)
        .map((e) => Baby.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Baby> updateBaby(
    String id, {
    String? name,
    List<String>? nicknames,
    DateTime? birthdate,
    String? sex,
  }) async {
    final res = await _dio.patch('/babies/$id', data: {
      'name': ?name,
      'nicknames': ?nicknames,
      'birthdate': ?_dateOnly(birthdate),
      'sex': ?sex,
    });
    return Baby.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StructuredResult> ingestText(String text, {String? lang}) async {
    final res = await _dio.post('/ingest/text',
        data: {'text': text, 'lang': ?lang, 'now': _localNowIso()});
    return StructuredResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Event> createEvent({
    required String babyId,
    required String type,
    String? subtype,
    Map<String, dynamic> fields = const {},
    DateTime? time,
    String? note,
    String source = 'text',
    String? rawText,
  }) async {
    final res = await _dio.post('/events', data: {
      'baby_id': babyId,
      'type': type,
      'subtype': ?subtype,
      'fields': fields,
      'time': ?time?.toUtc().toIso8601String(),
      'note': ?note,
      'source': source,
      'raw_text': ?rawText,
    });
    return Event.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    int limit = 100,
  }) async {
    final res = await _dio.get('/events', queryParameters: {
      'baby_id': ?babyId,
      'type': ?type,
      'limit': limit,
    });
    return (res.data as List)
        .map((e) => Event.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// A photo, with or without words. The server stores it and the model reads it;
  /// what comes back is the same confirm-and-save shape as a typed sentence.
  Future<IngestPhotoResult> ingestPhoto({
    required String babyId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String text = '',
    String? lang,
  }) async {
    final form = FormData.fromMap({
      'baby_id': babyId,
      'text': text,
      'lang': ?lang,
      'now': _localNowIso(),
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    final res = await _dio.post('/ingest/photo', data: form);
    return IngestPhotoResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Uint8List> photoBytes(String photoId) async {
    final res = await _dio.get<List<int>>(
      '/photos/$photoId',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data!);
  }

  /// What the assistant would say right now, unprompted.
  Future<AssistantTips> tips({required String babyId, String? lang}) async {
    final res = await _dio.get('/assistant/tips', queryParameters: {
      'baby_id': babyId,
      'lang': ?lang,
      'now': _localNowIso(),
    });
    return AssistantTips.fromJson(res.data as Map<String, dynamic>);
  }

  /// The keepsake: everything ever logged for this baby, counted and told back.
  Future<Wrapped> wrapped({required String babyId, String? lang}) async {
    final res = await _dio.get('/wrapped', queryParameters: {
      'baby_id': babyId,
      'lang': ?lang,
      'now': _localNowIso(),
    });
    return Wrapped.fromJson(res.data as Map<String, dynamic>);
  }

  String? _dateOnly(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The device's current local time as an offset-aware ISO 8601 string, so the
  /// server resolves relative and clock times ("last night", "8am") in the
  /// user's timezone. What gets stored is still UTC.
  String _localNowIso() {
    final now = DateTime.now();
    final off = now.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final abs = off.abs();
    final hh = abs.inHours.toString().padLeft(2, '0');
    final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return '${now.toIso8601String()}$sign$hh:$mm';
  }
}

/// Turn any request failure into a short, human message for the UI.
String friendlyError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Cannot reach the server. Check your connection and try again.';
      case DioExceptionType.badResponse:
        return 'The server had a problem (${e.response?.statusCode}). Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}
