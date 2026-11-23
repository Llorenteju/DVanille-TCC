class Reserva {
  final String id;
  final String nome;
  final String email;
  final String telefone;

  /// Formato AAAA-MM-DD (igual ao input date do HTML).
  final String data;
  final String horario;
  final int pessoas;
  final String preferencias;
  final String observacoes;

  /// solicitada | confirmada | cancelada | finalizada
  String status;

  /// Entregue apenas na criação de uma reserva de visitante; não persistir.
  final String? guestAccessToken;

  Reserva({
    required this.id,
    required this.nome,
    required this.email,
    required this.telefone,
    required this.data,
    required this.horario,
    required this.pessoas,
    this.preferencias = '',
    this.observacoes = '',
    this.status = 'solicitada',
    this.guestAccessToken,
  });

  factory Reserva.fromApi(Map<String, dynamic> json) {
    final id = json['id'];
    if (id == null || int.tryParse(id.toString()) == null) {
      throw const FormatException('A API retornou uma reserva sem ID válido.');
    }
    return Reserva(
      id: id.toString(),
      nome: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      telefone: (json['phone'] ?? '').toString(),
      data: (json['reservationDate'] ?? '').toString(),
      horario: (json['reservationTime'] ?? '').toString(),
      pessoas: (json['guests'] as num?)?.toInt() ?? 0,
      preferencias: (json['preferences'] ?? '').toString(),
      observacoes: (json['notes'] ?? '').toString(),
      status: (json['status'] ?? 'solicitada').toString(),
      guestAccessToken: json['guestAccessToken']?.toString(),
    );
  }

  String get dataBr {
    final partes = data.split('-');
    if (partes.length != 3) return data;
    return '${partes[2]}/${partes[1]}/${partes[0]}';
  }
}
