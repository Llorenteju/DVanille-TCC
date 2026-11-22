import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/reserva.dart';
import 'auth_api_service.dart' show DVanilleApiException;
import 'auth_client_stub.dart'
    if (dart.library.js_interop) 'auth_client_web.dart' as plataforma;

/// Reserva usando a API PostgreSQL; nunca consulta reservas por e-mail.
/// No Flutter Web, usa o cookie HttpOnly da sessão autenticada.
/// Requer backend no mesmo endereço configurado por DVANILLE_API_URL.
class ReservaApiService {
  static final ReservaApiService instance = ReservaApiService._();

  static const String _baseUrl = String.fromEnvironment(
    'DVANILLE_API_URL',
    defaultValue: 'http://localhost:3000/api',
  );
  final http.Client _client = plataforma.criarClienteAuth();

  ReservaApiService._();

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse('${_baseUrl.replaceAll(RegExp(r"/$"), "")}$path');
    late final http.Response response;
    try {
      final request = http.Request(method, url)
        ..headers['Accept'] = 'application/json'
        ..headers['Content-Type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request)
          .timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const DVanilleApiException('A API demorou para responder. Tente novamente.');
    } catch (error) {
      if (error is DVanilleApiException) rethrow;
      throw const DVanilleApiException(
        'Não foi possível acessar as reservas. Confira se o backend está ligado na porta 3001.',
      );
    }

    Map<String, dynamic> result;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) throw const FormatException();
      result = Map<String, dynamic>.from(json);
    } catch (_) {
      throw DVanilleApiException('Resposta inesperada da API de reservas.',
          statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300 || result['success'] != true) {
      throw DVanilleApiException(
        result['message']?.toString() ?? 'Não foi possível completar a solicitação.',
        statusCode: response.statusCode,
      );
    }
    return result;
  }

  Reserva _readReserva(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) throw const DVanilleApiException('Reserva não encontrada na resposta da API.');
    return Reserva.fromApi(Map<String, dynamic>.from(data));
  }

  Future<Reserva> criar({
    required String nome,
    required String email,
    required String telefone,
    required String data,
    required String horario,
    required int pessoas,
    required String preferencias,
    required String observacoes,
  }) async {
    final response = await _request('POST', '/reservations', body: {
      'name': nome,
      'email': email,
      'phone': telefone,
      'reservationDate': data,
      'reservationTime': horario,
      'guests': pessoas,
      'preferences': preferencias,
      'notes': observacoes,
    });
    return _readReserva(response);
  }

  Future<List<Reserva>> _listAll(String path) async {
    final reservas = <Reserva>[];
    for (var pagina = 1; pagina <= 100; pagina++) {
      final response = await _request('GET', '$path?page=$pagina&limit=100');
      final data = response['data'];
      if (data is! List) {
        throw const DVanilleApiException('A listagem de reservas veio em formato inesperado.');
      }
      reservas.addAll(data.map((item) {
        if (item is! Map) throw const DVanilleApiException('Reserva inválida na listagem.');
        return Reserva.fromApi(Map<String, dynamic>.from(item));
      }));
      final pag = response['pagination'];
      final totalPaginas = pag is Map ? (pag['totalPages'] as num?)?.toInt() : null;
      if (data.length < 100 || (totalPaginas != null && pagina >= totalPaginas)) {
        return reservas;
      }
    }
    throw const DVanilleApiException('Há muitas reservas. Não foi possível carregar o histórico completo.');
  }

  Future<List<Reserva>> listarMinhas() => _listAll('/reservations/me');
  Future<List<Reserva>> listarAdmin() => _listAll('/admin/reservations');

  Future<Reserva> cancelarMinha(String id) async {
    final response = await _request('PATCH', '/reservations/${Uri.encodeComponent(id)}/cancel');
    return _readReserva(response);
  }

  Future<Reserva> alterarStatusAdmin(String id, String status) async {
    final response = await _request(
      'PATCH',
      '/admin/reservations/${Uri.encodeComponent(id)}/status',
      body: {'status': status},
    );
    return _readReserva(response);
  }
}
