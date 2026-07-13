import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _loading = false;
  String? _error;

  AuthProvider() {
    ApiService.onUnauthorized = logout;
  }

  User? get user => _user;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;
  String? get error => _error;

  Future<void> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final userData = prefs.getString('user_data');

    if (token != null && userData != null) {
      try {
        _user = User.fromJson(json.decode(userData));
        if (_user!.role == 'DELIVERY') {
          LocationService.instance.startTracking();
          NotificationService.instance.initialize();
        }
      } catch (_) {
        _clearLocalData();
      }
    }
    notifyListeners();
  }

  Future<String?> sendOtp(String phoneNumber) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/v1/auth/send-otp/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone_number': phoneNumber,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        _loading = false;
        notifyListeners();
        return data['reqId'];
      } else {
        throw Exception(data['detail'] ?? data['message'] ?? data['error'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> verifyOtp(String phoneNumber, String otpCode, String reqId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/v1/auth/verify-otp/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone_number': phoneNumber,
          'otp_code': otpCode,
          'reqId': reqId,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        final userRole = data['user']['role'];
        if (userRole == 'DELIVERY') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('access_token', data['access']);
          await prefs.setString('refresh_token', data['refresh']);
          await prefs.setString('user_data', json.encode(data['user']));

          _user = User.fromJson(data['user']);

          // Start GPS tracking & FCM
          LocationService.instance.startTracking();
          NotificationService.instance.initialize();
        }
        _loading = false;
        notifyListeners();
        return data;
      } else {
        throw Exception(data['detail'] ?? data['message'] ?? data['error'] ?? 'Verification failed');
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> register(String username, String phoneNumber, String email) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/v1/auth/delivery-register/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'phone_number': phoneNumber,
          'email': email.trim().isEmpty ? null : email.trim(),
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        final userRole = data['user']['role'];
        if (userRole != 'DELIVERY') {
          throw Exception('Registered user does not have delivery agent privileges.');
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', data['access']);
        await prefs.setString('refresh_token', data['refresh']);
        await prefs.setString('user_data', json.encode(data['user']));

        _user = User.fromJson(data['user']);
        _loading = false;
        notifyListeners();

        // Start GPS tracking & FCM
        LocationService.instance.startTracking();
        NotificationService.instance.initialize();
        return true;
      } else {
        throw Exception(data['detail'] ?? data['message'] ?? data['error'] ?? 'Registration failed');
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> updateProfile({
    required String username,
    required String email,
    required String phoneNumber,
    required String address,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.patch('/delivery/profile/', {
        'username': username,
        'email': email,
        'phone_number': phoneNumber,
        'address': address,
      });

      _user = User.fromJson(res);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', json.encode(res));
      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> toggleActiveStatus(bool status) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.patch('/delivery/profile/', {
        'is_active': status,
      });

      _user = User.fromJson(res);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', json.encode(res));
      _loading = false;
      notifyListeners();

      if (!status) {
        LocationService.instance.stopTracking();
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refresh = prefs.getString('refresh_token');
      if (refresh != null) {
        await http.post(
          Uri.parse('${ApiService.baseUrl}/api/v1/auth/logout/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'refresh': refresh}),
        );
      }
    } catch (_) {}

    await _clearLocalData();
    LocationService.instance.stopTracking();
    _user = null;
    notifyListeners();
  }

  Future<void> _clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_data');
  }
}
