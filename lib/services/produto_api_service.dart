import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/produto.dart';

/// Consulta pública, somente leitura. Nenhuma rota POST/PUT/DELETE é usada.
/// A URL deve terminar em /api (por exemplo localhost:3001/api).
class ProdutoApiService {
  static const String _base = String.fromEnvironment(
    'DVANILLE_API_URL',
    defaultValue: 'http://localhost:3001/api',
  );

  static Uri get _api => Uri.parse(_base.replaceAll(RegExp(r'/$'), ''));

  static Uri _rota(String caminho, [Map<String, String>? parametros]) {
    final url = Uri.parse('${_api.toString()}/$caminho');
    return parametros == null ? url : url.replace(queryParameters: parametros);
  }

  Future<CatalogoApiResultado> listarCatalogo() async {
    final cliente = http.Client();
    try {
      // Se a API disponibilizar as categorias separadamente, aproveitamos
      // o slug. A ausência desse endpoint não impede a leitura dos produtos.
      final categorias = await _categorias(cliente);
      final produtosBrutos = <Map<String, dynamic>>[];
      final idsRecebidos = <int>{};

      const limite = 100;
      for (var pagina = 1; pagina <= 20; pagina++) {
        final resposta = await cliente
            .get(
              _rota('products', {'page': '$pagina', 'limit': '$limite'}),
            )
            .timeout(const Duration(seconds: 15));
        if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
          throw CatalogoApiException(
            'A consulta de produtos retornou HTTP ${resposta.statusCode}.',
          );
        }
        final body = jsonDecode(utf8.decode(resposta.bodyBytes));
        final registros =
            _lista(body, chaves: const ['products', 'items', 'results']);
        final paginacao = _paginacao(body);
        if (registros.isEmpty) break;
        var novos = 0;
        for (final registro in registros) {
          final id = _inteiro(registro['id']);
          if (id != null && idsRecebidos.add(id)) {
            produtosBrutos.add(registro);
            novos++;
          }
        }
        // Não repetir infinitamente caso a API ignore page.
        if (novos == 0) break;
        final totalPaginas = _inteiro(paginacao['totalPages'] ??
            paginacao['total_pages'] ??
            paginacao['pages'] ??
            paginacao['lastPage']);
        if (totalPaginas != null) {
          if (pagina >= totalPaginas) break;
        } else if (registros.length < limite) {
          break;
        }
      }

      final produtos = <Produto>[];
      final categoriasSemCorrespondencia = <String>{};
      for (final dado in produtosBrutos) {
        if (dado['isActive'] == false || dado['isAvailable'] == false) continue;
        final produto = _produto(dado, categorias);
        if (produto == null) continue;
        if (produto.categoria == 'categoria-nao-mapeada') {
          final categoria = dado['category'];
          categoriasSemCorrespondencia.add(
            categoria is Map
                ? '${categoria['slug'] ?? categoria['name'] ?? categoria['id']}'
                : '${dado['categorySlug'] ?? dado['categoryId'] ?? categoria ?? 'desconhecida'}',
          );
        }
        produtos.add(produto);
      }
      if (produtosBrutos.isNotEmpty && produtos.isEmpty) {
        throw CatalogoApiException(
          'A API respondeu, mas não foi possível interpretar os produtos. '
          'Verifique o formato retornado pelo endpoint /api/products.',
        );
      }
      return CatalogoApiResultado(
        produtos: produtos,
        categoriasNaoMapeadas: categoriasSemCorrespondencia.toList()..sort(),
      );
    } on TimeoutException {
      throw CatalogoApiException('A API demorou demais para responder.');
    } on FormatException {
      throw CatalogoApiException('A API retornou um JSON inválido.');
    } on http.ClientException catch (e) {
      throw CatalogoApiException('Falha de conexão com a API: ${e.message}');
    } finally {
      cliente.close();
    }
  }

  Future<Map<int, String>> _categorias(http.Client cliente) async {
    try {
      final res = await cliente
          .get(_rota('categories'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return {};
      final resultado = <int, String>{};
      final dados = jsonDecode(utf8.decode(res.bodyBytes));
      for (final cat in _lista(dados, chaves: const ['categories', 'items'])) {
        final id = _inteiro(cat['id']);
        final slug = _texto(cat['slug'] ?? cat['name']);
        if (id != null && slug.isNotEmpty) resultado[id] = slug;
      }
      return resultado;
    } catch (_) {
      return {};
    }
  }

  /// Formatos aceitos: lista simples; { data: [...] };
  /// { data: { products: [...] } }; { products: [...] }.
  static List<Map<String, dynamic>> _lista(dynamic body,
      {required List<String> chaves}) {
    dynamic atual = body;
    for (var i = 0; i < 4 && atual is Map; i++) {
      final mapa = Map<String, dynamic>.from(atual);
      dynamic proximo;
      for (final chave in [...chaves, 'data']) {
        if (mapa[chave] is List || mapa[chave] is Map) {
          proximo = mapa[chave];
          break;
        }
      }
      if (proximo == null) break;
      atual = proximo;
    }
    if (atual is! List) {
      throw CatalogoApiException('Formato inesperado na listagem da API.');
    }
    return atual
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  static Map<String, dynamic> _paginacao(dynamic body) {
    if (body is! Map) return {};
    final p = body['pagination'] ??
        body['meta'] ??
        (body['data'] is Map ? (body['data'] as Map)['pagination'] : null);
    if (p is Map) return Map<String, dynamic>.from(p);
    return {};
  }

  Produto? _produto(Map<String, dynamic> dado, Map<int, String> categorias) {
    final id = _inteiro(dado['id']);
    final nome = _texto(dado['name'] ?? dado['nome']);
    final preco = _numero(dado['price'] ?? dado['preco']);
    if (id == null || nome.isEmpty || preco == null) return null;

    final rawCat = dado['category'];
    final slug = rawCat is Map
        ? _texto(rawCat['slug'] ??
            rawCat['name'] ??
            categorias[_inteiro(rawCat['id'])])
        : _texto(dado['categorySlug'] ??
            (rawCat is num ? categorias[_inteiro(rawCat)] : rawCat) ??
            categorias[_inteiro(dado['categoryId'])]);
    final categoria = _categoria(slug);
    final original = preco;
    final promocional =
        _numero(dado['promotionalPrice'] ?? dado['promotional_price']);
    final promocaoValida =
        promocional != null && promocional > 0 && promocional < original;

    final nutrientes = dado['nutrition'] is Map
        ? Map<String, dynamic>.from(dado['nutrition'] as Map)
        : dado;
    final informados = <String>{};
    double nutricional(String nome, List<String> chaves) {
      for (final chave in chaves) {
        if (nutrientes[chave] != null) {
          final valor = _numero(nutrientes[chave]);
          if (valor != null) {
            informados.add(nome);
            return valor;
          }
        }
      }
      return 0;
    }

    final restricoes = <String>{};
    final r = dado['restricoesAlimentares'] ??
        dado['dietaryRestrictions'] ??
        dado['restrictions'] ??
        dado['productRestrictions'];
    if (r is List) {
      for (final entrada in r) {
        dynamic valor = entrada;
        if (entrada is Map) {
          valor = entrada['restriction'] ??
              entrada['dietaryRestriction'] ??
              entrada;
          if (valor is Map) valor = valor['slug'] ?? valor['name'];
        }
        final chave = _restricao(_texto(valor));
        if (chave != null) restricoes.add(chave);
      }
    }
    // Apenas atributos positivos explícitos permitem estas duas etiquetas.
    if (dado['isVegan'] == true) restricoes.add('vegano');
    if (dado['isVegetarian'] == true || dado['isVegan'] == true) {
      restricoes.add('vegetariano');
    }
    // Não deduzir 'sem glúten', 'sem APLV' etc. de campos ausentes
    // ou de flags containsX=false: segurança alimentar exige confirmação.

    final imagem = _imagem(_texto(dado['image'] ?? dado['imageUrl']));
    final ingredientes = _itens(dado['ingredients']);
    final alergenicos = _itens(dado['allergens']);

    const icones = {
      'bolo': '🎂',
      'salgados': '🥐',
      'doces': '🧁',
      'sobremesas-geladas': '🍧',
      'bebidas-quentes': '☕',
      'bebidas-geladas': '🥤',
    };
    return Produto(
      id: id,
      nome: nome,
      categoria: categoria,
      preco: promocaoValida ? promocional : original,
      precoAntigo: promocaoValida ? original : null,
      oferta: promocaoValida,
      descricao: _texto(dado['description'] ?? dado['descricao']),
      imagem: imagem,
      icon: icones[categoria] ?? '🍽️',
      ingredientes:
          ingredientes.isEmpty ? ['Ingredientes não informados'] : ingredientes,
      alergenicos: alergenicos.isEmpty
          ? ['Alergênicos não informados — consulte a cafeteria']
          : alergenicos,
      restricoes: restricoes.toList(),
      nutricional: Nutricional(
        calorias: nutricional('calorias', ['calories', 'calorias']),
        carboidratos:
            nutricional('carboidratos', ['carbohydrates', 'carboidratos']),
        proteinas: nutricional('proteinas', ['proteins', 'proteinas']),
        gorduras: nutricional('gorduras', ['fats', 'gorduras']),
        fibras: nutricional('fibras', ['fiber', 'fibras']),
        acucares: nutricional('acucares', ['sugars', 'acucares']),
        camposInformados: informados,
      ),
    );
  }

  static String _categoria(String slug) {
    final chave = _chave(slug);
    const opcoes = {
      'bolo': 'bolo',
      'bolos': 'bolo',
      'salgado': 'salgados',
      'salgados': 'salgados',
      'doce': 'doces',
      'doces': 'doces',
      'sobremesagelada': 'sobremesas-geladas',
      'sobremesasgeladas': 'sobremesas-geladas',
      'bebidaquente': 'bebidas-quentes',
      'bebidasquentes': 'bebidas-quentes',
      'bebidagelada': 'bebidas-geladas',
      'bebidasgeladas': 'bebidas-geladas',
    };
    return opcoes[chave] ?? 'categoria-nao-mapeada';
  }

  static String? _restricao(String valor) {
    final chave = _chave(valor);
    const opcoes = {
      'semaplv': 'semAPLV',
      'semsoja': 'semSoja',
      'semoleaginosas': 'semOleaginosas',
      'semacucaradicionado': 'semAcucarAdicionado',
      'semsaladicionado': 'semSalAdicionado',
      'lowfodmap': 'lowFODMAP',
      'lowcarb': 'lowCarb',
      'semaditivosartificiais': 'semAditivosArtificiais',
      'vegano': 'vegano',
      'vegan': 'vegano',
      'vegetariano': 'vegetariano',
      'vegetarian': 'vegetariano',
      'semlactose': 'semLactose',
      'semgluten': 'semGluten',
    };
    return opcoes[chave];
  }

  static String _chave(String valor) => valor
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _texto(dynamic value) => value == null ? '' : '$value'.trim();

  static double? _numero(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse('$value'.replaceAll(',', '.'));
  }

  static int? _inteiro(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  static List<String> _itens(dynamic value) {
    if (value is List)
      return value.map(_texto).where((x) => x.isNotEmpty).toList();
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[,;\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  static String _imagem(String valor) {
    if (valor.isEmpty) return '';
    final url = Uri.tryParse(valor);
    if (url == null) return '';
    if (url.hasScheme) {
      return (url.scheme == 'http' || url.scheme == 'https') ? valor : '';
    }
    final host = _api.replace(path: '', query: '', fragment: '');
    return host
        .resolve('/${valor.replaceFirst(RegExp(r'^/+'), '')}')
        .toString();
  }
}

class CatalogoApiResultado {
  final List<Produto> produtos;
  final List<String> categoriasNaoMapeadas;

  CatalogoApiResultado({
    required this.produtos,
    required this.categoriasNaoMapeadas,
  });
}

class CatalogoApiException implements Exception {
  final String mensagem;
  CatalogoApiException(this.mensagem);
  @override
  String toString() => mensagem;
}
