import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import 'passenger_api.dart';
import 'push_service.dart';
import 'soft_call_bootstrap.dart';
import 'voip_service.dart';

/// Owns the signed-in passenger session backed entirely by the production
/// API (`POST /api/mobile/auth/login` + `/api/auth/register`). No demo
/// OTP path — every login/registration is a real backend call.
class AuthService extends ChangeNotifier {
  UserProfile _profile = const UserProfile();
  bool _isLoggedIn = false;
  String? _lastError;
  bool _live = false;
  bool _busy = false;

  bool get isLoggedIn => _isLoggedIn;
  UserProfile get profile => _profile;
  String? get lastError => _lastError;
  bool get isLive => _live;
  bool get busy => _busy;

  /// True when a server operation is in flight (used by the UI for the
  /// busy state on destructive buttons).
  bool _busyServer = false;
  bool get busyServer => _busyServer;

  /// Restores a persisted mobile session from the previous launch.
  Future<void> bootstrap() async {
    await passengerApi.restore();
    if (passengerApi.isLoggedIn) {
      _applyUser(passengerApi.user);
      _live = true;
      _isLoggedIn = true;
      SoftCallBootstrap.connect();
      final pushToken = PushService.currentPushToken;
      if (pushToken != null && pushToken.isNotEmpty) {
        unawaited(registerPush(pushToken));
      }
      notifyListeners();
    }
  }

  void _applyUser(Map<String, dynamic> user) {
    _profile = UserProfile.fromJson(user);
  }

