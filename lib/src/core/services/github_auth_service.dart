import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GitHubDeviceLogin {
  const GitHubDeviceLogin({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.intervalSeconds,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final int intervalSeconds;
}

class GitHubAccount {
  const GitHubAccount({
    required this.login,
    required this.connected,
  });

  final String login;
  final bool connected;
}

class GitHubAuthService {
  GitHubAuthService._();

  static final GitHubAuthService instance = GitHubAuthService._();

  static const String clientId =
      String.fromEnvironment('NEXUS_GITHUB_CLIENT_ID');

  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'github_access_token';
  static const _refreshTokenKey = 'github_refresh_token';
  static const _expiresAtKey = 'github_access_expires_at';
  static const _refreshExpiresAtKey = 'github_refresh_expires_at';
  static const _loginKey = 'github_login';

  static const _apiVersion = '2026-03-10';

  bool get appConfigured => clientId.trim().isNotEmpty;

  Future<GitHubDeviceLogin> beginDeviceLogin() async {
    if (!appConfigured) {
      throw StateError(
        'This Nexus build does not contain a GitHub App client ID.',
      );
    }

    final response = await http.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: const {
        'Accept': 'application/json',
      },
      body: {
        'client_id': clientId,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'GitHub authorization failed with HTTP ${response.statusCode}.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final deviceCode = data['device_code']?.toString() ?? '';
    final userCode = data['user_code']?.toString() ?? '';
    final verification = data['verification_uri']?.toString() ?? '';
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 900;
    final interval = (data['interval'] as num?)?.toInt() ?? 5;

    if (deviceCode.isEmpty || userCode.isEmpty || verification.isEmpty) {
      throw StateError('GitHub returned an incomplete device login.');
    }

    return GitHubDeviceLogin(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: Uri.parse(verification),
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      intervalSeconds: interval,
    );
  }

  Future<void> openVerificationPage(GitHubDeviceLogin login) async {
    final opened = await launchUrl(
      login.verificationUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw StateError('Could not open GitHub authorization in the browser.');
    }
  }

  Future<GitHubAccount> completeDeviceLogin(
    GitHubDeviceLogin login, {
    void Function(String status)? onStatus,
  }) async {
    var interval = login.intervalSeconds;

    while (DateTime.now().isBefore(login.expiresAt)) {
      onStatus?.call('Waiting for GitHub authorization…');
      await Future<void>.delayed(Duration(seconds: interval));

      final response = await http.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: const {
          'Accept': 'application/json',
        },
        body: {
          'client_id': clientId,
          'device_code': login.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = data['access_token']?.toString() ?? '';
      if (accessToken.isNotEmpty) {
        await _saveTokens(data);
        final account = await _loadAccountFromApi(accessToken);
        await _storage.write(key: _loginKey, value: account.login);
        return account;
      }

      switch (data['error']?.toString()) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        case 'expired_token':
          throw StateError('The GitHub authorization code expired.');
        case 'access_denied':
          throw StateError('GitHub authorization was cancelled.');
        case 'device_flow_disabled':
          throw StateError('Device authorization is disabled for this GitHub App.');
        default:
          throw StateError(
            data['error_description']?.toString() ??
                data['error']?.toString() ??
                'GitHub authorization failed.',
          );
      }
    }

    throw StateError('The GitHub authorization code expired.');
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    final now = DateTime.now();
    final accessToken = data['access_token']?.toString() ?? '';
    final refreshToken = data['refresh_token']?.toString() ?? '';
    final expiresIn = (data['expires_in'] as num?)?.toInt();
    final refreshExpiresIn = (data['refresh_token_expires_in'] as num?)?.toInt();

    await _storage.write(key: _accessTokenKey, value: accessToken);

    if (refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    } else {
      await _storage.delete(key: _refreshTokenKey);
    }

    if (expiresIn != null) {
      await _storage.write(
        key: _expiresAtKey,
        value: now.add(Duration(seconds: expiresIn)).toIso8601String(),
      );
    } else {
      await _storage.delete(key: _expiresAtKey);
    }

    if (refreshExpiresIn != null) {
      await _storage.write(
        key: _refreshExpiresAtKey,
        value:
            now.add(Duration(seconds: refreshExpiresIn)).toIso8601String(),
      );
    } else {
      await _storage.delete(key: _refreshExpiresAtKey);
    }
  }

  Future<String?> accessToken() async {
    var token = await _storage.read(key: _accessTokenKey);
    if (token == null || token.isEmpty) return null;

    final expiresRaw = await _storage.read(key: _expiresAtKey);
    final expiresAt =
        expiresRaw == null ? null : DateTime.tryParse(expiresRaw);

    if (expiresAt != null &&
        expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
      token = await _refreshAccessToken();
    }

    return token;
  }

  Future<String?> _refreshAccessToken() async {
    if (!appConfigured) return null;

    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      await disconnect();
      return null;
    }

    final refreshExpiryRaw =
        await _storage.read(key: _refreshExpiresAtKey);
    final refreshExpiry = refreshExpiryRaw == null
        ? null
        : DateTime.tryParse(refreshExpiryRaw);
    if (refreshExpiry != null &&
        refreshExpiry.isBefore(DateTime.now())) {
      await disconnect();
      return null;
    }

    final response = await http.post(
      Uri.parse('https://github.com/login/oauth/access_token'),
      headers: const {
        'Accept': 'application/json',
      },
      body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await disconnect();
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token']?.toString() ?? '';
    if (token.isEmpty) {
      await disconnect();
      return null;
    }

    await _saveTokens(data);
    return token;
  }

  Future<GitHubAccount?> account() async {
    final token = await accessToken();
    if (token == null) return null;

    final cached = await _storage.read(key: _loginKey);
    if (cached != null && cached.isNotEmpty) {
      return GitHubAccount(login: cached, connected: true);
    }

    final account = await _loadAccountFromApi(token);
    await _storage.write(key: _loginKey, value: account.login);
    return account;
  }

  Future<GitHubAccount> _loadAccountFromApi(String token) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: _headers(token),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'GitHub account lookup failed with HTTP ${response.statusCode}.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final login = data['login']?.toString() ?? '';
    if (login.isEmpty) {
      throw StateError('GitHub account did not include a login.');
    }

    return GitHubAccount(login: login, connected: true);
  }

  Map<String, String> _headers(String token) => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $token',
        'X-GitHub-Api-Version': _apiVersion,
        'User-Agent': 'Nexus-Android',
      };

  Future<void> disconnect() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
    await _storage.delete(key: _refreshExpiresAtKey);
    await _storage.delete(key: _loginKey);
  }
}
