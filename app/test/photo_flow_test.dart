import 'dart:convert';
import 'dart:typed_data';

import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _photoId = 'photo-1';

/// A 1x1 PNG: the chat renders what was attached, so the bytes have to decode.
final _bytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
);

class _FakePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      XFile.fromData(_bytes, name: 'rash.png', mimeType: 'image/png');
}

class _FakeApiClient extends ApiClient {
  String? sentText;
  String? sentMime;
  Map<String, dynamic>? savedFields;

  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')];

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    int limit = 100,
  }) async => const [];

  @override
  Future<IngestPhotoResult> ingestPhoto({
    required String babyId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String text = '',
    List<Turn> history = const [],
    List<String> languages = const [],
  }) async {
    sentText = text;
    sentMime = mimeType;
    return const IngestPhotoResult(
      photoId: _photoId,
      result: StructuredResult(
        reply: 'I can see small red spots. A pediatrician should look at it.',
        events: [
          // The server stitches the photo id into whatever the model hands back.
          StructuredEvent(
            type: 'rash',
            fields: {'photo_id': _photoId},
            note: 'red spots on the cheek',
          ),
        ],
      ),
    );
  }

  @override
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
    savedFields = fields;
    return Event(
      id: 'e1',
      babyId: babyId,
      type: type,
      fields: fields,
      time: DateTime.now(),
      createdAt: DateTime.now(),
    );
  }
}

void main() {
  testWidgets('a photo goes out with the message and stays with the event',
      (tester) async {
    SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
    final prefs = await SharedPreferences.getInstance();
    final fake = _FakeApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(fake),
          imagePickerProvider.overrideWithValue(_FakePicker()),
        ],
        child: const DaybyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_a_photo_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from library'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'look at this rash');
    // The send button only exists once there is something typed to send.
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(fake.sentText, 'look at this rash');
    expect(fake.sentMime, 'image/png');
    expect(
      find.text('I can see small red spots. A pediatrician should look at it.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.savedFields?['photo_id'], _photoId);
  });
}
