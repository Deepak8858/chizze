import 'package:web_socket_channel/web_socket_channel.dart';

/// Fallback stub — no header support (should not be reached on supported platforms)
WebSocketChannel connectWithAuthHeader(Uri uri, String token) =>
    WebSocketChannel.connect(uri);
