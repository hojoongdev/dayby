import 'dart:async';

import 'package:dayby/api/api_client.dart';
import 'package:dayby/live.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLiveFeed implements LiveFeed {
  final _controller = StreamController<Event>.broadcast();

  void partnerLogs(Event event) => _controller.add(event);

  @override
  LiveConnection connect(String familyId, {String? token}) => LiveConnection(
        events: _controller.stream,
        close: _controller.close,
      );
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.events);

  /// What the server would return on the next fetch.
  List<Event> events;

  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')];

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    int limit = 100,
  }) async => events;
}

Event _event(String id, String type, String subtype) => Event(
      id: id,
      babyId: 'baby1',
      type: type,
      subtype: subtype,
      time: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
    );

void main() {
  testWidgets('what one parent logs shows up on the other phone',
      (tester) async {
    SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
    final prefs = await SharedPreferences.getInstance();
    final feed = _FakeLiveFeed();
    final api = _FakeApiClient([_event('e1', 'feeding', 'formula')]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(api),
          liveFeedProvider.overrideWithValue(feed),
        ],
        child: const DaybyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Records'));
    await tester.pumpAndSettle();
    expect(find.text('Diaper · wet'), findsNothing);

    // The other parent logs a diaper change: the server writes it, the change
    // stream carries it here.
    final theirs = _event('e2', 'diaper', 'wet');
    api.events = [theirs, ...api.events];
    feed.partnerLogs(theirs);
    await tester.pumpAndSettle();

    expect(find.text('Diaper · wet'), findsOneWidget);
    expect(find.text('Feeding · formula'), findsOneWidget);
  });
}
