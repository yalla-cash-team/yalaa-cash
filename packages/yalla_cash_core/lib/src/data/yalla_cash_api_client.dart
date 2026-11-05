import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yalla_cash_core/src/config/yalla_cash_environment.dart';
import 'package:yalla_cash_core/src/core/failure.dart';
import 'package:yalla_cash_core/src/data/auth_token_store.dart';

class YallaCashApiClient {
  YallaCashApiClient({
    required YallaCashEnvironment environment,
    required AuthTokenStore tokenStore,
    http.Client? httpClient,
  })  : _environment = environment,
        _tokenStore = tokenStore,
        _httpClient = httpClient ?? http.Client();

  final YallaCashEnvironment _environment;
  final AuthTokenStore _tokenStore;
  final http.Client _httpClient;
  AuthTokens? _memoryTokens;

  Future<AuthTokens?> get tokens async {
    if (_memoryTokens != null) return _memoryTokens;
    _memoryTokens = await _tokenStore.read();
    return _memoryTokens;
  }

  Future<bool> hasSavedSession() async {
    final saved = await tokens;
    return saved != null &&
        (saved.accessToken.isNotEmpty || saved.refreshToken.isNotEmpty);
  }

  Future<void> saveTokens(AuthTokens tokens) async {
    _memoryTokens = tokens;
    await _tokenStore.write(tokens);
  }

  Future<void> clearTokens() async {
    _memoryTokens = null;
    await _tokenStore.clear();
  }

  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool authenticated = true,
  }) =>
      _send(
        'GET',
        path,
        query: query,
        authenticated: authenticated,
      );

  Future<Object?> post(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    bool authenticated = true,
  }) =>
      _send(
        'POST',
        path,
        body: body,
        query: query,
        authenticated: authenticated,
      );

  Future<Object?> patch(
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) =>
      _send(
        'PATCH',
        path,
        body: body,
        authenticated: authenticated,
      );

  Future<Object?> put(
    String path, {
    Map<String, Object?>? body,
  }) =>
      _send('PUT', path, body: body);

  Future<Object?> delete(String path) => _send('DELETE', path);

  /// Absolute URL for a server-relative path such as `/stores/1/logo?v=2`.
  /// Full URLs (legacy product, banner or CDN links) are returned unchanged.
  Uri resolveUrl(String path) {
    final parsed = Uri.parse(path);
    if (parsed.hasScheme) return parsed;
    return _uri(parsed.path, parsed.queryParameters);
  }

  /// In-flight refresh-token rotation. Guarantees exactly ONE active
  /// `/auth/refresh` request per API client at any time: concurrent
  /// requests that hit a 401 all await the SAME refresh Future instead of
  /// racing each other with the same single-use refresh token.
  Future<bool>? _refreshInFlight;

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    bool authenticated = true,
    bool retryOnUnauthorized = true,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['accept'] = 'application/json';
    request.headers['content-type'] = 'application/json';

    if (authenticated) {
      final saved = await tokens;
      if (saved?.accessToken case final token?) {
        request.headers['authorization'] = 'Bearer $token';
      }
    }

    if (body != null) request.body = jsonEncode(body);

    try {
      final streamed =
          await _httpClient.send(request).timeout(_environment.apiTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401 && authenticated && retryOnUnauthorized) {
        final refreshed = await _refreshToken();
        if (refreshed) {
          // Re-read the latest tokens: the shared refresh attempt may have
          // completed while this request was waiting on it.
          return await _send(
            method,
            path,
            body: body,
            query: query,
            authenticated: authenticated,
            retryOnUnauthorized: false,
          );
        }
      }
      return _decodeResponse(response);
    } on TimeoutException {
      throw const YallaCashFailure(
        code: 'request_timeout',
        message: 'انتهت مهلة الاتصال بالخادم.',
      );
    } on SocketException {
      throw const YallaCashFailure(
        code: 'network_unavailable',
        message: 'تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت.',
      );
    } on http.ClientException catch (error) {
      throw YallaCashFailure(
        code: 'network_error',
        message: error.message,
        details: error,
      );
    }
  }

  Future<bool> _refreshToken() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final attempt = _performRefresh();
    _refreshInFlight = attempt;
    attempt.whenComplete(() {
      if (identical(_refreshInFlight, attempt)) {
        _refreshInFlight = null;
      }
    });
    return attempt;
  }

  Future<bool> _performRefresh() async {
    final stopwatch = Stopwatch()..start();
    final saved = await tokens;
    if (saved == null) return false;
    try {
      final response = await post(
        '/auth/refresh',
        body: {'refreshToken': saved.refreshToken},
        authenticated: false,
      );
      final json = apiMap(response);
      final newTokens = _tokensFromAuthResponse(json);
      // Persist the rotated pair BEFORE returning so every waiter retries
      // with the fresh access token.
      await saveTokens(newTokens);
      if (kDebugMode) {
        debugPrint(
          'CUSTOMER_STARTUP token_refresh_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      return true;
    } on Object {
      // The refresh attempt failed (invalid/expired refresh token or an
      // unusable response). Only THIS owner of the attempt clears the
      // stored session, exactly once; concurrent waiters simply observe
      // `false` and let their original 401 surface to the caller.
      await clearTokens();
      if (kDebugMode) {
        debugPrint(
          'CUSTOMER_STARTUP token_refresh_failed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      return false;
    }
  }

  Object? _decodeResponse(http.Response response) {
    final raw =
        response.bodyBytes.isEmpty ? '' : utf8.decode(response.bodyBytes);
    final decoded = raw.isEmpty ? null : jsonDecode(raw);
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    if (decoded is Map<String, Object?>) {
      throw YallaCashFailure(
        statusCode: response.statusCode,
        code: decoded['code']?.toString() ?? 'request_failed',
        message: decoded['message']?.toString() ?? 'فشل الطلب.',
        details: decoded['details'],
      );
    }

    throw YallaCashFailure(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'فشل الطلب.',
      details: raw,
    );
  }

  Uri _uri(String path, Map<String, Object?>? query) {
    final base = _environment.apiBaseUrl;
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final childPath = path.startsWith('/') ? path : '/$path';
    final queryParameters = <String, String>{};
    query?.forEach((key, value) {
      if (value != null) queryParameters[key] = value.toString();
    });
    return base.replace(
      path: '$basePath$childPath',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }
}

Map<String, Object?> apiMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw const YallaCashFailure(
    code: 'invalid_response',
    message: 'استجابة الخادم غير متوقعة.',
  );
}

List<Map<String, Object?>> apiItems(Object? value) {
  final map = apiMap(value);
  final items = map['items'];
  if (items is List) {
    return items.map((item) => apiMap(item)).toList(growable: false);
  }
  throw const YallaCashFailure(
    code: 'invalid_response',
    message: 'استجابة الخادم لا تحتوي على قائمة صالحة.',
  );
}

AuthTokens authTokensFromResponse(Map<String, Object?> json) =>
    _tokensFromAuthResponse(json);

AuthTokens _tokensFromAuthResponse(Map<String, Object?> json) {
  final expires = json['expiresInSeconds'] as int? ?? 900;
  return AuthTokens(
    accessToken: json['accessToken']! as String,
    refreshToken: json['refreshToken']! as String,
    expiresAt: DateTime.now().add(Duration(seconds: expires)),
  );
}
