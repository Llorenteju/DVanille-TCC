import 'novo_api_http_service.dart';

class PedidoMesaApi {
  final String id, mesa, status, compradorEmail;
  final String? cupom;
  final double total, desconto;
  final DateTime criadoEm;
  final List<ItemMesaApi> itens;

  const PedidoMesaApi({required this.id, required this.mesa, required this.status,
    required this.compradorEmail, required this.total, required this.desconto,
    required this.criadoEm, required this.itens, this.cupom});

  factory PedidoMesaApi.fromJson(Map<String, dynamic> json) => PedidoMesaApi(
    id: (json['id'] ?? '').toString(), mesa: (json['table'] ?? '').toString(),
    status: (json['status'] ?? '').toString(),
    compradorEmail: (json['buyerEmail'] ?? '').toString(),
    total: (json['total'] as num).toDouble(),
    desconto: (json['discount'] as num).toDouble(),
    cupom: json['coupon']?.toString(),
    criadoEm: DateTime.parse(json['createdAt'].toString()).toLocal(),
    itens: ((json['items'] as List?) ?? []).map((item) =>
        ItemMesaApi.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
  );
}
class ItemMesaApi {
  final int produtoId, quantidade;
  final String nome;
  final double preco;
  const ItemMesaApi({required this.produtoId, required this.quantidade,
    required this.nome, required this.preco});
  factory ItemMesaApi.fromJson(Map<String, dynamic> json) => ItemMesaApi(
    produtoId: (json['productId'] as num).toInt(),
    quantidade: (json['quantity'] as num).toInt(),
    nome: (json['name'] ?? '').toString(),
    preco: (json['price'] as num).toDouble(),
  );
}

class PedidoMesaApiService {
  static final PedidoMesaApiService instance = PedidoMesaApiService._();
  PedidoMesaApiService._();
  List<PedidoMesaApi> _list(dynamic data) => (data as List)
      .map((item) => PedidoMesaApi.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList(growable: false);

  Future<PedidoMesaApi> enviar({required String mesa, required String qrToken,
    required String requestId, required List<Map<String, dynamic>> itens,
    String? cupom}) async {
    final data = await NovoApiHttpService.instance.request('POST', '/table-orders',
      body: {'table': mesa, 'qrToken': qrToken, 'requestId': requestId,
        'items': itens, 'coupon': cupom});
    return PedidoMesaApi.fromJson(Map<String, dynamic>.from(data as Map));
  }
  Future<List<PedidoMesaApi>> meus() async => _list(
    await NovoApiHttpService.instance.request('GET', '/table-orders/mine'));
  Future<List<PedidoMesaApi>> listarAdmin() async => _list(
    await NovoApiHttpService.instance.request('GET', '/admin/table-orders'));
  Future<PedidoMesaApi> atualizarStatus(String id, String status) async =>
    PedidoMesaApi.fromJson(Map<String, dynamic>.from(
      await NovoApiHttpService.instance.request('PATCH',
        '/admin/table-orders/${Uri.encodeComponent(id)}/status',
        body: {'status': status}) as Map));
  Future<Map<String, dynamic>> qrDaMesa(String mesa) async =>
      Map<String, dynamic>.from(await NovoApiHttpService.instance.request(
        'GET', '/admin/table-orders/qr?table=${Uri.encodeQueryComponent(mesa)}') as Map);
}
