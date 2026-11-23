import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/produto.dart';
import 'auth_client_stub.dart'
    if (dart.library.js_interop) 'auth_client_web.dart' as plataforma;

/// As rotas /admin são protegidas no backend: cookie HttpOnly + role ADMIN.
/// Este cliente NÃO guarda tokens, senhas ou credenciais no navegador.
class AdminProdutoApiService {
  static const _base = String.fromEnvironment(
    'DVANILLE_API_URL',
    defaultValue: 'http://localhost:3001/api',
  );

  Uri _url(String path) => Uri.parse(
        '${_base.replaceAll(RegExp(r'/$'), '')}/$path',
      );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final client = plataforma.criarClienteAuth();
    try {
      final request = http.Request(method, _url(path));
      request.headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      });
      if (data != null) request.body = jsonEncode(data);
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      return _decode(response);
    } on TimeoutException {
      throw const AdminProdutoApiException('A API demorou para responder.');
    } on AdminProdutoApiException {
      rethrow;
    } catch (_) {
      throw const AdminProdutoApiException(
        'Não foi possível acessar a API. Confira o Docker e a porta 3001.',
      );
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> parsed;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map) throw const FormatException();
      parsed = Map<String, dynamic>.from(body);
    } catch (_) {
      throw const AdminProdutoApiException('Resposta inválida do servidor.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = parsed['message']?.toString() ?? 'Erro na API.';
      if (response.statusCode == 401) {
        throw const AdminProdutoApiException(
          'Sua sessão expirou. Faça login novamente.',
        );
      }
      if (response.statusCode == 403) {
        throw const AdminProdutoApiException(
          'A sua conta não possui permissão administrativa.',
        );
      }
      throw AdminProdutoApiException('HTTP ${response.statusCode}: $message');
    }
    return parsed;
  }

  String _normalizar(String valor) => valor
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ã', 'a')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<int> _categoriaId(String categoriaLocal) async {
    final body = await _request('GET', 'admin/categories');
    final raw = body['data'];
    if (raw is! List) {
      throw const AdminProdutoApiException('Categorias inválidas na API.');
    }
    final equivalentes = <String, Set<String>>{
      'bolo': {'bolo', 'bolos'},
      'salgados': {'salgado', 'salgados'},
      'doces': {'doce', 'doces'},
      'sobremesas-geladas': {'sobremesagelada', 'sobremesasgeladas'},
      'bebidas-quentes': {'bebidaquente', 'bebidasquentes'},
      'bebidas-geladas': {'bebidagelada', 'bebidasgeladas'},
    };
    final alvo = equivalentes[categoriaLocal] ?? {_normalizar(categoriaLocal)};
    for (final item in raw) {
      if (item is! Map) continue;
      final slug = _normalizar('${item['slug'] ?? ''}');
      final nome = _normalizar('${item['name'] ?? ''}');
      if (alvo.contains(slug) || alvo.contains(nome)) {
        final id = item['id'];
        if (id is num) return id.toInt();
      }
    }
    throw AdminProdutoApiException(
      'Não encontrei a categoria "$categoriaLocal" no Supabase. '
      'Verifique as categorias cadastradas antes de salvar.',
    );
  }

  /// Correspondência entre os filtros do Flutter e os slugs do Supabase.
  /// Nunca inventamos IDs: são sempre consultados em /dietary-restrictions.
  static const Map<String, String> _slugPorChave = {
    'semAPLV': 'sem-aplv',
    'semSoja': 'sem-soja',
    'semOleaginosas': 'sem-oleaginosas',
    'semAcucarAdicionado': 'sem-acucar-adicionado',
    'semSalAdicionado': 'sem-sal-adicionado',
    'lowFODMAP': 'low-fodmap',
    'lowCarb': 'low-carb',
    'semAditivosArtificiais': 'sem-aditivos-artificiais',
    'vegano': 'vegano',
    'vegetariano': 'vegetariano',
    'semLactose': 'sem-lactose',
    'semGluten': 'sem-gluten',
  };

  /// Somente restrições ativas no banco. Não mostra uma opção do protótipo
  /// como disponível se ela não estiver registrada no Supabase.
  Future<Map<String, int>> listarRestricoes() async {
    final body = await _request('GET', 'dietary-restrictions');
    final data = body['data'];
    if (data is! List) {
      throw const AdminProdutoApiException(
        'A API retornou uma lista de restrições inválida.',
      );
    }
    final idsPorSlug = <String, int>{};
    for (final item in data) {
      if (item is! Map) continue;
      final slug = '${item['slug'] ?? ''}'.trim();
      final id = int.tryParse('${item['id'] ?? ''}');
      if (slug.isNotEmpty && id != null && id > 0) {
        idsPorSlug[slug] = id;
      }
    }
    final resultado = <String, int>{};
    for (final entry in _slugPorChave.entries) {
      final id = idsPorSlug[entry.value];
      if (id != null) resultado[entry.key] = id;
    }
    if (resultado.isEmpty) {
      throw const AdminProdutoApiException(
        'Não foram encontradas restrições alimentares válidas na API.',
      );
    }
    return resultado;
  }

  Future<List<int>> _idsParaRestricoes(List<String> restricoes) async {
    final idsPorChave = await listarRestricoes();
    final selecionadas = {...restricoes};
    // Vegano implica vegetariano; exibimos os dois selos após confirmação.
    if (selecionadas.contains('vegano')) selecionadas.add('vegetariano');
    final desconhecidas =
        selecionadas.where((chave) => !idsPorChave.containsKey(chave)).toList();
    if (desconhecidas.isNotEmpty) {
      throw AdminProdutoApiException(
        'Uma restrição selecionada não está disponível no Supabase: '
        '${desconhecidas.join(', ')}. Atualize o formulário.',
      );
    }
    return selecionadas.map((chave) => idsPorChave[chave]!).toList()..sort();
  }

  Map<String, dynamic> _payload(
    Produto produto,
    int categoriaId, {
    required bool novo,
    required bool incluirImagem,
    required List<int> restrictionIds,
  }) {
    final campos = produto.nutricional.camposInformados;
    bool informado(String chave) => campos == null || campos.contains(chave);
    final map = <String, dynamic>{
      'categoryId': categoriaId,
      // [] remove os vínculos na edição; o backend salva numa transação.
      'restrictionIds': restrictionIds,
      'name': produto.nome.trim(),
      'description': produto.descricao.trim(),
      'price': produto.preco,
      'stock': produto.estoque,
      'ingredients': produto.ingredientes.join(', '),
      'allergens': produto.alergenicos.join(', '),
      'calories':
          informado('calorias') ? produto.nutricional.calorias.round() : null,
      'carbohydrates':
          informado('carboidratos') ? produto.nutricional.carboidratos : null,
      'proteins': informado('proteinas') ? produto.nutricional.proteinas : null,
      'fats': informado('gorduras') ? produto.nutricional.gorduras : null,
      'fiber': informado('fibras') ? produto.nutricional.fibras : null,
      'isVegan': produto.restricoes.contains('vegano'),
      'isVegetarian': produto.restricoes.contains('vegano') ||
          produto.restricoes.contains('vegetariano'),
      'isAvailable': produto.disponivel,
    };
    if (novo) {
      map['isActive'] = true;
    }
    if (incluirImagem) map['image'] = produto.imagem.trim();
    return map;
  }

  /// POST/PUT real no Supabase. O backend valida ADMIN novamente.
  /// Retorna ID; a tela deve atualizar a lista antes de mostrar sucesso.
  Future<int> salvar(
    Produto produto, {
    Produto? anterior,
    bool fotoSelecionada = false,
  }) async {
    if (produto.nome.trim().length < 2 || produto.preco <= 0) {
      throw const AdminProdutoApiException(
        'Informe um nome com pelo menos 2 letras e preço maior que zero.',
      );
    }
    if (produto.estoque < 0 || produto.estoque > 1000000) {
      throw const AdminProdutoApiException(
        'Informe um estoque válido de 0 a 1.000.000 unidades.',
      );
    }
    final categoryId = await _categoriaId(produto.categoria);
    final restrictionIds = await _idsParaRestricoes(produto.restricoes);
    final novo = anterior == null;
    final incluirImagem = !fotoSelecionada &&
        (novo ? produto.imagem.isNotEmpty : produto.imagem != anterior.imagem);
    if (incluirImagem && produto.imagem.isNotEmpty) {
      final uri = Uri.tryParse(produto.imagem);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const AdminProdutoApiException(
          'Use uma URL de imagem HTTPS válida ou selecione uma foto.',
        );
      }
      if (produto.imagem.length > 255) {
        throw const AdminProdutoApiException('URL de imagem muito longa.');
      }
    }
    final res = await _request(
      novo ? 'POST' : 'PUT',
      novo ? 'admin/products' : 'admin/products/${anterior.id}',
      data: _payload(
        produto,
        categoryId,
        novo: novo,
        incluirImagem: incluirImagem,
        restrictionIds: restrictionIds,
      ),
    );
    final dados = res['data'];
    if (dados is Map && dados['id'] is num) return (dados['id'] as num).toInt();
    throw const AdminProdutoApiException(
      'A API não confirmou o ID do produto salvo. Confira o Supabase antes de tentar novamente.',
    );
  }

  /// Upload com validação de arquivo realizada no próprio backend.
  /// Fotos devem ser armazenadas em volume persistente no Docker.
  Future<void> enviarFoto(int id, Uint8List bytes, String nomeArquivo) async {
    final extensao = nomeArquivo.split('.').last.toLowerCase();
    final mime = switch (extensao) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw const AdminProdutoApiException('Formato de foto inválido.'),
    };
    final client = plataforma.criarClienteAuth();
    try {
      final request =
          http.MultipartRequest('POST', _url('admin/products/$id/image'));
      request.headers['Accept'] = 'application/json';
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: nomeArquivo,
        contentType: MediaType.parse(mime),
      ));
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30));
      _decode(response);
    } on TimeoutException {
      throw const AdminProdutoApiException('A foto demorou para ser enviada.');
    } on AdminProdutoApiException {
      rethrow;
    } catch (_) {
      throw const AdminProdutoApiException('Falha no upload da foto.');
    } finally {
      client.close();
    }
  }

  /// Acrescenta unidades ao estoque real pelo endpoint administrativo.
  /// Utiliza ajuste relativo para não sobrescrever pedidos simultâneos.
  Future<void> reporEstoque(int produtoId, int quantidade) async {
    if (produtoId <= 0 || quantidade < 1 || quantidade > 1000000) {
      throw const AdminProdutoApiException(
        'Informe um produto válido e uma reposição de 1 a 1.000.000 unidades.',
      );
    }
    await _request(
      'PATCH',
      'admin/stock/$produtoId',
      data: {'adjustment': quantidade},
    );
  }

  /// Evita exclusão definitiva: desativa no Supabase, com histórico preservado.
  Future<void> atualizarAtivacao(int id, {required bool ativo}) async {
    await _request('PUT', 'admin/products/$id', data: {
      'isActive': ativo,
      'isAvailable': false,
    });
  }
}

class AdminProdutoApiException implements Exception {
  final String mensagem;
  const AdminProdutoApiException(this.mensagem);
  @override
  String toString( ) => mensagem;
}
