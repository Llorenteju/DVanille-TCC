import 'package:flutter/foundation.dart';

import '../models/comanda_mesa.dart';
import '../models/pedido.dart';
import '../models/produto.dart';
import 'app_state.dart';
import '../data/mock_data.dart';
import 'pedido_mesa_api_service.dart';

class ComandaMesaState extends ChangeNotifier {
  ComandaMesaState._();

  static final ComandaMesaState instance = ComandaMesaState._();

  final Map<String, ComandaMesa> _comandas = {};
  final Map<String, String> _tokensQr = {};
  final Map<String, String> _enviosPendentes = {};

  /// Guarda o token assinado contido no QR físico durante a navegação entre telas.
  void registrarTokenQr(String mesa, String? token) {
    if (token != null && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) {
      _tokensQr[mesa.trim()] = token;
    }
  }


  List<ComandaMesa> get comandas => List.unmodifiable(_comandas.values);

  ComandaMesa? comandaDaMesa(String mesa) => _comandas[mesa.trim()];

  ComandaMesa abrirComanda(String mesa) {
    final numeroMesa = mesa.trim();

    if (numeroMesa.isEmpty) {
      throw ArgumentError('Informe uma mesa válida.');
    }

    final existente = _comandas[numeroMesa];

    if (existente != null && existente.status != 'encerrada') {
      return existente;
    }

    final comanda = ComandaMesa(
      id: 'CM-${DateTime.now().microsecondsSinceEpoch}',
      mesa: numeroMesa,
    );

    _comandas[numeroMesa] = comanda;
    notifyListeners();

    return comanda;
  }

  bool _podeEditar(ComandaMesa comanda) {
    return comanda.status != 'encerrada';
  }

  void adicionarProduto({
    required String mesa,
    required Produto produto,
    int quantidade = 1,
  }) {
    final numeroMesa = mesa.trim();

    if (numeroMesa.isEmpty || quantidade <= 0) return;

    final comanda = _comandas[numeroMesa];

    if (comanda == null || !_podeEditar(comanda)) return;

    comanda.adicionarItem(
      produtoId: produto.id.toString(),
      nome: produto.nome,
      preco: produto.preco,
      quantidade: quantidade,
    );

    comanda.status = 'aberta';
    _enviosPendentes.remove(numeroMesa);

    notifyListeners();
  }

  void alterarQuantidade({
    required String mesa,
    required String produtoId,
    required int variacao,
  }) {
    final comanda = _comandas[mesa.trim()];

    if (comanda == null || !_podeEditar(comanda)) return;

    comanda.alterarQuantidade(produtoId, variacao);
    _enviosPendentes.remove(mesa.trim());

    notifyListeners();
  }

  void removerProduto({
    required String mesa,
    required String produtoId,
  }) {
    final comanda = _comandas[mesa.trim()];

    if (comanda == null || !_podeEditar(comanda)) return;

    comanda.removerItem(produtoId);
    _enviosPendentes.remove(mesa.trim());

    notifyListeners();
  }

  /// Verifica se hoje está na semana do aniversário.
  ///
  /// A semana começa na segunda-feira e termina no domingo.
  bool _estaNaSemanaDoAniversario(DateTime nascimento) {
    final hoje = DateTime.now();

    // Ajusta o dia para aniversários em 29 de fevereiro.
    final ultimoDiaDoMes = DateTime(
      hoje.year,
      nascimento.month + 1,
      0,
    ).day;

    final diaAniversario =
        nascimento.day > ultimoDiaDoMes ? ultimoDiaDoMes : nascimento.day;

    final aniversario = DateTime(
      hoje.year,
      nascimento.month,
      diaAniversario,
    );

    final inicioSemana = aniversario.subtract(
      Duration(days: aniversario.weekday - DateTime.monday),
    );

    final fimSemana = inicioSemana.add(const Duration(days: 6));

    final dataHoje = DateTime(hoje.year, hoje.month, hoje.day);

    return !dataHoje.isBefore(inicioSemana) && !dataHoje.isAfter(fimSemana);
  }

