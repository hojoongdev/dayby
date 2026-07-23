import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth.dart';
import '../config.dart';
import '../models/event.dart';
import '../models/family.dart';
import '../models/insights.dart';
import '../models/routine.dart';
import '../models/stats.dart';
import '../models/tip.dart';
import '../models/wrapped.dart';

class ApiClient {
  ApiClient({
    String baseUrl = kApiBaseUrl,
    String? familyId,
    String? caregiverId,
    AuthTokens? tokens,
    this.onTokensRefreshed,
  }) : _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    _tokens = tokens;
    setFamilyId(familyId);
    setCaregiverId(caregiverId);
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

  /// Which caregiver this device is, so records get stamped with an author even when
  /// nobody signs in.
  void setCaregiverId(String? caregiverId) {
    if (caregiverId == null || caregiverId.isEmpty) {
      _dio.options.headers.remove('X-Caregiver-Id');
    } else {
      _dio.options.headers['X-Caregiver-Id'] = caregiverId;
    }
  }

  Future<Caregiver> addCaregiver(String name) async {
    final res = await _dio.post('/families/caregivers', data: {'name': name});
    return Caregiver.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Caregiver>> caregivers() async {
    final res = await _dio.get('/families/caregivers');
    return (res.data as List)
        .map((c) => Caregiver.fromJson(c as Map<String, dynamic>))
        .toList();
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

  /// Password provider: sign in to an existing local account.
  Future<Session> signInWithPassword(String email, String password) async {
    final res = await _dio.post(
      '/auth/signin',
      data: {'email': email, 'password': password},
    );
    return Session.fromJson(res.data as Map<String, dynamic>);
  }

  /// Password provider: make a new local account and get a session for it.
  Future<Session> signUp(String email, String password, {String? name}) async {
    final res = await _dio.post(
      '/auth/signup',
      data: {'email': email, 'password': password, 'name': ?name},
    );
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

  Future<List<Message>> messages() async {
    final res = await _dio.get('/messages');
    return (res.data as List)
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendMessage(String text) =>
      _dio.post('/messages', data: {'text': text});

  Future<void> markMessagesRead() => _dio.post('/messages/read');

  Future<List<Routine>> listRoutines() async {
    final res = await _dio.get('/routines');
    return (res.data as List)
        .map((r) => Routine.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Routine> createRoutine({
    required RoutineKind kind,
    required String message,
    String? triggerType,
    int? delayMin,
    String? timeLocal,
    String? babyId,
  }) async {
    final res = await _dio.post('/routines', data: {
      'kind': kindToWire(kind),
      'message': message,
      'trigger_type': ?triggerType,
      'delay_min': ?delayMin,
      'time_local': ?timeLocal,
      'baby_id': ?babyId,
    });
    return Routine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Routine> setRoutineActive(String id, bool active) async {
    final res = await _dio.patch('/routines/$id', data: {'active': active});
    return Routine.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteRoutine(String id) => _dio.delete('/routines/$id');

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

  /// The other parent, by name. Each record carries the id of whoever logged it; this
  /// is the only thing that turns one into a person.
  Future<List<AuthUser>> familyMembers() async {
    final res = await _dio.get('/families/members');
    return (res.data as List)
        .map((e) => AuthUser.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// `history` is the chat so far, which is what "actually 200" and "and yesterday?"
  /// resolve against. `languages` is what this caregiver speaks: the server works out
  /// which of those was used, and is not allowed to reach for any other.
  Future<StructuredResult> ingestText(
    String text, {
    List<Turn> history = const [],
    List<String> languages = const [],
  }) async {
    final res = await _dio.post('/ingest/text', data: {
      'text': text,
      'now': _localNowIso(),
      'history': [for (final turn in history) turn.toJson()],
      'languages': languages,
    });
    return StructuredResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// The recording itself. The server transcribes it and structures the result, so the
  /// app never has to be told which language to listen for.
  Future<IngestVoiceResult> ingestVoice({
    required Uint8List bytes,
    required String mimeType,
    List<Turn> history = const [],
    List<String> languages = const [],
  }) async {
    final form = FormData.fromMap({
      'now': _localNowIso(),
      'history': jsonEncode([for (final turn in history) turn.toJson()]),
      'languages': languages.join(','),
      'file': MultipartFile.fromBytes(
        bytes,
        filename: 'speech.wav',
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    final res = await _dio.post('/ingest/voice', data: form);
    return IngestVoiceResult.fromJson(res.data as Map<String, dynamic>);
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

  /// Correct a record. Whatever is left null stays as it was, and `fields` merges,
  /// so fixing the amount does not erase the rest of what was said.
  Future<Event> updateEvent(
    String id, {
    String? type,
    String? subtype,
    Map<String, dynamic>? fields,
    DateTime? time,
    String? note,
  }) async {
    final res = await _dio.patch('/events/$id', data: {
      'type': ?type,
      'subtype': ?subtype,
      'fields': ?fields,
      'time': ?time?.toUtc().toIso8601String(),
      'note': ?note,
    });
    return Event.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteEvent(String id) => _dio.delete('/events/$id');

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
    List<Turn> history = const [],
    List<String> languages = const [],
  }) async {
    final form = FormData.fromMap({
      'baby_id': babyId,
      'text': text,
      'now': _localNowIso(),
      'languages': languages.join(','),
      // Multipart fields are scalars, so the history goes as a JSON string.
      'history': jsonEncode([for (final turn in history) turn.toJson()]),
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

  /// The numbers behind the charts. `now` carries this phone's offset, which is what
  /// makes a "day" on the chart mean the day they actually had.
  Future<Stats> stats({required String babyId, int days = 14}) async {
    final res = await _dio.get('/stats', queryParameters: {
      'baby_id': babyId,
      'days': days,
      'now': _localNowIso(),
    });
    return Stats.fromJson(res.data as Map<String, dynamic>);
  }

  /// Looking forward and back: the next few things due, and the week's trends.
  Future<Insights> insights({required String babyId, String? lang}) async {
    final res = await _dio.get('/insights', queryParameters: {
      'baby_id': babyId,
      'lang': ?lang,
      'now': _localNowIso(),
    });
    return Insights.fromJson(res.data as Map<String, dynamic>);
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
