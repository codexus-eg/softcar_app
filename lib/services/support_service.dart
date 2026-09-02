import 'package:flutter/foundation.dart';

import 'passenger_api.dart';

/// A chat session returned by `GET/POST /api/mobile/support-chat`.
class ChatSession {
  final String id;
  final String lane;
  final String status;
  final String subject;
  final String? assignedToName;
  final DateTime? startedAt;
  final DateTime createdAt;
  final List<ChatMessage> messages;

  const ChatSession({
    required this.id,
    this.lane = 'CUSTOMER_SERVICE',
    this.status = 'QUEUED',
    this.subject = '',
    this.assignedToName,
    this.startedAt,
    required this.createdAt,
    this.messages = const [],
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id']?.toString() ?? '',
        lane: json['lane']?.toString() ?? 'CUSTOMER_SERVICE',
        status: json['status']?.toString() ?? 'QUEUED',
        subject: json['subject']?.toString() ?? '',
        assignedToName: json['assignedTo'] is Map
            ? (json['assignedTo'] as Map)['name']?.toString()
            : null,
        startedAt: json['startedAt'] != null
            ? DateTime.tryParse(json['startedAt'].toString())
            : null,
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
        messages: (json['messages'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  bool get isClosed => status == 'CLOSED' || status == 'RESOLVED';
}

class ChatMessage {
  final String id;
  final String message;
  final String senderId;
  final String senderName;
  final String senderRole;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    this.message = '',
    this.senderId = '',
    this.senderName = '',
    this.senderRole = 'USER',
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] is Map
        ? Map<String, dynamic>.from(json['sender'])
        : <String, dynamic>{};
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      senderId: sender['id']?.toString() ?? '',
      senderName: sender['name']?.toString() ?? '',
      senderRole: sender['role']?.toString() ?? 'USER',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class SupportTicket {
  final String id;
  final String subject;
  final String message;
  final String category;
  final String priority;
  final String status;
  final DateTime createdAt;

  const SupportTicket({
    required this.id,
    this.subject = '',
    this.message = '',
    this.category = 'GENERAL',
    this.priority = 'NORMAL',
    this.status = 'OPEN',
    required this.createdAt,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        id: json['id']?.toString() ?? '',
        subject: json['subject']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        category: json['category']?.toString() ?? 'GENERAL',
        priority: json['priority']?.toString() ?? 'NORMAL',
        status: json['status']?.toString() ?? 'OPEN',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Live support store: chats + tickets from the real backend.
class SupportService extends ChangeNotifier {
  List<ChatSession> _sessions = const [];
  List<SupportTicket> _tickets = const [];
  int? _queuePosition;
  bool _loading = false;
  Object? _error;

  List<ChatSession> get sessions => _sessions;
  List<SupportTicket> get tickets => _tickets;
  int? get queuePosition => _queuePosition;
  bool get loading => _loading;
  Object? get error => _error;

  ChatSession? get activeSession =>
      _sessions.isEmpty || _sessions.first.isClosed ? null : _sessions.first;

  Future<void> syncChat() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (!passengerApi.isLoggedIn) return;
      final json = await passengerApi.getSupportChat();
      final raw = json['sessions'] is List ? json['sessions'] as List : const [];
      _sessions = raw.whereType<Map>().map((e) {
        return ChatSession.fromJson(Map<String, dynamic>.from(e));
      }).toList();
      _queuePosition = json['queuePosition'] as int?;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> syncTickets() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (!passengerApi.isLoggedIn) return;
      final rows = await passengerApi.getSupportTickets();
      _tickets = rows.whereType<Map>().map((e) {
        return SupportTicket.fromJson(Map<String, dynamic>.from(e));
      }).toList();
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Starts a new chat (reuses the active one for the lane when present).
  Future<ChatSession?> startChat({
    required String subject,
    required String message,
    String lane = 'CUSTOMER_SERVICE',
  }) async {
    if (!passengerApi.isLoggedIn) return null;
    final json = await passengerApi.createSupportChat(
      subject: subject,
      message: message,
      lane: lane,
    );
    final session = json['session'] is Map
        ? ChatSession.fromJson(Map<String, dynamic>.from(json['session']))
        : null;
    if (session != null) {
      _sessions = [
        session,
        ..._sessions.where((s) => s.id != session.id),
      ];
      _queuePosition = json['queuePosition'] as int?;
      notifyListeners();
    }
    return session;
  }

  Future<bool> sendMessage(String sessionId, String message) async {
    try {
      await passengerApi.sendChatMessage(sessionId, message);
      await syncChat();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> closeChat(String sessionId) async {
    try {
      await passengerApi.closeChat(sessionId);
      await syncChat();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<SupportTicket?> submitTicket({
    required String subject,
    required String message,
    String category = 'GENERAL',
    String priority = 'NORMAL',
  }) async {
    if (!passengerApi.isLoggedIn) return null;
    final json = await passengerApi.createSupportTicket(
      subject: subject,
      message: message,
      category: category,
      priority: priority,
    );
    final ticket = SupportTicket.fromJson(Map<String, dynamic>.from(json));
    _tickets = [ticket, ..._tickets];
    notifyListeners();
    return ticket;
  }
}