  /// Aplica o cupom de aniversário exclusivamente à comanda.
  bool aplicarCupomAniversario(String mesa) {
    final numeroMesa = mesa.trim();

    if (numeroMesa.isEmpty) return false;

    final state = AppState.instance;
    final cliente = state.usuarioLogado;
    final comanda = _comandas[numeroMesa];

    if (cliente == null ||
        comanda == null ||
        comanda.itens.isEmpty ||
        !_podeEditar(comanda)) {
      return false;
    }

    // Impede reaplicação do mesmo cupom.
    if (comanda.temCupom) return false;

    final nascimento = cliente.dataNascimento;

    if (nascimento == null || !_estaNaSemanaDoAniversario(nascimento)) {
      return false;
    }

    final percentual = cupons['ANIVERSARIO'];

    if (percentual == null) return false;

    comanda.aplicarCupom(
      codigo: 'ANIVERSARIO',
      percentual: percentual,
    );

    notifyListeners();

    return true;
  }

  /// Remove o cupom aplicado à comanda.
  void removerCupom(String mesa) {
    final comanda = _comandas[mesa.trim()];

    if (comanda == null || !_podeEditar(comanda)) return;

    comanda.removerCupom();

    notifyListeners();
  }

  void solicitarAtendimento(String mesa) {
    final numeroMesa = mesa.trim();

    if (numeroMesa.isEmpty) return;

    final comanda = _comandas[numeroMesa];

    if (comanda == null || !_podeEditar(comanda)) return;

    comanda.solicitarAtendimento();

    notifyListeners();
  }

  Pedido _pedidoRecebido(PedidoMesaApi remoto) {
    final data = remoto.criadoEm;
    String dois(int valor) => valor.toString().padLeft(2, '0');
    return Pedido(
      id: remoto.id,
      clienteEmail: remoto.compradorEmail,
      itens: remoto.itens.map((item) => ItemPedido(
        produtoId: item.produtoId.toString(),
        nome: item.nome,
        preco: item.preco,
        qtd: item.quantidade,
      )).toList(),
      total: remoto.total,
      desconto: remoto.desconto,
      cupomAplicado: remoto.cupom,
      data: '${dois(data.day)}/${dois(data.month)}/${data.year} '
          '${dois(data.hour)}:${dois(data.minute)}',
      status: remoto.status,
      modo: 'caixa',
      mesa: remoto.mesa,
    );
  }

  Future<void> carregarPedidosMesaApi(String mesa) async {
    final numeroMesa = mesa.trim();
    if (!AppState.instance.logadoPelaApi || numeroMesa.isEmpty) return;
    final registros = await PedidoMesaApiService.instance.meus();
    final state = AppState.instance;
    state.pedidos.removeWhere((pedido) => pedido.mesa == numeroMesa);
    state.pedidos.addAll(
      registros.where((pedido) => pedido.mesa == numeroMesa).map(_pedidoRecebido),
    );
    state.notifyListeners();
    notifyListeners();
  }

  /// Registra no backend antes de limpar os itens. Se a API falhar, mantém a comanda.
  Future<bool> enviarPedidoAoCaixa(String mesa) async {
    final numeroMesa = mesa.trim();
    final state = AppState.instance;
    final cliente = state.usuarioLogado;
    final comanda = _comandas[numeroMesa];
    if (cliente == null || !state.logadoPelaApi || comanda == null ||
        comanda.itens.isEmpty || !_podeEditar(comanda)) return false;

    final qrToken = _tokensQr[numeroMesa];
    if (qrToken == null || qrToken.isEmpty) {
      throw StateError('Para enviar a comanda, abra a página usando o QR Code válido da mesa.');
    }
    if (comanda.temCupom) {
      throw StateError('A validação do cupom de aniversário no caixa ainda está pendente. Remova o cupom para enviar.');
    }
    final pedidoId = _enviosPendentes.putIfAbsent(numeroMesa, () =>
        'CM-${DateTime.now().microsecondsSinceEpoch}-$numeroMesa');
    final criado = await PedidoMesaApiService.instance.enviar(
      mesa: numeroMesa,
      qrToken: qrToken,
      requestId: pedidoId,
      itens: comanda.itens.map((item) => <String, dynamic>{
        'productId': int.parse(item.produtoId),
        'quantity': item.quantidade,
      }).toList(),
    );
    state.pedidos.removeWhere((pedido) => pedido.id == criado.id);
    state.pedidos.add(_pedidoRecebido(criado));
    comanda.itens.clear();
    comanda.removerCupom();
    comanda.status = 'aberta';
    _enviosPendentes.remove(numeroMesa);
    state.notifyListeners();
    notifyListeners();
    return true;
  }

  void encerrarComanda(String mesa) {
    final comanda = _comandas[mesa.trim()];

    if (comanda == null) return;

    comanda.status = 'encerrada';

    notifyListeners();
  }
}
