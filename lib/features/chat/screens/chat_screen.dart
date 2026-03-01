import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/websocket_service.dart';

/// In-app chat between customer and delivery partner during an active order.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMsg>[];
  StreamSubscription<WsEvent>? _wsSub;

  /// Safely truncate an ID to at most [maxLen] characters.
  String _shortId(String id, [int maxLen = 8]) =>
      id.length <= maxLen ? id : id.substring(0, maxLen);

  @override
  void initState() {
    super.initState();
    _addSystemMsg('Chat started for order #${_shortId(widget.orderId)}');
    _listenWs();
  }

  void _listenWs() {
    final ws = ref.read(webSocketServiceProvider);
    _wsSub = ws.events.listen((e) {
      if (e.type == WsEventType.unknown && e.payload['chat_order_id'] == widget.orderId) {
        final text = e.payload['message'] as String? ?? '';
        final sender = e.payload['sender_role'] as String? ?? 'other';
        if (text.isNotEmpty) {
          setState(() {
            _messages.add(_ChatMsg(
              text: text,
              isMe: false,
              senderLabel: sender == 'delivery_partner' ? 'Rider' : 'Customer',
              timestamp: DateTime.now(),
            ));
          });
          _scrollToBottom();
        }
      }
    });
  }

  void _addSystemMsg(String text) {
    _messages.add(_ChatMsg(
      text: text,
      isMe: false,
      isSystem: true,
      senderLabel: 'System',
      timestamp: DateTime.now(),
    ));
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMsg(
        text: text,
        isMe: true,
        senderLabel: 'You',
        timestamp: DateTime.now(),
      ));
    });
    _controller.clear();

    // Send over WebSocket
    final ws = ref.read(webSocketServiceProvider);
    ws.send({
      'type': 'chat_message',
      'payload': {
        'order_id': widget.orderId,
        'message': text,
      },
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Order Chat'),
            Text(
              'Order #${_shortId(widget.orderId)}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Chat is available during active delivery. '
                    'Messages are not stored after delivery is completed.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── Messages ───
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: AppColors.textTertiary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'No messages yet',
                          style: AppTypography.body2.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Send a message to your rider',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      return _MessageBubble(msg: msg, index: i);
                    },
                  ),
          ),

          // ─── Quick replies ───
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 6,
            ),
            child: Row(
              children: _quickReplies.map((reply) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(reply, style: const TextStyle(fontSize: 12)),
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.08),
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    onPressed: () {
                      _controller.text = reply;
                      _sendMessage();
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // ─── Input ───
          Container(
            padding: EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.sm,
              top: AppSpacing.sm,
              bottom: MediaQuery.of(context).padding.bottom + AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(
                  color: AppColors.divider.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    style: AppTypography.body2,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusLg),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, size: 20),
                    color: Colors.white,
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _quickReplies = [
    'On my way!',
    'I\'m at the entrance',
    'Please call me',
    'Running late, sorry!',
    'Can\'t find the location',
    'Thank you!',
  ];
}

// ─── Models & Widgets ─────────────────────────────────────────────

class _ChatMsg {
  final String text;
  final bool isMe;
  final bool isSystem;
  final String senderLabel;
  final DateTime timestamp;

  const _ChatMsg({
    required this.text,
    required this.isMe,
    this.isSystem = false,
    required this.senderLabel,
    required this.timestamp,
  });
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, required this.index});
  final _ChatMsg msg;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (msg.isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Text(
              msg.text,
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
        ),
      );
    }

    final timeStr =
        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isMe
              ? AppColors.primary
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
            bottomRight: Radius.circular(msg.isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!msg.isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  msg.senderLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              msg.text,
              style: AppTypography.body2.copyWith(
                color: msg.isMe ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: msg.isMe
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 40).ms).fadeIn().slideY(begin: 0.05);
  }
}
