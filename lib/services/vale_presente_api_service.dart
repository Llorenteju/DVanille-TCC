import 'novo_api_http_service.dart';

class ValeRegistroApi {
  final String id, codigo, destinatario, mensagem, compradorEmail, status;
  final double valor;
  final DateTime criadoEm, validade;
  final DateTime? resgatadoEm;

  const ValeRegistroApi({required this.id, required this.codigo,
    required this.destinatario, required this.mensagem,
    required this.compradorEmail, required this.status,
    required this.valor, required this.criadoEm,
    required this.validade, this.resgatadoEm});

  factory ValeRegistroApi.fromJson(Map<String, dynamic> json) => ValeRegistroApi(
    id: (json['id'] ?? '').toString(),
    codigo: (json['code'] ?? '').toString(),
    destinatario: (json['recipient'] ?? '').toString(),
    mensagem: (json['message'] ?? '').toString(),
    compradorEmail: (json['buyerEmail'] ?? '').toString(),
    status: (json['status'] ?? '').toString(),
    valor: (json['value'] as num).toDouble(),
    criadoEm: DateTime.parse(json['createdAt'].toString()).toLocal(),
    validade: DateTime.parse(json['expiresAt'].toString()).toLocal(),
    resgatadoEm: json['redeemedAt'] == null
        ? null : DateTime.parse(json['redeemedAt'].toString()).toLocal(),
  );
}

class ValePresenteApiService {
  static final ValePresenteApiService instance = ValePresenteApiService._();
  ValePresenteApiService._();

  List<ValeRegistroApi> _lista(dynamic data) => (data as List)
      .map((item) => ValeRegistroApi.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList(growable: false);

  Future<List<ValeRegistroApi>> listarMeus() async => _lista(
      await NovoApiHttpService.instance.request('GET', '/gift-vouchers/me'));

  Future<List<ValeRegistroApi>> listarAdmin() async => _lista(
      await NovoApiHttpService.instance.request('GET', '/admin/gift-vouchers'));

  Future<List<ValeRegistroApi>> emitirDemonstracao({required String requestId,
    required List<Map<String, dynamic>> items}) async => _lista(
      await NovoApiHttpService.instance.request('POST', '/gift-vouchers/demo-issue',
        body: {'requestId': requestId, 'items': items}));

  Future<ValeRegistroApi> resgatar(String codigo) async => ValeRegistroApi.fromJson(
    Map<String, dynamic>.from(await NovoApiHttpService.instance.request(
      'PATCH', '/admin/gift-vouchers/redeem', body: {'code': codigo}) as Map));

  Future<ValeRegistroApi> cancelar(String id) async => ValeRegistroApi.fromJson(
    Map<String, dynamic>.from(await NovoApiHttpService.instance.request(
      'PATCH', '/admin/gift-vouchers/${Uri.encodeComponent(id)}/cancel') as Map));
}
