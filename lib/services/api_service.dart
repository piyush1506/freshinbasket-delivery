import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String baseUrl = 'https://freshinbasket.com'; 
  // Default, can be overridden by shared preferences
  static VoidCallback? onUnauthorized;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('api_base_url');
    // Temporarily force local IP for development
    baseUrl = 'https://freshinbasket.com';
    // if (savedUrl != null && savedUrl.isNotEmpty) {
    //   baseUrl = savedUrl;
    // } else {
    //   // Try to use customer app default
    //   baseUrl = 'http://192.168.29.50:8000';
    // }
  }

  static Future<void> setBaseUrl(String newUrl) async {
    baseUrl = newUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', newUrl);
  }

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static dynamic _safeDecode(String body) {
    if (body.trimLeft().startsWith('<')) {
      return null;
    }
    try {
      return json.decode(body);
    } catch (_) {
      return null;
    }
  }

  static Future<dynamic> _request(
    Future<http.Response> Function() sendRequest,
  ) async {
    try {
      var response = await sendRequest();
      if (response.statusCode == 401) {
        final refreshed = await _refreshToken();
        if (refreshed) {
          response = await sendRequest();
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return null;
        final decoded = _safeDecode(response.body);
        if (decoded != null) return decoded;
        throw Exception('Server returned unexpected response (${response.statusCode}).');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        onUnauthorized?.call();
      }
      final body = _safeDecode(response.body);
      if (body is Map) {
        throw Exception(body['detail'] ?? body['message'] ?? 'Request failed (${response.statusCode})');
      }
      throw Exception('Request failed (${response.statusCode})');
    } on SocketException {
      throw Exception('Unable to connect to server. Check your internet connection.');
    } on http.ClientException {
      throw Exception('Unable to connect to server.');
    }
  }

  static Future<bool> _refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refresh = prefs.getString('refresh_token');
      if (refresh == null) {
        onUnauthorized?.call();
        return false;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh': refresh}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await prefs.setString('access_token', data['access']);
        return true;
      }
      onUnauthorized?.call();
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<dynamic> get(String path) async {
    return _request(() async {
      final headers = await _headers();
      return http.get(Uri.parse('$baseUrl/api/v1$path'), headers: headers);
    });
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    return _request(() async {
      final headers = await _headers();
      return http.post(
        Uri.parse('$baseUrl/api/v1$path'),
        headers: headers,
        body: json.encode(body),
      );
    });
  }

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    return _request(() async {
      final headers = await _headers();
      return http.patch(
        Uri.parse('$baseUrl/api/v1$path'),
        headers: headers,
        body: json.encode(body),
      );
    });
  }
}
