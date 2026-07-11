import 'package:dio/dio.dart';

import '../config.dart';
import '../models/event.dart';
import '../models/family.dart';

class ApiClient {
  ApiClient({String baseUrl = kApiBaseUrl, String? familyId})
      : _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    setFamilyId(familyId);
  }

  final Dio _dio;

  void setFamilyId(String? familyId) {
    if (familyId == null || familyId.isEmpty) {
      _dio.options.headers.remove('X-Family-Id');
    } else {
      _dio.options.headers['X-Family-Id'] = familyId;
    }
  }

  Future<Family> createFamily(String name) async {
    final res = await _dio.post('/families', data: {'name': name});
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
