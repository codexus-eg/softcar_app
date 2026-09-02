import 'package:flutter/foundation.dart';

import 'passenger_api.dart';

/// Live in-app notifications from the production backend. Both the home-tab
/// bell badge and the notifications screen share this single source of truth
/// so the unread count is always derived from real `GET /notifications` data.
class NotificationService extends ChangeNotifier {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = false;
  bool _live = false;

  final List<void Function(Map<String, dynamic> notification)> _forcedListeners = [];
  final Set<String> _firedForced = {};

  List<Map<String, dynamic>> get items => _items;
  bool get loading => _loading;
  bool get live => _live;

  /// Registers a listener invoked whenever a newly-arrived focused
  /// notification (EVENT_NOTIFICATION) appears during a refresh, so the shell
  /// can show the forced in-app overlay.
  void addForcedListener(void Function(Map<String, dynamic> notification) callback) {
    _forcedListeners.add(callback);
  }

  void removeForcedListener(void Function(Map<String, dynamic> notification) callback) {
    _forcedListeners.remove(callback);
  }

  int get unreadCount =>
      _items.where((n) => n['read'] != true).length;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      if (!passengerApi.isLoggedIn) {
        _items = const [];
        _live = false;
        return;
      }
      final json = await passengerApi.getNotifications();
      final rows = (json['data'] as List? ?? const [])
          .whereType<Map>()
          .cast<Map<String, dynamic>>()
          .toList()
            ..sort((a, b) => _date(b).compareTo(_date(a)));
      _items = rows;
      _live = true;
      _fireForced(rows);
    } catch (_) {
      // Keep the current list when a refresh fails.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Fires newly-arrived focused notifications exactly once each. A forced
  /// notification is only shown if it arrived after this service was created
  /// (older focused rows are acknowledged on first load).
  void _fireForced(List<Map<String, dynamic>> rows) {
    for (final n in rows) {
      final id = n['id']?.toString() ?? '';
      if (id.isEmpty || _firedForced.contains(id)) continue;
      _firedForced.add(id);
      final type = n['type']?.toString() ?? '';
      if (type != 'EVENT_NOTIFICATION') continue;
      for (final callback in _forcedListeners.toList()) {
        callback(n);
      }
    }
  }

  /// Marks every notification read locally for this session (the backend has
  /// no per-notification read endpoint in the mobile API).
  void markAllRead() {
    _items = _items
        .map((n) => Map<String, dynamic>.from(n)..['read'] = true)
        .toList();
    notifyListeners();
  }

  /// Marks a single notification read locally for this session.
  void markRead(String id) {
    var changed = false;
    _items = _items.map((n) {
      if (n['id']?.toString() != id || n['read'] == true) return n;
      changed = true;
      return Map<String, dynamic>.from(n)..['read'] = true;
    }).toList();
    if (changed) notifyListeners();
  }

  static DateTime _date(Map<String, dynamic> n) =>
      DateTime.tryParse(n['createdAt']?.toString() ??
              n['at']?.toString() ??
              '') ??
      DateTime.now();
}