  /// Real backend sign-in by email or phone + password.
  Future<bool> login(String identifier, String password) async {
    _lastError = null;
    _busy = true;
    notifyListeners();
    try {
      final json = await passengerApi.login(identifier, password);
      _applyUser(json['user'] is Map
          ? Map<String, dynamic>.from(json['user'])
          : const {});
      _live = true;
      _isLoggedIn = true;
      SoftCallBootstrap.connect();
      final pushToken = PushService.currentPushToken;
      if (pushToken != null && pushToken.isNotEmpty) {
        unawaited(registerPush(pushToken));
      }
      return true;
    } on PassengerApiException catch (e) {
      _lastError = e.message;
      return false;
    } catch (_) {
      _lastError = 'Unable to reach the server. Check your connection.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Real backend registration. Email-based accounts are instant; a phone
  /// is optional and gender (male/female) is sent so the server can tailor
  /// the reservation experience.
  Future<bool> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? gender,
    bool acceptTerms = true,
  }) async {
    _lastError = null;
    _busy = true;
    notifyListeners();
    try {
      final json = await passengerApi.register(
        name: name,
        email: email,
        password: password,
        phone: phone,
        gender: gender,
        acceptTerms: acceptTerms,
      );
      _applyUser(json['user'] is Map
          ? Map<String, dynamic>.from(json['user'])
          : <String, dynamic>{
              'name': name.trim(),
              'email': email.trim(),
              'gender': gender,
            });
      _live = true;
      _isLoggedIn = true;
      SoftCallBootstrap.connect();
      final pushToken = PushService.currentPushToken;
      if (pushToken != null && pushToken.isNotEmpty) {
        unawaited(registerPush(pushToken));
      }
      return true;
    } on PassengerApiException catch (e) {
      _lastError = e.message;
      return false;
    } catch (_) {
      _lastError = 'Unable to reach the server. Check your connection.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final pushToken = PushService.currentPushToken;
    if (pushToken != null && pushToken.isNotEmpty) {
      await unregisterPush(pushToken);
    }
    SoftCallBootstrap.disconnect();
    await VoipService.instance.hangUp();
    await VoipService.instance.resetCall();
    _isLoggedIn = false;
    _live = false;
    _profile = const UserProfile();
    await passengerApi.signOut();
    notifyListeners();
  }

  /// Persists a gender added/edited locally (the backend stores it too when
  /// set during registration).
  Future<void> setGender(UserGender gender) async {
    _profile = _profile.copyWith(gender: gender);
    notifyListeners();
  }

  // ---- OTP flows (BeOn, production) --------------------------------------

  /// Sends a 6-digit OTP to [phone] (Egyptian `01xxxxxxxxx`) or [email].
  /// Returns the backend message or throws [PassengerApiException].
  Future<String> requestOtp({
    required String channel,
    required String target,
  }) async {
    _busy = true;
    notifyListeners();
    try {
      final json = await passengerApi.requestOtp(channel: channel, target: target);
      return json['message']?.toString() ?? 'OTP sent';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Verifies an OTP for [target]. Returns true when accepted.
  Future<bool> verifyOtp({required String target, required String code}) async {
    _lastError = null;
    _busy = true;
    notifyListeners();
    try {
      await passengerApi.verifyOtp(target: target, code: code);
      return true;
    } on PassengerApiException catch (e) {
      _lastError = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Sends a reset OTP to [phone] for the forgot-password flow.
  Future<String?> forgotPassword(String phone) async {
    _lastError = null;
    _busy = true;
    notifyListeners();
    try {
      final json = await passengerApi.forgotPassword(phone);
      return json['message']?.toString();
    } on PassengerApiException catch (e) {
      _lastError = e.message;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Resets the password with a verified OTP. Returns error message or null.
  Future<String?> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    _lastError = null;
    _busy = true;
    notifyListeners();
    try {
      await passengerApi.resetPassword(
        phone: phone,
        code: code,
        newPassword: newPassword,
      );
      return null;
    } on PassengerApiException catch (e) {
      _lastError = e.message;
      return e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Registers the device push token with the backend for loud notifications.
  Future<void> registerPush(String token) async {
    try {
      await passengerApi.registerPushDevice(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
        deviceName: 'SoftCar Passenger',
      );
    } on PassengerApiException {
      // Registration is best-effort; failures must never break the app.
    }
  }

  Future<void> unregisterPush(String token) async {
    try {
      await passengerApi.unregisterPushDevice(token);
    } on PassengerApiException {
      // Best-effort.
    }
  }

  // ---- profile management (live backend) --------------------------------

  /// Updates profile fields on the live backend (`PATCH /api/mobile/account`).
  /// Returns the server error message on failure, or null on success.
  Future<String?> updateProfile({
    String? name,
    String? phone,
    String? email,
    UserGender? gender,
    DateTime? dateOfBirth,
    String? emergencyPhone,
    String? referralCode,
    String? preferredLanguage,
    String? preferredTheme,
    bool? pushNotifications,
    bool? emailNotifications,
    bool? phoneNotifications,
  }) async {
    final fields = <String, dynamic>{};
    if (name != null) fields['name'] = name;
    if (phone != null) fields['phone'] = phone;
    if (email != null) fields['email'] = email;
    if (gender != null) fields['gender'] = gender.code;
    if (dateOfBirth != null) {
      fields['dateOfBirth'] = dateOfBirth.toIso8601String().split('T').first;
    }
    if (emergencyPhone != null) fields['emergencyPhone'] = emergencyPhone;
    if (referralCode != null) fields['referralCode'] = referralCode;
    if (preferredLanguage != null) fields['preferredLanguage'] = preferredLanguage;
    if (preferredTheme != null) fields['preferredTheme'] = preferredTheme;
    if (pushNotifications != null) fields['pushNotifications'] = pushNotifications;
    if (emailNotifications != null) fields['emailNotifications'] = emailNotifications;
    if (phoneNotifications != null) fields['phoneNotifications'] = phoneNotifications;
    if (fields.isEmpty) return null;
    try {
      final json = await passengerApi.updateAccount(fields);
      if (json['user'] is Map) {
        _applyUser(Map<String, dynamic>.from(json['user']));
        notifyListeners();
      }
      return null;
    } on PassengerApiException catch (e) {
      return e.message;
    }
  }

  /// Refetches the full profile (me) so saved places, date of birth and the
  /// referral code are always current before the profile page is opened.
  Future<void> refreshProfile() async {
    try {
      final json = await passengerApi.getMe();
      if (json['user'] is Map) {
        _applyUser(Map<String, dynamic>.from(json['user']));
        notifyListeners();
      }
    } on PassengerApiException {
      // Best-effort — the cached profile stays until a live call succeeds.
    }
  }

  // ---- saved places (Work / Home) ----------------------------------------

  Future<dynamic> getSavedPlacesRaw() async =>
      await passengerApi.getSavedPlaces();

  Future<String?> savePlace({
    required String label,
    required String name,
    required String address,
    required double lat,
    required double lng,
    required String placeType,
    String? placeId,
    bool isDefault = false,
  }) async {
    try {
      final json = await passengerApi.savePlace(
        label: label,
        name: name,
        address: address,
        lat: lat,
        lng: lng,
        placeType: placeType,
        placeId: placeId,
        isDefault: isDefault,
      );
      if (json['place'] is Map) {
        final places = List<SavedPlace>.from(profile.savedPlaces)
          ..removeWhere(
              (p) => p.id == (json['place'] as Map)['id']?.toString())
          ..add(SavedPlace.fromJson(Map<String, dynamic>.from(json['place'])));
        _profile = _profile.copyWith(savedPlaces: places);
        notifyListeners();
      }
      return null;
    } on PassengerApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> updatePlace(String placeId, Map<String, dynamic> fields) async {
    try {
      final json = await passengerApi.updatePlace(placeId, fields);
      if (json['place'] is Map) {
        final updated = SavedPlace.fromJson(
            Map<String, dynamic>.from(json['place']));
        final places = List<SavedPlace>.from(profile.savedPlaces)
            .map((p) => p.id == updated.id ? updated : p)
            .toList();
        _profile = _profile.copyWith(savedPlaces: places);
        notifyListeners();
      }
      return null;
    } on PassengerApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> deletePlace(String placeId) async {
    try {
      await passengerApi.deletePlace(placeId);
      _profile = _profile.copyWith(
        savedPlaces: profile.savedPlaces
            .where((p) => p.id != placeId)
            .toList(),
      );
      notifyListeners();
      return null;
    } on PassengerApiException catch (e) {
      return e.message;
    }
  }

  /// Applies a friend's referral code (idempotent server-side).
  Future<String?> applyReferral(String code) async {
    try {
      await passengerApi.applyReferral(code);
      return null;
    } on PassengerApiException catch (e) {
      return e.message;
    }
  }

  /// Uploads an avatar from a picked image. Returns the new image URL.
  Future<String?> uploadAvatar(List<int> bytes, String contentType) async {
    try {
      final url = await passengerApi.uploadAvatar(bytes, contentType);
      _profile = _profile.copyWith(image: url);
      notifyListeners();
      return url;
    } on PassengerApiException {
      return null;
    }
  }

  Future<bool> removeAvatar() async {
    try {
      await passengerApi.removeAvatar();
      _profile = _profile.copyWith(image: null);
      notifyListeners();
      return true;
    } on PassengerApiException {
      return false;
    }
  }

  /// Deletes the account permanently. Returns the server message if blocked
  /// (e.g. active reservations) or null once deleted.
  Future<String?> deleteAccount() async {
    _busyServer = true;
    notifyListeners();
    try {
      await passengerApi.deleteAccount();
      await signOut();
      return null;
    } on PassengerApiException catch (e) {
      return e.message;
    } finally {
      _busyServer = false;
      notifyListeners();
    }
  }
}