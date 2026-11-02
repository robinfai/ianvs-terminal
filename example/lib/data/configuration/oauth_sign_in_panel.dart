import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../ui/app_ui.dart';
import '../services/data_api_client.dart';
import '../services/data_api_device_identity.dart';
import 'data_api_configuration.dart';
import 'data_api_configuration_repository.dart';

/// Inline account choice: identities are never joined using email addresses.
class OAuthSignInPanel extends StatefulWidget {
  const OAuthSignInPanel({
    required this.baseUri,
    this.onAuthenticated,
    this.accountManager,
    this.onBusyChanged,
    super.key,
  });
  final DataApiOAuthAccountManager? accountManager;
  final ValueChanged<bool>? onBusyChanged;
  final Uri baseUri;
  final Future<void> Function(DataApiRemoteLoginRequest request)?
  onAuthenticated;
  @override
  State<OAuthSignInPanel> createState() => _OAuthSignInPanelState();
}

class _OAuthSignInPanelState extends State<OAuthSignInPanel> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  Map<String, Object?>? _proof;
  bool _busy = false;
  bool _linking = false;
  bool _needsChoice = false;
  bool _passwordLink = false;
  bool _capacity = false;
  bool _replaceOldest = false;
  String? _error;
  DataApiClient get _client => DataApiClient(
    baseUri: widget.baseUri,
    accessToken: null,
    encryptionKey: null,
  );
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String _text(String zh, String en) => _zh ? zh : en;

  List<String>? _linkedProviders;
  @override
  void initState() {
    super.initState();
    if (widget.accountManager != null) unawaited(_loadLinkedProviders());
  }

  Future<void> _loadLinkedProviders() async {
    try {
      final providers = await widget.accountManager!.linkedOAuthProviders();
      if (mounted) {
        setState(() {
          _linkedProviders = providers;
          _error = null;
        });
      }
    } on Object catch (_) {
      if (mounted) setState(() => _error = '无法读取登录方式，请重试。');
    }
  }

  Future<void> _linkCurrentAccount(String provider) => _run(() async {
    final proof = await _identity(provider);
    if (!mounted) return;
    await widget.accountManager!.linkOAuthIdentity(proof);
    await _loadLinkedProviders();
  });

  Future<Map<String, Object?>> _identity(String provider) async {
    final nonce = await _client.createOAuthChallenge();
    String? token;
    if (provider == 'apple') {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [],
        nonce: nonce,
      );
      token = credential.identityToken;
    } else {
      final config = await _client.oauthConfiguration();
      final key = defaultTargetPlatform == TargetPlatform.macOS
          ? 'google_macos_client_id'
          : 'google_ios_client_id';
      final clientID = config[key] as String?;
      if (clientID == null ||
          !clientID.endsWith('.apps.googleusercontent.com')) {
        throw StateError(
          _text(
            '此服务尚未启用 Google 登录。',
            'Google sign-in is not enabled on this service.',
          ),
        );
      }
      final scheme = clientID.split('.').reversed.join('.');
      final response = await const FlutterAppAuth().authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientID,
          '$scheme:/oauthredirect',
          discoveryUrl:
              'https://accounts.google.com/.well-known/openid-configuration',
          scopes: const ['openid', 'email', 'profile'],
          nonce: nonce,
          promptValues: const ['select_account'],
        ),
      );
      token = response.idToken;
    }
    if (token == null || token.isEmpty) {
      throw StateError(
        _text('未获取到登录凭据，请重试。', 'No identity token received. Please retry.'),
      );
    }
    return {'provider': provider, 'identity_token': token, 'nonce': nonce};
  }

  Future<void> _signIn(String provider) => _run(() async {
    _proof = await _identity(provider);
    if (!mounted) return;
    await _submit();
  });

  Future<void> _submit({String action = '', String? linkProvider}) async {
    final proof = _proof;
    if (proof == null || !mounted) return;
    final operation = await _client.beginOAuthLogin({
      ...proof,
      'action': action,
      'device_id': await dataApiDeviceIdentity(widget.baseUri),
      'replace_oldest': _replaceOldest,
      if (action == 'link' && linkProvider == null) ...{
        'username': _username.text.trim(),
        'password': _password.text,
      },
      if (linkProvider != null) 'link': await _identity(linkProvider),
    });
    if (!mounted) {
      await _client.cancelAuthOperation(operation.operationId);
      return;
    }
    try {
      await widget.onAuthenticated!(
        DataApiRemoteLoginRequest.oauth(
          baseUri: widget.baseUri,
          operation: operation,
        ),
      );
    } on Object catch (_) {
      // A prepared operation must not occupy a slot when local persistence fails.
      try {
        await _client.cancelAuthOperation(operation.operationId);
      } on Object catch (_) {}
      _proof = null;
      _needsChoice = false;
      rethrow;
    }
    if (!mounted) return;
    _proof = null;
    _needsChoice = false;
    _password.clear();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      await action();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        _error = _text(
          'Apple 登录未完成，请重试。',
          'Apple sign-in failed. Please retry.',
        );
      }
    } on FlutterAppAuthUserCancelledException {
      /* Keep the current step. */
    } on DataApiRequestException catch (e) {
      if (e.code == 'oauth_account_choice_required') {
        _needsChoice = true;
        _linking = false;
      } else {
        _capacity = e.code == 'auth_session_capacity';
        _error = switch (e.code) {
          'oauth_historical_account_missing' => _text(
            '该登录方式尚无历史账号，请选择其他方式或创建新账号。',
            'No existing account for this identity. Choose another method or create an account.',
          ),
          'invalid_credentials' => _text(
            '账号或密码不正确。',
            'Incorrect username or password.',
          ),
          'apple_link_conflict' => _text(
            '该身份已关联其他账号，无法再次关联。',
            'This identity is already linked to another account.',
          ),
          'auth_session_capacity' => _text(
            '登录会话已满，可选择退出最早的会话后重试。',
            'Session limit reached. You can replace the oldest session and retry.',
          ),
          'apple_registration_disabled' => _text(
            '此服务未开放注册，请关联历史账号。',
            'Registration is disabled. Link an existing account.',
          ),
          'invalid_apple_identity' => _text(
            '身份验证已过期，请返回并重新登录。',
            'Verification expired. Go back and sign in again.',
          ),
          _ => _text(
            '登录未完成，请检查网络后重试。',
            'Sign-in failed. Check the connection and retry.',
          ),
        };
      }
    } on Object catch (e) {
      _error = displayDataServiceMessage(e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proof = _proof;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.accountManager != null) ...[
          if (_linkedProviders == null && _error == null)
            const LinearProgressIndicator(),
          if (_linkedProviders != null)
            for (final provider in ['apple', 'google']) ...[
              if (_linkedProviders!.contains(provider))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '${provider == 'apple' ? 'Apple' : 'Google'} · ${_text('已关联', 'Linked')}',
                  ),
                )
              else
                OutlinedButton(
                  onPressed: _busy ? null : () => _linkCurrentAccount(provider),
                  child: Text(
                    '${_text('关联', 'Link')} ${provider == 'apple' ? 'Apple' : 'Google'}',
                  ),
                ),
              const SizedBox(height: 8),
            ],
          if (_linkedProviders == null && _error != null)
            TextButton(
              onPressed: _busy ? null : _loadLinkedProviders,
              child: Text(_text('重试', 'Retry')),
            ),
        ] else if (proof == null || !_needsChoice) ...[
          SignInWithAppleButton(
            onPressed: () {
              if (!_busy) unawaited(_signIn('apple'));
            },
            text: context.l10n.appleSignIn,
            style: Theme.of(context).brightness == Brightness.dark
                ? SignInWithAppleButtonStyle.white
                : SignInWithAppleButtonStyle.black,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : () => _signIn('google'),
            child: Text(_text('使用 Google 登录', 'Sign in with Google')),
          ),
        ] else ...[
          Text(
            _text(
              _linking ? '关联历史账号' : '首次登录',
              _linking ? 'Link an existing account' : 'First sign-in',
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (!_linking) ...[
            FilledButton(
              onPressed: _busy ? null : () => setState(() => _linking = true),
              child: Text(_text('关联历史账号', 'Link an existing account')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => _submit(action: 'create')),
              child: Text(_text('创建新账号', 'Create a new account')),
            ),
          ] else ...[
            if (!_passwordLink) ...[
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _submit(
                          action: 'link',
                          linkProvider: proof['provider'] == 'apple'
                              ? 'google'
                              : 'apple',
                        ),
                      ),
                child: Text(
                  proof['provider'] == 'apple'
                      ? _text('使用 Google 关联', 'Link with Google')
                      : _text('使用 Apple 关联', 'Link with Apple'),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _passwordLink = true),
                child: Text(
                  _text('使用账号密码关联', 'Link with username and password'),
                ),
              ),
            ] else ...[
              TextField(
                controller: _username,
                enabled: !_busy,
                decoration: InputDecoration(labelText: context.l10n.username),
                autocorrect: false,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(labelText: context.l10n.password),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => _submit(action: 'link')),
                child: Text(_text('验证并关联', 'Verify and link')),
              ),
            ],
          ],
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _proof = null;
                    _needsChoice = false;
                    _linking = false;
                    _passwordLink = false;
                    _error = null;
                    _password.clear();
                  }),
            child: Text(_text('返回', 'Back')),
          ),
        ],
        if (_capacity)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_text('退出最早的一个会话', 'Sign out the oldest session')),
            value: _replaceOldest,
            onChanged: _busy
                ? null
                : (v) => setState(() => _replaceOldest = v ?? false),
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
