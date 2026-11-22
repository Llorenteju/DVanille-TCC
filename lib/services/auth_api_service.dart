import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'auth_client_stub.dart'
    if (dart.library.js_interop) 'auth_client_web.dart' as plataforma;

/// Erro retornado pelo backend ou ao tentar acessar a API.
class DVanilleApiException implements Exception {
  final String message;
  final int? statusCode;

  const DVanilleApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Dados públicos enviados pelo backend (nunca contém a senha).
class AuthUser {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String role;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
  });

  bool get isAdmin => role.toUpperCase() == 'ADMIN';

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! num) {
      throw const DVanilleApiException(
          'A API retornou um usuário sem ID válido.');
    }

    return AuthUser(
      id: id.toInt(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      role: (json['role'] ?? 'CUSTOMER').toString(),
    );
  }
}

class AuthSession {
  final AuthUser user;
  final String token;
  final String tokenType;
  final String expiresIn;

  const AuthSession({
    required this.user,
    required this.token,
    required this.tokenType,
    required this.expiresIn,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    final token = json['token'];
    if (userJson is! Map || token is! String || token.isEmpty) {
      throw const DVanilleApiException(
        'A API retornou uma resposta de autenticação incompleta.',
      );
    }

    return AuthSession(
      user: AuthUser.fromJson(Map<String, dynamic>.from(userJson)),
      token: token,
      tokenType: (json['tokenType'] ?? 'Bearer').toString(),
      expiresIn: (json['expiresIn'] ?? '').toString(),
    );
  }
}

/// Serviço de autenticação para o backend Node.js da D'Vanille.
///
/// Por padrão, acessa a API local pela porta 3000. Quando o backend estiver
/// hospedado, utilize --dart-define=DVANILLE_API_URL=https://.../api.
///
/// O token continua somente na memória. No Web, a API administra um
/// cookie HttpOnly que é enviado automaticamente pelo navegador.
/// Não armazenar senhas nem JWT em SharedPreferences/localStorage.
class AuthApiService {
  static const String defaultBaseUrl = String.fromEnvironment(
    'DVANILLE_API_URL',
    defaultValue: 'http://localhost:3000/api',
  );

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  AuthSession? _session;
  AuthUser? _usuarioCookie;

  AuthApiService({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/$'), ''),
        _client = client ?? plataforma.criarClienteAuth(),
        _ownsClient = client == null;

  AuthSession? get session => _session;
  AuthUser? get currentUser => _session?.user ?? _usuarioCookie;
  bool get isAuthenticated => _session != null || _usuarioCookie != null;

  /// Login: POST /api/auth/login
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final body = await _send(
      'POST',
      '/auth/login',
      data: {
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );

    final session = _readSession(body);
    _session = session;
    _usuarioCookie = session.user;
    return session;
  }

  /// Cadastro: POST /api/auth/register.
  /// Os demais campos do formulário (nascimento, restrições, notificações)
  /// ainda não existem na API e precisam ser implementados no backend.
  Future<AuthSession> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final body = await _send(
      'POST',
      '/auth/register',
      data: {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'password': password,
      },
    );

    final session = _readSession(body);
    _session = session;
    _usuarioCookie = session.user;
    return session;
  }

  /// Recupera a sessão do cookie HttpOnly após F5, sem guardar JWT no Web.
  /// Retorna null se a sessão expirou ou foi encerrada.
  Future<AuthUser?> restaurarSessao() async {
    if (_session != null) return _session!.user;
    try {
      final body = await _send('GET', '/auth/me');
      final data = body['data'];
      if (data is! Map) {
        throw const DVanilleApiException(
            'Resposta inválida ao restaurar sessão.');
      }
      final usuario = AuthUser.fromJson(Map<String, dynamic>.from(data));
      _usuarioCookie = usuario;
      return usuario;
    } on DVanilleApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        _usuarioCookie = null;
        return null;
      }
      rethrow;
    }
  }

  /// Confirma a sessão com o backend: GET /api/auth/me.
  Future<AuthUser> me() async {
    final body = await _send('GET', '/auth/me', requireAuth: true);
    final data = body['data'];
    if (data is! Map) {
      throw const DVanilleApiException(
          'Resposta inválida ao consultar perfil.');
    }
    return AuthUser.fromJson(Map<String, dynamic>.from(data));
  }

  /// Encerra a sessão no servidor e remove o token da memória.
  Future<void> logout() async {
    try {
      if (isAuthenticated) {
        await _send('POST', '/auth/logout', requireAuth: true);
      }
    } finally {
      _session = null;
      _usuarioCookie = null;
    }
  }

  /// Útil ao receber 401/403 de uma sessão já expirada.
  void clearLocalSession() {
    _session = null;
    _usuarioCookie = null;
  }

  AuthSession _readSession(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! Map) {
      throw const DVanilleApiException('Resposta inválida da autenticação.');
    }
    return AuthSession.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    bool requireAuth = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (requireAuth) {
      final token = _session?.token;
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else if (_usuarioCookie == null) {
        throw const DVanilleApiException('Faça login para continuar.',
            statusCode: 401);
      }
      // Sem Bearer no navegador após F5: cookie HttpOnly enviado pelo BrowserClient.
    }

    late final http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (data != null) request.body = jsonEncode(data);
      final streamed =
          await _client.send(request).timeout(const Duration(seconds: 15));
      response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const DVanilleApiException(
          'A API demorou para responder. Tente novamente.');
    } on DVanilleApiException {
      rethrow;
    } catch (_) {
      throw const DVanilleApiException(
        'Não foi possível conectar à API. Confira se o Docker está funcionando e se o site usa a porta 8080.',
      );
    }

    Map<String, dynamic> body;
    try {
      final parsed = jsonDecode(utf8.decode(response.bodyBytes));
      if (parsed is! Map) throw const FormatException();
      body = Map<String, dynamic>.from(parsed);
    } catch (_) {
      throw DVanilleApiException(
        'A API respondeu em um formato inesperado.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['success'] != true) {
      final message = body['message']?.toString() ?? 'Falha ao acessar a API.';
      throw DVanilleApiException(message, statusCode: response.statusCode);
    }
    return body;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
