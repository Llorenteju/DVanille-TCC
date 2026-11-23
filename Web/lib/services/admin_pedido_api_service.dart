import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_api_service.dart' show DVanilleApiException;
import 'auth_client_stub.dart'
    if (dart.library.js_interop) 'auth_client_web.dart' as plataforma;

/// Representa um pedido real retornado pela API do backend.
/// Nunca utiliza a lista de pedidos fictícios de AppState.
class PedidoAdminApi {
  final int apiId;
  final String id;
  final String clienteEmail;
  final String clienteNome;
  final List<ItemPedidoAdminApi> itens;
  final double total;
  final DateTime criadoEm;
  final String statusApi;
  final String modalidade;
  final String metodoPagamento;
  final String statusPagamento;
  final List<String> proximosStatusApi;

  const PedidoAdminApi({
    required this.apiId,
    required this.id,
    required this.clienteEmail,
    required this.clienteNome,
    required this.itens,
    required this.total,
    required this.criadoEm,
    required this.statusApi,
    required this.modalidade,
    required this.metodoPagamento,
    required this.statusPagamento,
    required this.proximosStatusApi,
  });

  static double _num(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  static String nomeStatusApi(String status) => switch (status) {
        'PENDING' => 'Recebido',
        'CONFIRMED' => 'Confirmado',
        'PREPARING' => 'Em preparação',
        'READY' => 'Pronto',
        'OUT_FOR_DELIVERY' => 'Saiu para entrega',
        'DELIVERED' => 'Finalizado',
        'CANCELLED' => 'Cancelado',
        _ => status,
      };

  /// Status na nomenclatura usada no layout original do painel Web.
  String get status => nomeStatusApi(statusApi).toLowerCase();

  String get data {
    final local = criadoEm.toLocal();
    String dois(int x) => x.toString().padLeft(2, '0');
    return '${dois(local.day)}/${dois(local.month)}/${local.year} '
        '${dois(local.hour)}:${dois(local.minute)}';
  }

  String get resumoItens => itens.isEmpty
      ? 'Itens não informados'
      : itens.map((i) => '${i.qtd}x ${i.nome}').join(', ');

  String get modalidadeDescricao => modalidade == 'DELIVERY' ? 'Delivery' : 'Retirada na loja';

  factory PedidoAdminApi.fromJson(Map<String, dynamic> json) {
    final usuario = json['user'];
    final user = usuario is Map ? Map<String, dynamic>.from(usuario) : <String, dynamic>{};
    final rawItens = json['items'];
    final listaItens = rawItens is List
        ? rawItens.whereType<Map>().map((item) => ItemPedidoAdminApi.fromJson(
              Map<String, dynamic>.from(item),
            )).toList(growable: false)
        : <ItemPedidoAdminApi>[];
    final rawProximos = json['allowedNextStatuses'];
    final proximos = rawProximos is List
        ? rawProximos.whereType<String>().toList(growable: false)
        : <String>[];
    final idInt = json['id'];
    if (idInt is! num) throw const DVanilleApiException('Pedido recebido sem ID numérico.');
    final numero = json['orderNumber']?.toString() ?? '';
    if (numero.isEmpty) throw const DVanilleApiException('Pedido recebido sem número.');

    return PedidoAdminApi(
      apiId: idInt.toInt(),
      id: numero,
      clienteEmail: user['email']?.toString() ?? '',
      clienteNome: user['name']?.toString() ?? '',
      itens: listaItens,
      total: _num(json['total']),
      criadoEm: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      statusApi: json['orderStatus']?.toString() ?? 'PENDING',
      modalidade: json['deliveryType']?.toString() ?? 'PICKUP',
      metodoPagamento: json['paymentMethod']?.toString() ?? '',
      statusPagamento: json['paymentStatus']?.toString() ?? '',
      proximosStatusApi: proximos,
    );
  }
}

class ItemPedidoAdminApi {
  final String nome;
  final int qtd;
  final double preco;

  const ItemPedidoAdminApi({
    required this.nome,
    required this.qtd,
    required this.preco,
  });

  factory ItemPedidoAdminApi.fromJson(Map<String, dynamic> json) => ItemPedidoAdminApi(
        nome: json['productName']?.toString() ?? 'Produto',
        qtd: (json['quantity'] as num?)?.toInt() ?? 0,
        preco: PedidoAdminApi._num(json['unitPrice']),
      );
}

/// Cliente HTTP com cookie HttpOnly do Web, igual ao usado nas reservas.
/// As rotas do servidor exigem sessão ADMIN autenticada.
class AdminPedidoApiService {
  static final AdminPedidoApiService instance = AdminPedidoApiService._();

  static const String _baseUrl = String.fromEnvironment(
    'DVANILLE_API_URL',
    defaultValue: 'http://localhost:3000/api',
  );
  final http.Client _client = plataforma.criarClienteAuth();

  AdminPedidoApiService._();

  Future<Map<String, dynamic>> _request(String method, String path, {Map<String, dynamic>? body}) async {
    final url = Uri.parse('${_baseUrl.replaceAll(RegExp(r"/$"), "")}$path');
    late final http.Response response;
    try {
      final request = http.Request(method, url)
        ..headers['Accept'] = 'application/json'
        ..headers['Content-Type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const DVanilleApiException('A API demorou para responder. Atualize e tente novamente.');
    } catch (erro) {
      if (erro is DVanilleApiException) rethrow;
      throw const DVanilleApiException('Falha de conexão com os pedidos. Confira se o backend está ligado.');
    }

    Map<String, dynamic> resultado;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      resultado = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw DVanilleApiException('A API respondeu em um formato inesperado.', statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300 || resultado['success'] != true) {
      throw DVanilleApiException(
        resultado['message']?.toString() ?? 'Não foi possível consultar os pedidos.',
        statusCode: response.statusCode,
      );
    }
    return resultado;
  }

  Future<List<PedidoAdminApi>> listarTodos() async {
    final pedidos = <PedidoAdminApi>[];
    // A API pagina a listagem. Lemos todas as páginas necessárias.
    for (var pagina = 1; pagina <= 100; pagina++) {
      final resposta = await _request('GET', '/admin/orders?page=$pagina&limit=100');
      final dados = resposta['data'];
      if (dados is! List) {
        throw const DVanilleApiException('A listagem de pedidos veio em formato inválido.');
      }
      for (final item in dados) {
        if (item is! Map) throw const DVanilleApiException('Pedido inválido na resposta da API.');
        pedidos.add(PedidoAdminApi.fromJson(Map<String, dynamic>.from(item)));
      }
      final paginacao = resposta['pagination'];
      final totalPaginas = paginacao is Map ? (paginacao['totalPages'] as num?)?.toInt() : null;
      if (dados.length < 100 || (totalPaginas != null && pagina >= totalPaginas)) return pedidos;
    }
    throw const DVanilleApiException('Existem muitos pedidos para carregar de uma vez.');
  }

  Future<void> atualizarStatus(PedidoAdminApi pedido, String novoStatus) async {
    if (!pedido.proximosStatusApi.contains(novoStatus)) {
      throw const DVanilleApiException('Essa mudança de status não é permitida pelo backend.');
    }
    await _request(
      'PATCH',
      '/admin/orders/${pedido.apiId}/status',
      body: {'status': novoStatus},
    );
  }
}
