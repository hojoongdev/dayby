import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingApiClient extends ApiClient {
  _FailingApiClient(this.babies);

  final List<Baby> babies;

  @override
  Future<List<Baby>> listBabies() async => babies;

  @override
  Future<List<Event>> listEvents({String? babyId, String? type, int limit = 100}) async =>
      const [];

  @override
  Future<StructuredResult> ingestText(
    String text, {
    List<Turn> history = const [],
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/ingest/text'),
      type: DioExceptionType.connectionError,
    );
  }
}

void main() {
  testWidgets('a network failure shows an error bubble and keeps the message',
      (tester) async {
    SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
    final prefs = await SharedPreferences.getInstance();
    final fake = _FailingApiClient(
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(fake),
        ],
        child: const DaybyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log')); // switch from Home to the Log tab
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'fed 120 ml');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    expect(find.text('fed 120 ml'), findsOneWidget); // message not lost
  });
}
