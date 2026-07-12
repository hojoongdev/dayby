import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'models/event.dart';

/// An open line to the family's feed.
class LiveConnection {
  const LiveConnection({required this.events, required this.close});

  final Stream<Event> events;
  final void Function() close;
}

/// Where live events come from. An interface so a test can push events through
/// the app without a socket.
abstract class LiveFeed {
  LiveConnection connect(String familyId, {String? token});
}

/// The real thing: a WebSocket the server feeds from a MongoDB change stream.
class WebSocketLiveFeed implements LiveFeed {
  const WebSocketLiveFeed();

  @override
  LiveConnection connect(String familyId, {String? token}) {
    // The session travels in the query string because a browser cannot put headers
    // on a WebSocket.
    final channel = WebSocketChannel.connect(
      Uri.parse('$kWsBaseUrl/ws/events').replace(queryParameters: {
        'family_id': familyId,
        'token': ?token,
      }),
    );
    return LiveConnection(
      events: channel.stream
          .map((raw) => jsonDecode(raw as String) as Map<String, dynamic>)
          .where((message) => message['type'] == 'event')
          .map((message) =>
              Event.fromJson(message['event'] as Map<String, dynamic>)),
      close: channel.sink.close,
    );
  }
}
