import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native (Android / iOS / Desktop) — token passed as Authorization header,
/// not in the URL, so it never appears in proxy or server access logs.
WebSocketChannel connectWithAuthHeader(Uri uri, String token) =>
    IOWebSocketChannel.connect(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
