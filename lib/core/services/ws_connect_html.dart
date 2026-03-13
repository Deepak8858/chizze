import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Web (browser) — browser WebSocket API does not support custom headers.
/// Real-time authenticated features are not supported on the web platform.
WebSocketChannel connectWithAuthHeader(Uri uri, String token) =>
    HtmlWebSocketChannel.connect(uri);
