import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Erro da API: a interface deve mostrar esta mensagem e NÃO fingir sucesso.
class MobileApiException implements Exception {
  final String message;
  final int? statusCode;

  const MobileApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Cliente HTTP do aplicativo MOBILE. Não é utilizado pelo site público.
///
/// Android Emulator: http://10.0.2.2:3001/api
/// Flutter Web de teste: http://localhost:3001/api (via --dart-define)
/// Celular físico: use endereço LAN acessível e backend vinculado à rede.
/// Produção: use exclusivamente HTTPS.
///
/// JWT guardado somente em memória nesta versão; nunca em arquivo .env do app.
class MobileApiService {
  static const baseUrl = String.fromEnvironment(
    'DVANILLE_API_URL',
    defaultValue: 'http://10.0.2.2:3001/api',
  );

  MobileApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _token;

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  void setToken(String token) {
    if (token.isEmpty) {
      throw const MobileApiException('A API não retornou uma sessão válida.');
    }
    _token = token;
  }

  void clearToken() => _token = null;

  Uri get _base => Uri.parse(baseUrl.replaceAll(RegExp(r'/$'), ''));

  /// Converte uma imagem do backend para URL completa; não altera assets locais.
  String imageUrl(String image) {
    if (image.isEmpty || image.startsWith('assets/') || image.startsWith('http://') || image.startsWith('https://')) {
      return image;
    }
    final server = _base.replace(path: '', query: '', fragment: '');
    return server.resolve(image.startsWith('/') ? image : '/$image').toString();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    bool auth = true,
  }) async {
    if (auth && !isAuthenticated) {
      throw const MobileApiException('Entre na sua conta para continuar.', statusCode: 401);
    }
    final request = http.Request(method, Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path'));
    request.headers['Accept'] = 'application/json';
    request.headers['Content-Type'] = 'application/json';
    if (auth) request.headers['Authorization'] = 'Bearer $_token';
    if (data != null) request.body = jsonEncode(data);

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const MobileApiException('A API demorou para responder. Verifique a conexão.');
    } catch (error) {
      if (error is MobileApiException) rethrow;
      throw const MobileApiException('Não foi possível acessar a API. Confira o Docker e o endereço DVANILLE_API_URL.');
    }

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw MobileApiException('Resposta inválida da API (HTTP ${response.statusCode}).', statusCode: response.statusCode);
    }

    if (response.statusCode < 200 || response.statusCode >= 300 || body['success'] != true) {
      throw MobileApiException(
        (body['message'] ?? 'A operação não foi concluída.').toString(),
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) => request('GET', path, auth: auth);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data, {bool auth = true}) => request('POST', path, data: data, auth: auth);
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> data) => request('PATCH', path, data: data);
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> data) => request('PUT', path, data: data);
  Future<Map<String, dynamic>> delete(String path) => request('DELETE', path);

  void dispose() => _client.close();
}
