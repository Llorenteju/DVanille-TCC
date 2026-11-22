/// Informações nutricionais por porção (mesmas chaves usadas no HTML).
class Nutricional {
  double calorias;
  double carboidratos;
  double proteinas;
  double gorduras;
  double fibras;
  double acucares;

  /// Para registros da API: indica quais valores foram efetivamente
  /// informados no banco. `null` preserva a exibição dos dados do protótipo.
  final Set<String>? camposInformados;

  Nutricional({
    this.calorias = 0,
    this.carboidratos = 0,
    this.proteinas = 0,
    this.gorduras = 0,
    this.fibras = 0,
    this.acucares = 0,
    this.camposInformados,
  });

  String _valor(String campo, double valor, String unidade) {
    if (camposInformados != null && !camposInformados!.contains(campo)) {
      return 'Não informado';
    }
    return '${_n(valor)} $unidade';
  }

  List<List<String>> get linhas => [
        ['Calorias', _valor('calorias', calorias, 'kcal')],
        ['Carboidratos', _valor('carboidratos', carboidratos, 'g')],
        ['Proteínas', _valor('proteinas', proteinas, 'g')],
        ['Gorduras', _valor('gorduras', gorduras, 'g')],
        ['Fibras', _valor('fibras', fibras, 'g')],
        ['Açúcares', _valor('acucares', acucares, 'g')],
      ];

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class Produto {
  int id;
  String nome;

  /// id da categoria: bolos, doces, sobremesas-geladas, bebidas, salgados
  String categoria;
  double preco;
  double? precoAntigo;
  String descricao;
  String imagem;
  String icon;
  List<String> ingredientes;
  List<String> restricoes;
  List<String> alergenicos;
  Nutricional nutricional;
  bool oferta;
  // Campos de controle reais enviados pela API (não alteram o protótipo local).
  int? categoryId;
  bool ativo;
  bool disponivel;
  int estoque;

  Produto({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.preco,
    required this.descricao,
    this.precoAntigo,
    this.imagem = '',
    this.icon = '🍽️',
    List<String>? ingredientes,
    List<String>? restricoes,
    List<String>? alergenicos,
    Nutricional? nutricional,
    this.oferta = false,
    this.categoryId,
    this.ativo = true,
    this.disponivel = true,
    this.estoque = 0,
  })  : ingredientes = ingredientes ?? <String>[],
        restricoes = restricoes ?? <String>[],
        alergenicos = alergenicos ?? <String>[],
        nutricional = nutricional ?? Nutricional();

  /// Percentual de desconto exibido na página de ofertas.
  int get descontoPercentual {
    final antigo = precoAntigo;
    if (antigo == null || antigo <= 0) return 0;
    return ((1 - preco / antigo) * 100).round();
  }
}
