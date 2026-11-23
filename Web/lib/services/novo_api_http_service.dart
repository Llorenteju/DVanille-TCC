import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'auth_client_stub.dart'
    if (dart.library.js_interop) 'auth_client_web.dart' as plataforma;

/// Cliente compartilhado para os novos módulos.
/// No Web envia o cookie HttpOnly da sessão; nunca usa localStorage para JWT.
class NovoApiHttpService {
  static final NovoApiHttpService instance = NovoApiHttpService._();

  static const String _base = String.fromEnvironment(
    'DVANILLE_API_URL', defaultValue: 'http://localhost:3001/api',
  );
  final http.Client _client = plataforma.criarClienteAuth();

  NovoApiHttpService._();

  Future<dynamic> request(String method, String endpoint, {Object? body}) async {
    final uri = Uri.parse('${_base.replaceFirst(RegExp(r"/$"), "")}$endpoint');
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    late http.Response response;
    try {
      final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw StateError('A API demorou para responder. Confira a conexão.');
    } catch (_) {
      throw StateError('Não foi possível conectar ao backend.');
    }
    Map<String, dynamic> parsed;
    try {
      parsed = Map<String, dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
    } catch (_) {
      throw StateError('Resposta inválida da API (HTTP ${response.statusCode}).');
    }
    if (response.statusCode < 200 || response.statusCode >= 300 || parsed['success'] != true) {
      throw StateError((parsed['message'] ?? 'Erro ao comunicar com a API.').toString());
    }
    return parsed['data'];
  }
}
