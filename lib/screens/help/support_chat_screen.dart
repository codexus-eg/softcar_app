import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../services/support_service.dart';
import '../../widgets/common_widgets.dart';

/// Live support chat backed by the real support-chat API.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final support = context.read<SupportService>();
      if (support.sessions.isEmpty) support.syncChat();
    });
    // Poll for new replies / queue movement on the live chat session.
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      final support = context.read<SupportService>();
      if (support.activeSession != null) support.syncChat();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _startChat() async {
    final support = context.read<SupportService>();
    setState(() => _sending = true);
    await support.startChat(
      subject: support.activeSession?.subject.isEmpty == true
          ? ''
          : L10n.t(context, 'customerService'),
      message: L10n.t(context, 'newChatSub'),
    );
    _scrollToBottom();
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final support = context.read<SupportService>();
    final session = support.activeSession;
    if (session == null) return;
    setState(() => _sending = true);
    _controller.clear();
    final ok = await support.sendMessage(session.id, text);
    _scrollToBottom();
    if (mounted) {
      setState(() => _sending = false);
      if (!ok) _snack(L10n.t(context, 'sendFailed'));
    }
  }

  Future<void> _close() async {
    final support = context.read<SupportService>();
    final session = support.activeSession;
    if (session == null) return;
    await support.closeChat(session.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'chat'))),
      body: Consumer<SupportService>(
        builder: (context, support, _) {
          final session = support.activeSession;
          if (support.loading && support.sessions.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          if (session == null) {
            return _EmptyChat(
              onStart: _startChat,
              sending: _sending,
            );
          }
          return Column(
            children: [
              _SessionBanner(session: session, queue: support.queuePosition),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: session.messages.length,
                  itemBuilder: (context, i) =>
                      _Bubble(message: session.messages[i]),
                ),
              ),
              if (session.isClosed)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    L10n.t(context, 'chatClosed'),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                )
              else
                _Composer(
                  controller: _controller,
                  sending: _sending,
                  onSend: _send,
                  onClose: _close,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionBanner extends StatelessWidget {
  final ChatSession session;
  final int? queue;
  const _SessionBanner({required this.session, this.queue});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = session.isClosed
        ? L10n.t(context, 'chatClosed')
        : queue != null && queue! > 0
            ? L10n.t(context, 'queuePosition').replaceFirst('{n}', '$queue')
            : L10n.t(context, 'waiting');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDarkElevated : AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            session.isClosed
                ? Icons.lock_outline_rounded
                : Icons.support_agent_rounded,
            size: 18,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.assignedToName != null && !session.isClosed
                  ? '${session.assignedToName} — $text'
                  : text,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.senderRole == 'USER' || message.senderRole == 'PASSENGER';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isUser ? AppColors.accent : AppColors.surfaceDarkElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.message,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: isUser ? Colors.white : AppColors.textOnDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.senderName.isEmpty
                  ? _time(message.createdAt)
                  : '${message.senderName} · ${_time(message.createdAt)}',
              style: TextStyle(
                fontSize: 10,
                color: isUser
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onClose;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: L10n.t(context, 'typeMessage'),
                  isDense: true,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: sending ? null : onSend,
              icon: const Icon(Icons.send_rounded, color: AppColors.accent),
              tooltip: L10n.t(context, 'send'),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded,
                  color: AppColors.textSecondary),
              tooltip: L10n.t(context, 'close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final VoidCallback onStart;
  final bool sending;
  const _EmptyChat({required this.onStart, required this.sending});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.chat_bubble_outline_rounded,
            size: 64, color: AppColors.textTertiary),
        const SizedBox(height: 16),
        Center(
          child: Text(L10n.t(context, 'newChat'),
              style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            L10n.t(context, 'newChatSub'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(height: 28),
        SoftCard(
          accent: true,
          onTap: sending ? null : onStart,
          child: Center(
            child: sending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent))
                : Text(
                    L10n.t(context, 'startChat'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
          ),
        ),
      ],
    );
  }
}