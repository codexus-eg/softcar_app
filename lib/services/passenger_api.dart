import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thin client for the SoftCar production mobile API at softcarshuttle.com,
/// used by the passenger app. Bearer token is an SHA-256-hashed 30-day
/// `MobileSession` created by the backend, exactly like the driver app.
class PassengerApiException implements Exception {
  final String message;
  final String? code;
  final int status;
  const PassengerApiException(this.message, {this.code, this.status = 400});

  /// True for connectivity-level failures (server unreachable/offline).
  bool get isNetwork => code == 'NETWORK_ERROR';

  @override
  String toString() => message;
}

class PassengerApi {
  PassengerApi({String? baseUrl})
    : _base = baseUrl ?? 'https://softcarshuttle.com/api/mobile',
      _origin = 'https://softcarshuttle.com';

  static const _tokenKey = 'softcar.passenger.token';
  static const _userKey = 'softcar.passenger.user';

  final String _base;
  final String _origin;
  String? _token;
  Map<String, dynamic> _user = const {};

  String? get token => _token;
  Map<String, dynamic> get user => _user;
  bool get isLoggedIn => _token != null;

  // ---- session ------------------------------------------------------------

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      final rawUser = prefs.getString(_userKey);
      if (rawUser != null) {
        final decoded = jsonDecode(rawUser);
        if (decoded is Map) _user = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      _token = null;
    }
  }

  Future<void> persistSession(String? token, Map<String, dynamic>? user) async {
    _token = token;
    if (user != null) _user = user;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token == null) {
        await prefs.remove(_tokenKey);
        await prefs.remove(_userKey);
        _user = const {};
      } else {
        await prefs.setString(_tokenKey, token);
        await prefs.setString(_userKey, jsonEncode(_user));
      }
    } catch (_) {}
  }

  Future<void> signOut() async {
    await persistSession(null, null);
  }

  // ---- auth ---------------------------------------------------------------

  Future<Map<String, dynamic>> login(String identifier, String password) async {
    final json = await _request(
      'POST',
      '/auth/login',
      body: {
        'identifier': identifier.trim(),
        'password': password,
        'platform': 'flutter-passenger',
        'deviceName': 'SoftCar Passenger',
      },
      auth: false,
    );
    final token = json['token'];
    if (token is String && token.isNotEmpty) {
      final user = json['user'];
      await persistSession(
        token,
        user is Map ? Map<String, dynamic>.from(user) : const {},
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? gender,
    bool acceptTerms = true,
  }) async {
    final uri = Uri.parse('$_origin/api/auth/register');
    final res = await http.post(
      uri,
      headers: _jsonHeaders(),
      body: jsonEncode({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        'password': password,
        if (gender != null && gender.isNotEmpty) 'gender': gender,
        'acceptTerms': acceptTerms,
        'createMobileSession': true,
        'platform': 'flutter-passenger',
        'deviceName': 'SoftCar Passenger',
      }),
    );
    final decoded = _decode(res);
    if (res.statusCode >= 400) {
      throw PassengerApiException(
        decoded is Map
            ? (decoded['message'] ?? 'Registration failed')
            : 'Registration failed ($res.statusCode)',
        code:
            decoded is Map && decoded['code'] != null
                ? decoded['code'].toString()
                : null,
        status: res.statusCode,
      );
    }
    final token = decoded['token'];
    if (token is String && token.isNotEmpty) {
      final user = decoded['user'];
      await persistSession(
        token,
        user is Map ? Map<String, dynamic>.from(user) : const {},
      );
    }
    return decoded;
  }

  // ---- OTP (BeOn) --------------------------------------------------------

  /// Sends a 6-digit OTP via BeOn to [target] (Egyptian phone `01xxxxxxxxx`
  /// or email). Used for register-verification and password resets.
  ///
  /// OTP/register routes live at `/api/auth/*` (NOT under `/api/mobile/*`),
  /// so they are hit directly on [_origin] like the register call below.
  Future<Map<String, dynamic>> requestOtp({
    required String channel,
    required String target,
  }) async {
    return _authRequest(
      'POST',
      '/api/auth/request-otp',
      body: {'channel': channel, 'target': target.trim()},
    );
  }

  /// Verifies a 6-digit OTP for [target]. Throws on wrong/expired codes with
  /// the backend's Arabic error message.
  Future<Map<String, dynamic>> verifyOtp({
    required String target,
    required String code,
  }) async {
    return _authRequest(
      'POST',
      '/api/auth/verify-otp',
      body: {'target': target.trim(), 'code': code.trim()},
    );
  }

  /// Sends an OTP to [phone] for the forgot-password flow.
  Future<Map<String, dynamic>> forgotPassword(String phone) async {
    return _authRequest(
      'POST',
      '/api/auth/forgot-password',
      body: {'phone': phone.trim()},
    );
  }

  /// Resets the password for the phone-owning account using the OTP [code].
  Future<Map<String, dynamic>> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    return _authRequest(
      'POST',
      '/api/auth/reset-password',
      body: {
        'phone': phone.trim(),
        'code': code.trim(),
        'newPassword': newPassword,
      },
    );
  }

  // ---- push ---------------------------------------------------------------

  /// Registers this device's Expo push token so the backend can send loud
  /// notifications to the passenger. [isExpoPushToken] mirrors the backend
  /// validator; set it false for a raw FCM token.
  Future<Map<String, dynamic>> registerPushDevice({
    required String token,
    required String platform,
    String? deviceName,
    bool isExpoPushToken = true,
  }) async {
    return _request(
      'POST',
      '/push/register',
      body: {
        'token': token,
        'platform': platform,
        if (deviceName != null) 'deviceName': deviceName,
        'isExpoPushToken': isExpoPushToken,
      },
    );
  }

  Future<void> unregisterPushDevice(String token) async {
    await _request('DELETE', '/push/register', body: {'token': token});
  }

  // ---- data ---------------------------------------------------------------

  Future<List<dynamic>> getTrips({
    String? q,
    String? from,
    String? to,
    String? date,
    double? lat,
    double? lng,
  }) async {
    final query = <String, String>{
      if (q != null && q.isNotEmpty) 'q': q,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (date != null && date.isNotEmpty) 'date': date,
      if (lat != null) 'lat': '$lat',
      if (lng != null) 'lng': '$lng',
    };
    final json = await _request('GET', '/trips', query: query);
    return json['data'] is List ? json['data'] as List : const [];
  }

  /// Authoritative single-trip payload (with per-reservation seat + owner
  /// gender). Seat selection uses this so every reserved seat reflects the
  /// real reservation's gender regardless of which entry path supplied the
  /// trip object. Returns null when the trip cannot be resolved.
  Future<Map<String, dynamic>?> fetchTripDetail(String id) async {
    final json = await _request('GET', '/trips', query: {'id': id});
    final list = json['data'];
    if (list is List && list.isNotEmpty) {
      return Map<String, dynamic>.from(list.first as Map);
    }
    return null;
  }

  /// Starts a PCI SAQ-A hosted Cybersource checkout for a pending CARD
  /// reservation. No card data ever enters this app's API requests.
  Future<Map<String, dynamic>> createCardPaymentSession(String reservationId) =>
      _request(
        'POST',
        '/payments/create-session',
        body: {'reservationId': reservationId},
      );

  Future<Map<String, dynamic>> getCardPaymentStatus(String transactionId) =>
      _request('GET', '/payments/$transactionId');

  /// Active reserve tiers (`GET /api/mobile/tiers`), returned as a plain
  /// list under `tiers`. General and trip-scoped packages are both included.
  Future<List<dynamic>> getTiers() async {
    final json = await _request('GET', '/tiers');
    return json['tiers'] is List ? json['tiers'] as List : const [];
  }

  /// Public home-screen ads (`GET /api/mobile/ads`), returned as a list under
  /// `ads`. Each ad carries `id`, `name`, (relative) `imageUrl`, `details`
  /// and an optional `animation` hint.
  Future<List<Map<String, dynamic>>> getAds() async {
    final json = await _request('GET', '/ads', auth: false);
    final list = json['ads'] is List ? json['ads'] as List : const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// The single "focused event" ad (`GET /api/mobile/ads/focused`) that should
  /// be shown as a forced overlay when the app starts, or null when none is
  /// configured. Public — the backend only returns active, focused ads.
  Future<Map<String, dynamic>?> getFocusedAd() async {
    final json = await _request('GET', '/ads/focused', auth: false);
    final ad = json['ad'];
    return ad is Map ? Map<String, dynamic>.from(ad) : null;
  }

  /// Records an ad impression (`POST /ads/{id}/view`). Public, best-effort —
  /// failures are swallowed so home rendering never breaks.
  Future<void> reportAdView(String adId) async {
    try {
      await _request('POST', '/ads/$adId/view', auth: false);
    } catch (_) {
      // best-effort analytics
    }
  }

  /// Records an ad click (`POST /ads/{id}/click`). Public, best-effort.
  Future<void> reportAdClick(String adId) async {
    try {
      await _request('POST', '/ads/$adId/click', auth: false);
    } catch (_) {
      // best-effort analytics
    }
  }

  /// Active promo vouchers (`GET /api/vouchers/active`). Public, no auth —
  /// only published, in-date vouchers are returned under the `vouchers` key.
  Future<List<Map<String, dynamic>>> getActiveVouchers() async {
    final uri = Uri.parse('$_origin/api/vouchers/active');
    final headers = _jsonHeaders()..remove('Authorization');
    http.Response res;
    try {
      res = await http.get(uri, headers: headers);
    } catch (_) {
      throw PassengerApiException(
        'Unable to reach the server. Check your connection.',
        code: 'NETWORK_ERROR',
      );
    }
    final decoded = _decode(res);
    if (res.statusCode >= 400) {
      throw PassengerApiException(
        decoded is Map
            ? (decoded['message'] ??
                decoded['error'] ??
                'Could not load vouchers ($res.statusCode)')
            : 'Could not load vouchers ($res.statusCode)',
        code:
            decoded is Map && decoded['code'] != null
                ? decoded['code'].toString()
                : null,
        status: res.statusCode,
      );
    }
    final list =
        decoded is Map && decoded['vouchers'] is List
            ? decoded['vouchers'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// The passenger's personal bonus vouchers
  /// (`GET /api/mobile/member/vouchers`, bearer auth). Returned under the
  /// `vouchers` key; each carries `id`, `code`, `name`, `description`,
  /// `imageUrl`, `type`, `scope`, `value`, `startAt`, `endAt`,
  /// `maxPerPassenger`, `maxRedemptions`, `redeemedCount`, `usedUp` and an
  /// optional nested `freeTier`.
  Future<List<Map<String, dynamic>>> getMemberVouchers() async {
    final json = await _request('GET', '/member/vouchers');
    final list =
        json['vouchers'] is List ? json['vouchers'] as List : const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Validates a promo voucher against a live trip
  /// (`POST /api/mobile/vouchers/validate`). Returns the backend's voucher
  /// discount payload (discount amount/percent), or throws the backend error
  /// message (with `status`/`code`) when the code is invalid.
  Future<Map<String, dynamic>> validateVoucher({    required String code,
    required String tripId,
    String? pickupPointId,
    String? dropoffPointId,
    int? seats,
    String? tierId,
  }) async {
    return _request(
      'POST',
      '/vouchers/validate',
      body: {
        'code': code.trim(),
        'tripId': tripId,
        if (pickupPointId != null && pickupPointId.isNotEmpty)
          'pickupPointId': pickupPointId,
        if (dropoffPointId != null && dropoffPointId.isNotEmpty)
          'dropoffPointId': dropoffPointId,
        if (seats != null) 'seats': seats,
        if (tierId != null && tierId.isNotEmpty) 'tierId': tierId,
      },
    );
  }

  /// Quotes the live per-seat fare for a pickup → drop-off pair using the
  /// backend segment-pricing engine (falls back to the trip base fare for
  /// non-segment routes).
  Future<Map<String, dynamic>> quoteTripPrice({
    required String tripId,
    required String pickupPointId,
    required String dropoffPointId,
    int seats = 1,
  }) async {
    return _request(
      'POST',
      '/pricing/calculate',
      body: {
        'tripId': tripId,
        'pickupPointId': pickupPointId,
        'dropoffPointId': dropoffPointId,
        'seats': seats,
      },
    );
  }

  Future<Map<String, dynamic>> createReservation({
    required String tripId,
    required String pickupPointId,
    required String dropoffPointId,
    required int seats,
    String? seatNumbers,
    String paymentMethod = 'CASH',
    String? clientRequestId,
    bool roundTrip = false,
    String? roundTripReturnTripId,
    String? returnPickupPointId,
    String? returnDropoffPointId,
    String? tierId,
  }) async {
    final json = await _request(
      'POST',
      '/reservations',
      body: {
        'tripId': tripId,
        'pickupPointId': pickupPointId,
        'dropoffPointId': dropoffPointId,
        'seats': seats,
        if (seatNumbers != null) 'seatNumbers': seatNumbers,
        'paymentMethod': paymentMethod,
        if (clientRequestId != null) 'clientRequestId': clientRequestId,
        if (tierId != null && tierId.isNotEmpty) 'tierId': tierId,
        if (roundTrip) ...{
          'roundTrip': true,
          'roundTripReturnTripId': roundTripReturnTripId ?? '',
          'returnPickupPointId': returnPickupPointId ?? '',
          'returnDropoffPointId': returnDropoffPointId ?? '',
        },
      },
    );
    return json['data'] is Map ? Map<String, dynamic>.from(json['data']) : json;
  }

  /// Creates a recurring reservation plan. [weekdays] are ISO day numbers
  /// (Sunday=0 .. Saturday=6), matching what the UI date pickers produce.
  /// [selectedServiceDates] are optional explicit `yyyy-MM-dd` overrides.
  Future<Map<String, dynamic>> createRecurringReservation({
    required String tripId,
    required String pickupPointId,
    required String dropoffPointId,
    required String startDate,
    required String endDate,
    required List<int> weekdays,
    required int seats,
    String? seatNumbers,
    String paymentMethod = 'CASH',
    String? tierId,
    String? clientRequestId,
    List<String>? selectedServiceDates,
    String? includedPrimaryPlanId,
  }) async {
    return _request(
      'POST',
      '/recurring-reservations',
      body: {
        'tripId': tripId,
        'pickupPointId': pickupPointId,
        'dropoffPointId': dropoffPointId,
        'startDate': startDate,
        'endDate': endDate,
        'weekdays': weekdays,
        'seats': seats,
        if (seatNumbers != null) 'seatNumbers': seatNumbers,
        'paymentMethod': paymentMethod,
        if (tierId != null && tierId.isNotEmpty) 'tierId': tierId,
        if (clientRequestId != null) 'clientRequestId': clientRequestId,
        if (selectedServiceDates != null && selectedServiceDates.isNotEmpty)
          'selectedServiceDates': selectedServiceDates,
        if (includedPrimaryPlanId != null && includedPrimaryPlanId.isNotEmpty)
          'includedPrimaryPlanId': includedPrimaryPlanId,
      },
    );
  }

  Future<List<dynamic>> getReservations() async {
    final json = await _request('GET', '/reservations');
    return json['data'] is List ? json['data'] as List : const [];
  }

  /// Pending boarding/cash confirmations the driver is waiting on
  /// (`GET /api/mobile/reservations/confirmations`). Returns
  /// `{ data: [...] }` each with the confirmation + reservation + trip.
  Future<List<dynamic>> getPendingConfirmations() async {
    final json = await _request('GET', '/reservations/confirmations');
    return json['confirmations'] is List ? json['confirmations'] as List : const [];
  }

  /// Confirms or rejects a boarding/cash confirmation
  /// (`PATCH /api/mobile/reservations/confirmations/{id}`).
  /// `confirmedBoarding`/`confirmedPayment` reflect what really happened.
  Future<Map<String, dynamic>> respondToConfirmation(
    String confirmationId, {
    required bool confirmedBoarding,
    required bool confirmedPayment,
    String? responseNote,
  }) async {
    return _request('PATCH', '/reservations/confirmations/$confirmationId', body: {
      'action': confirmedBoarding || confirmedPayment ? 'confirm' : 'reject',
      'confirmedBoarding': confirmedBoarding,
      'confirmedPayment': confirmedPayment,
      if (responseNote != null && responseNote.isNotEmpty)
        'responseNote': responseNote,
    });
  }

  /// Cancels the passenger's own RESERVED reservation
  /// (`POST /api/mobile/reservations/{id}/cancel`). The backend restores the
  /// seats and auto-refunds any paid amount to the passenger wallet. Returns
  /// `{success, message, record, refundedAmount}`.
  Future<Map<String, dynamic>> cancelReservation(String reservationId) async {
    return _request('POST', '/reservations/$reservationId/cancel');
  }

  /// Moves a RESERVED reservation to another SCHEDULED trip of the same
  /// service class (`POST /api/mobile/reservations/{id}/transfer`). Returns
  /// `{success, message, reservationId, tripId, tripTitle, serviceDate}`.
  Future<Map<String, dynamic>> transferReservation({
    required String reservationId,
    required String targetTripId,
  }) async {
    return _request(
      'POST',
      '/reservations/$reservationId/transfer',
      body: {'targetTripId': targetTripId},
    );
  }

  Future<Map<String, dynamic>> getWallet() async {
    return _request('GET', '/wallet/transactions');
  }

  /// POST /wallet/transactions — starts a wallet top-up pending finance review.
  Future<Map<String, dynamic>> rechargeWallet(Map<String, dynamic> body) async {
    final json = await _request('POST', '/wallet/transactions', body: body);
    return json['data'] is Map ? Map<String, dynamic>.from(json['data']) : json;
  }

  /// POST /wallet/evidence — uploads a screenshot/receipt proving a top-up.
  ///
  /// The backend contract is a JSON payload carrying the image as base64 plus
  /// metadata (so it can hash and store it), NOT a multipart upload.
  Future<Map<String, dynamic>> uploadWalletEvidence({
    required String transactionId,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    int? width;
    int? height;
    try {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
    } catch (_) {}
    return _request('POST', '/wallet/evidence', body: {
      'transactionId': transactionId,
      'screenshotBase64': base64Encode(bytes),
      'contentType': contentType,
      'sizeBytes': bytes.length,
      'width': width,
      'height': height,
    });
  }

  /// POST /payments/create-session — creates a Cybersource checkout session
  /// for a CARD reservation. Returns transactionId + checkoutUrl.
  Future<Map<String, dynamic>> createPaymentSession({
    required String reservationId,
  }) async {
    return _request('POST', '/payments/create-session', body: {
      'reservationId': reservationId,
    });
  }

  /// GET /payments/:transactionId — polls Cybersource payment status.
  Future<Map<String, dynamic>> getPaymentStatus(String transactionId) async {
    return _request('GET', '/payments/$transactionId');
  }

  Future<Map<String, dynamic>> getNotifications() async {
    return _request('GET', '/notifications');
  }

  // ---- account / profile ------------------------------------------------

  /// Updates the passenger's profile on the live backend (name, phone,
  /// gender, language, notification prefs). Returns the updated user map.
  Future<Map<String, dynamic>> updateAccount(
    Map<String, dynamic> fields,
  ) async {
    final json = await _request('PATCH', '/account', body: fields);
    final user = json['user'];
    if (user is Map) {
      _user = Map<String, dynamic>.from(user);
      await _persistUser();
    }
    return json;
  }

  /// Uploads an avatar photo. [bytes] must be a JPEG/PNG/WebP image.
  Future<String> uploadAvatar(List<int> bytes, String contentType) async {
    final uri = Uri.parse('$_base/account/photo');
    final request =
        http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer $_token'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: 'avatar',
              contentType:
                  contentType.contains('png')
                      ? http.MediaType('image', 'png')
                      : contentType.contains('webp')
                      ? http.MediaType('image', 'webp')
                      : http.MediaType('image', 'jpeg'),
            ),
          );
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final decoded = _decode(res);
    if (res.statusCode >= 400) {
      throw PassengerApiException(
        decoded is Map
            ? (decoded['error'] ?? decoded['message'] ?? 'Upload failed')
            : 'Upload failed ($res.statusCode)',
        status: res.statusCode,
      );
    }
    final imageUrl = decoded is Map ? decoded['imageUrl']?.toString() : null;
    if (imageUrl != null) {
      _user = Map<String, dynamic>.from(_user)..['image'] = imageUrl;
      await _persistUser();
    }
    return imageUrl ?? '';
  }

  /// Removes the passenger's avatar from the live backend.
  Future<void> removeAvatar() async {
    final uri = Uri.parse('$_base/account/photo');
    final res = await http.delete(uri, headers: _jsonHeaders());
    if (res.statusCode >= 400) {
      throw PassengerApiException(
        'Could not remove photo',
        status: res.statusCode,
      );
    }
    _user = Map<String, dynamic>.from(_user)..['image'] = null;
    await _persistUser();
  }

  /// Deletes the passenger account permanently (active reservations block it).
  Future<void> deleteAccount() async {
    await _request('DELETE', '/account');
  }

  /// Refreshes the full profile from `/api/mobile/me` (includes saved places,
  /// date of birth, emergency phone and referral code).
  Future<Map<String, dynamic>> getMe() async {
    final json = await _request('GET', '/me');
    final user = json['user'];
    if (user is Map) {
      _user = Map<String, dynamic>.from(user);
      await _persistUser();
    }
    return json;
  }

  // ---- saved places (Work / Home) ---------------------------------------

  Future<List<Map<String, dynamic>>> getSavedPlaces() async {
    final json = await _request('GET', '/account/places');
    final list = json['places'];
    if (list is List) return list.cast<Map<String, dynamic>>();
    return const [];
  }

  Future<Map<String, dynamic>> savePlace({
    required String label,
    required String name,
    required String address,
    required double lat,
    required double lng,
    required String placeType,
    String? placeId,
    bool isDefault = false,
  }) async {
    return _request('POST', '/account/places', body: {
      'label': label,
      'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
      'placeType': placeType,
      if (placeId != null && placeId.isNotEmpty) 'placeId': placeId,
      'isDefault': isDefault,
    });
  }

  Future<Map<String, dynamic>> updatePlace(
    String placeId,
    Map<String, dynamic> fields,
  ) async {
    return _request('PATCH', '/account/places/$placeId', body: fields);
  }

  Future<void> deletePlace(String placeId) async {
    await _request('DELETE', '/account/places/$placeId');
  }

  // ---- referral ----------------------------------------------------------

  /// Applies a friend's referral code to this account. The backend keeps it
  /// so future completed trips can grant the referrer their bonus.
  Future<void> applyReferral(String code) async {
    await _request('POST', '/account/referral', body: {'code': code});
  }

  // ---- Where-to smart search --------------------------------------------

  /// `GET /api/mobile/trips/whereto` — searches every upcoming trip that can
  /// take the user from [lat],[lng] to a destination that is either a typed
  /// place name (geocoded + stopped match) or exact coordinates. Results come
  /// back sorted ascending by accuracy (walk distance to board/alight stops).
  Future<Map<String, dynamic>> whereTo({
    required double lat,
    required double lng,
    String? to,
    double? toLat,
    double? toLng,
    int? maxResults,
  }) async {
    final query = <String, String>{
      'lat': lat.toStringAsFixed(6),
      'lng': lng.toStringAsFixed(6),
      if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
      if (toLat != null) 'toLat': toLat.toStringAsFixed(6),
      if (toLng != null) 'toLng': toLng.toStringAsFixed(6),
      if (maxResults != null) 'maxResults': '$maxResults',
    };
    return _request('GET', '/trips/whereto', query: query);
  }

  /// App-side push acknowledgement — tells the ops dashboard the FCM message
  /// was actually rendered on this device (delivery monitoring).
  Future<void> ackPush(String token, {String? notificationId}) async {
    await _request(
      'POST',
      '/push/ack',
      body: {
        'token': token,
        if (notificationId != null && notificationId.isNotEmpty)
          'notificationId': notificationId,
      },
    ).catchError((_) => <String, dynamic>{});
  }

  Future<void> _persistUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(_user));
    } catch (_) {}
  }

  // ---- support tickets --------------------------------------------------

  Future<List<dynamic>> getSupportTickets() async {
    final raw = await _request('GET', '/support-tickets');
    final direct = raw['data'];
    if (direct is List) return direct;
    if (raw['notifications'] is List) return raw['notifications'] as List;
    return raw.values.whereType<List>().isNotEmpty
        ? raw.values.firstWhere((v) => v is List) as List
        : <dynamic>[];
  }

  Future<Map<String, dynamic>> createSupportTicket({
    required String subject,
    required String message,
    String category = 'GENERAL',
    String priority = 'NORMAL',
  }) async {
    final json = await _request(
      'POST',
      '/support-tickets',
      body: {
        'subject': subject.trim(),
        'message': message.trim(),
        'category': category,
        'priority': priority,
      },
    );
    return json;
  }

  // ---- support chat -----------------------------------------------------

  Future<Map<String, dynamic>> getSupportChat() async {
    return _request('GET', '/support-chat');
  }

  /// Creates a new chat session (or reuses the active one for this lane).
  Future<Map<String, dynamic>> createSupportChat({
    required String subject,
    required String message,
    String lane = 'CUSTOMER_SERVICE',
  }) async {
    return _request(
      'POST',
      '/support-chat',
      body: {
        'action': 'create',
        'subject': subject.trim(),
        'message': message.trim(),
        'lane': lane,
      },
    );
  }

  /// Sends a message into an existing live chat session.
  Future<void> sendChatMessage(String sessionId, String message) async {
    await _request(
      'POST',
      '/support-chat',
      body: {'action': 'message', 'sessionId': sessionId, 'message': message},
    );
  }

  /// Closes an existing chat session.
  Future<void> closeChat(String sessionId) async {
    await _request(
      'POST',
      '/support-chat',
      body: {'action': 'close', 'sessionId': sessionId},
    );
  }

  // ---- secure in-app support calls --------------------------------------

  Future<Map<String, dynamic>> createSupportCall({
    required String reason,
    int priority = 0,
  }) => _request('POST', '/voip/sessions', body: {
        'reason': reason.trim(),
        'priority': priority,
        'lane': 'CUSTOMER_SERVICE',
      });

  Future<Map<String, dynamic>> getSupportCall(String id) => _request(
        'GET',
        '/voip/sessions?id=${Uri.encodeQueryComponent(id)}',
      );

  Future<void> updateSupportCall(String id, String action) async {
    await _request('POST', '/voip/sessions', body: {'id': id, 'action': action});
  }

  Future<void> sendCallSignal(
    String callId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    await _request('POST', '/voip/signals', body: {
      'callId': callId,
      'type': type,
      'payload': payload,
    });
  }

  Future<List<Map<String, dynamic>>> getCallSignals(
    String callId,
    DateTime? after,
  ) async {
    final suffix = after == null
        ? ''
        : '&after=${Uri.encodeQueryComponent(after.toUtc().toIso8601String())}';
    final json = await _request(
      'GET',
      '/voip/signals?callId=${Uri.encodeQueryComponent(callId)}$suffix',
    );
    final values = json['signals'];
    return values is List
        ? values.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
  }

  // ---- Soft-Call VoIP -----------------------------------------------------

  /// POST /voip/sessions — action-based Soft-Call endpoint
  /// (`create` | `heartbeat` | `cancel` | `end` | `accept`).
  Future<Map<String, dynamic>> voipPostSession(
    Map<String, dynamic> body,
  ) =>
      _request('POST', '/voip/sessions', body: body);

  /// GET /voip/sessions?id= — fresh session incl. queuePosition/iceServers.
  Future<Map<String, dynamic>> voipGetSession(String id) => _request(
        'GET',
        '/voip/sessions?id=${Uri.encodeQueryComponent(id)}',
      );

  Future<void> voipSendSignal(
    String callSessionId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    await _request('POST', '/voip/signals', body: {
      'callSessionId': callSessionId,
      'type': type,
      'payload': payload,
    });
  }

  Future<List<Map<String, dynamic>>> voipGetSignals(
    String callSessionId,
    DateTime? after,
  ) async {
    final suffix = after == null
        ? ''
        : '&after=${Uri.encodeQueryComponent(after.toUtc().toIso8601String())}';
    final json = await _request(
      'GET',
      '/voip/signals?callSessionId='
          '${Uri.encodeQueryComponent(callSessionId)}$suffix',
    );
    final values = json['signals'];
    return values is List
        ? values.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
  }

  // ---- loyalty / reviews --------------------------------------------------

  Future<Map<String, dynamic>> getLoyalty() async {
    final json = await _request('GET', '/loyalty');
    return json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
  }

  Future<Map<String, dynamic>> submitReview({
    required String reservationId,
    required int rating,
    String? title,
    String? body,
    String? complaint,
  }) async {
    return _request(
      'POST',
      '/reservations/$reservationId/review',
      body: {
        'rating': rating,
        if (title != null && title.trim().isNotEmpty)
          'reviewTitle': title.trim(),
        if (body != null && body.trim().isNotEmpty) 'reviewBody': body.trim(),
        if (complaint != null && complaint.trim().isNotEmpty)
          'complaint': complaint.trim(),
      },
    );
  }

  // ---- transport ----------------------------------------------------------

  Map<String, String> _jsonHeaders() => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  dynamic _decode(http.Response res) {
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Sends a request to a pre-auth `/api/auth/*` endpoint directly on
  /// [_origin] (the mobile base prefixes `/api/mobile`, which does not exist
  /// for OTP/register routes).
  Future<Map<String, dynamic>> _authRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    var uri = Uri.parse('$_origin$path');
    final headers = _jsonHeaders();
    headers.remove('Authorization');
    final encoded = body != null ? jsonEncode(body) : null;

    http.Response res;
    try {
      res = switch (method) {
        'GET' => await http.get(uri, headers: headers),
        'POST' => await http.post(uri, headers: headers, body: encoded),
        'PATCH' => await http.patch(uri, headers: headers, body: encoded),
        'DELETE' => await http.delete(uri, headers: headers),
        _ => throw ArgumentError('unsupported method $method'),
      };
    } catch (_) {
      throw PassengerApiException(
        'Unable to reach the server. Check your connection.',
        code: 'NETWORK_ERROR',
      );
    }

    final status = res.statusCode;
    final decoded = _decode(res);

    if (status >= 400) {
      final err =
          decoded is Map
              ? (decoded['message'] ??
                  decoded['error'] ??
                  'Error $status from server')
              : 'Error $status';
      throw PassengerApiException(
        err,
        code:
            decoded is Map && decoded['code'] != null
                ? decoded['code'].toString()
                : null,
        status: status,
      );
    }

    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'data': decoded};
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = true,
  }) async {
    var uri = Uri.parse('$_base$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    final headers = _jsonHeaders();
    if (!auth) headers.remove('Authorization');
    final encoded = body != null ? jsonEncode(body) : null;

    http.Response res;
    try {
      res = switch (method) {
        'GET' => await http.get(uri, headers: headers),
        'POST' => await http.post(uri, headers: headers, body: encoded),
        'PATCH' => await http.patch(uri, headers: headers, body: encoded),
        'DELETE' => await http.delete(uri, headers: headers),
        _ => throw ArgumentError('unsupported method $method'),
      };
    } catch (_) {
      throw PassengerApiException(
        'Unable to reach the server. Check your connection.',
        code: 'NETWORK_ERROR',
      );
    }

    final status = res.statusCode;
    final decoded = _decode(res);

    if (status == 401) {
      await signOut();
      throw PassengerApiException(
        decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'Session expired. Please sign in again.',
        code: 'UNAUTHORIZED',
        status: 401,
      );
    }

    if (status >= 400) {
      final err =
          decoded is Map
              ? (decoded['message'] ??
                  decoded['error'] ??
                  'Error $status from server')
              : 'Error $status';
      throw PassengerApiException(
        err,
        code:
            decoded is Map && decoded['code'] != null
                ? decoded['code'].toString()
                : null,
        status: status,
      );
    }

    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{'data': decoded};
  }
}

/// Process-wide API instance shared by services (auth, shuttle, wallet).
PassengerApi passengerApi = PassengerApi();
