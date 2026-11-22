import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

/// Indicadores reais retornados por GET /api/admin/dashboard.
class AdminDashboardDados {
  final int totalUsuarios;
  final int totalProdutos;
  final int produtosEstoqueBaixo;
  final int totalPedidos;
  final int pedidosPendentes;
  final int pedidosEmAndamento;
  final int pedidosFinalizados;
  final int pedidosCancelados;
  final double faturamento;
  final List<AdminDashboardPedidoRecente> pedidosRecentes;

  const AdminDashboardDados({
    required this.totalUsuarios,
    required this.totalProdutos,
    required this.produtosEstoqueBaixo,
    required this.totalPedidos,
    required this.pedidosPendentes,
    required this.pedidosEmAndamento,
    required this.pedidosFinalizados,
    required this.pedidosCancelados,
    required this.faturamento,
    required this.pedidosRecentes,
  });

  factory AdminDashboardDados.fromJson(Map<String, dynamic> json) {
    final users = _map(json['users']);
    final products = _map(json['products']);
    final orders = _map(json['orders']);
    final recentes = json['recentOrders'];

    return AdminDashboardDados(
      totalUsuarios: _inteiro(users['total']),
      totalProdutos: _inteiro(products['total']),
      produtosEstoqueBaixo: _inteiro(products['lowStock']),
      totalPedidos: _inteiro(orders['total']),
      pedidosPendentes: _inteiro(orders['pending']),
      pedidosEmAndamento: _inteiro(orders['inProgress']),
      pedidosFinalizados: _inteiro(orders['completed']),
      pedidosCancelados: _inteiro(orders['cancelled']),
      faturamento: _decimal(json['revenue']),
      pedidosRecentes: recentes is List
          ? recentes
              .whereType<Map>()
              .map((item) => AdminDashboardPedidoRecente.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

class AdminDashboardPedidoRecente {
  final String numero;
  final String cliente;
  final double total;

  const AdminDashboardPedidoRecente({
    required this.numero,
    required this.cliente,
    required this.total,
  });

  factory AdminDashboardPedidoRecente.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    final id = json['id']?.toString() ?? '';
    final numero = (json['orderNumber'] ?? '').toString().trim();
    final email = (json['customerEmail'] ??
            json['userEmail'] ??
            user['email'] ??
            '')
        .toString()
        .trim();
    final nome = (json['customerName'] ?? user['name'] ?? '').toString().trim();
    final userId = json['userId']?.toString() ?? '';

    return AdminDashboardPedidoRecente(
      numero: numero.isNotEmpty ? numero : (id.isNotEmpty ? '#$id' : 'Pedido'),
      cliente: email.isNotEmpty
          ? email
          : nome.isNotEmpty
              ? nome
              : (userId.isNotEmpty ? 'Cliente #$userId' : 'Cliente'),
      total: _decimal(json['total']),
    );
  }
}

Map<String, dynamic> _map(dynamic valor) =>
    valor is Map ? Map<String, dynamic>.from(valor) : <String, dynamic>{};

int _inteiro(dynamic valor) =>
    valor is num ? valor.toInt() : int.tryParse(valor?.toString() ?? '') ?? 0;

double _decimal(dynamic valor) => valor is num
    ? valor.toDouble()
    : double.tryParse(valor?.toString() ?? '') ?? 0.0;

class AdminDashboardApiException implements Exception {
  final String mensagem;
  final int? statusCode;

  const AdminDashboardApiException(this.mensagem, {this.statusCode});

  @override
  String toString() => mensagem;
}

/// Web: utiliza o cookie HttpOnly já estabelecido pelo login.
/// Não lê, armazena nem envia o JWT manualmente.
class AdminDashboardApiService {
  static const String defaultBaseUrl = String.fromEnvironment(
    'DVANILLE_API_URL',
    defaultValue: 'http://localhost:3001/api',
  );

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  AdminDashboardApiService({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ?? defaultBaseUrl).replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? (BrowserClient()..withCredentials = true),
        _ownsClient = client == null;

  Future<AdminDashboardDados> carregar() async {
    late http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$baseUrl/admin/dashboard'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const AdminDashboardApiException('A API demorou para responder.');
    } catch (_) {
      throw const AdminDashboardApiException(
        'Não foi possível conectar ao backend. Confira a porta 3001.',
      );
    }

    late Map<String, dynamic> body;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) throw const FormatException();
      body = Map<String, dynamic>.from(json);
    } catch (_) {
      throw AdminDashboardApiException(
        'A API respondeu em um formato inesperado.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300 ||
        body['success'] != true) {
      throw AdminDashboardApiException(
        body['message']?.toString() ?? 'Não foi possível carregar o Dashboard.',
        statusCode: response.statusCode,
      );
    }

    if (body['data'] is! Map) {
      throw const AdminDashboardApiException(
        'A resposta do Dashboard não contém os indicadores esperados.',
      );
    }

    return AdminDashboardDados.fromJson(
      Map<String, dynamic>.from(body['data'] as Map),
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
