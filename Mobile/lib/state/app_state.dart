import 'dart:async';

import 'package:flutter/material.dart';
import '../services/mobile_api_service.dart';
import '../services/mobile_mappers.dart';
import '../models/models.dart';

/// Estado global da aplicação.
/// Usa ChangeNotifier + ListenableBuilder (nativos do Flutter).
class AppState extends ChangeNotifier {
  AppState._internal() {
    products = [];
    addresses = [];
    notifications = [];
  }

  static final AppState instance = AppState._internal();

  final MobileApiService api = MobileApiService();
  bool carregandoCatalogo = false;
  String? erroSincronizacao;
  Order? ultimoPedidoCriado;

  Future<void> loginOnline({required String email, required String senha}) async {
    final result = await api.post('/auth/login', {
      'email': email.trim().toLowerCase(),
      'password': senha,
    }, auth: false);
    _adotarSessao(apiMap(result['data']));
    await carregarDadosIniciais();
  }

  Future<void> cadastrarOnline({
    required String nome, required String email, required String telefone, required String senha,
  }) async {
    final result = await api.post('/auth/register', {
      'name': nome.trim(), 'email': email.trim().toLowerCase(),
      'phone': telefone.trim(), 'password': senha,
    }, auth: false);
    _adotarSessao(apiMap(result['data']));
    await carregarDadosIniciais();
  }

  void _adotarSessao(Map<String, dynamic> data) {
    final token = apiString(data['token']);
    api.setToken(token);
    final u = apiMap(data['user']);
    isLoggedIn = true;
    isAdmin = apiString(u['role']).toUpperCase() == 'ADMIN';
    user = AppUser(
      nome: apiString(u['name']),
      email: apiString(u['email']),
      telefone: apiString(u['phone']),
    );
    // Nunca carregar dados pessoais de uma conta anterior.
    cartItems.clear();
    favoriteIds.clear();
    addresses.clear();
    orders.clear();
    ultimoPedidoCriado = null;
    notifyListeners();
  }

  Future<void> carregarDadosIniciais() async {
    // Catálogo é indispensável; nada de mostrar os mocks como se fossem dados reais.
    await atualizarProdutos();
    erroSincronizacao = null;
    for (final load in <Future<void> Function()>[
      atualizarFavoritos, atualizarCarrinho, atualizarEnderecos, atualizarPedidos,
    ]) {
      try {
        await load();
      } catch (error) {
        erroSincronizacao = error.toString();
        notifyListeners();
      }
    }
  }

  Future<void> atualizarProdutos() async {
    carregandoCatalogo = true;
    notifyListeners();
    try {
      final body = await api.get('/products?limit=100&sort=name&order=asc', auth: false);
      final values = apiList(body['data']);
      products = values.map((value) => apiProduct(value, api)).toList();
    } finally {
      carregandoCatalogo = false;
      notifyListeners();
    }
  }

  Future<void> atualizarFavoritos() async {
    if (!api.isAuthenticated || isAdmin) return;
    final body = await api.get('/favorites?limit=100');
    favoriteIds.clear();
    for (final raw in apiList(body['data'])) {
      final fav = apiMap(raw);
      final id = apiString(fav['productId'] ?? apiMap(fav['product'])['id']);
      if (id.isNotEmpty) favoriteIds.add(id);
    }
    notifyListeners();
  }

  Future<void> alternarFavoritoOnline(String productId) async {
    final id = int.tryParse(productId);
    if (id == null) throw const MobileApiException('ID de produto inválido.');
    if (favoriteIds.contains(productId)) {
      await api.delete('/favorites/$id');
      favoriteIds.remove(productId);
    } else {
      await api.post('/favorites', {'productId': id});
      favoriteIds.add(productId);
    }
    notifyListeners();
  }

  Future<void> atualizarCarrinho() async {
    if (!api.isAuthenticated || isAdmin) return;
    final body = await api.get('/cart');
    final cart = apiMap(body['data']);
    cartItems.clear();
    for (final raw in apiList(cart['items'])) {
      final item = apiMap(raw);
      final productId = apiString(item['productId']);
      final local = products.where((p) => p.id == productId);
      final p = local.isNotEmpty ? local.first : Product(
        id: productId, nome: apiString(item['name'], 'Produto'),
        descricao: '', categoria: ProductCategory.doces,
        preco: apiDouble(item['unitPrice']), imagem: api.imageUrl(apiString(item['image'])),
      );
      cartItems.add(CartItem(
        produto: Product(
          id: p.id, nome: p.nome, descricao: p.descricao,
          categoria: p.categoria, preco: apiDouble(item['unitPrice'], p.preco),
          imagem: p.imagem, ingredientes: p.ingredientes,
          alergenicos: p.alergenicos, restricoes: p.restricoes,
          stock: p.stock, disponivel: item['isAvailable'] != false,
        ),
        quantidade: apiInt(item['quantity'], 1),
      ));
    }
    notifyListeners();
  }

  Future<void> adicionarAoCarrinhoOnline(Product product, {int quantidade = 1}) async {
    if (!product.emEstoque) {
      throw const MobileApiException('Produto sem estoque no momento.');
    }
    final id = int.tryParse(product.id);
    if (id == null) throw const MobileApiException('ID de produto inválido.');
    await api.post('/cart/items', {'productId': id, 'quantity': quantidade});
    await atualizarCarrinho();
    if (!cartItems.any((item) => item.produto.id == product.id)) {
      throw const MobileApiException('A API recebeu o produto, mas o carrinho voltou vazio. Precisamos conferir a sessão e o backend.');
    }
  }

  Future<void> alterarQuantidadeOnline(CartItem item, int quantity) async {
    final id = int.tryParse(item.produto.id);
    if (id == null) throw const MobileApiException('ID de produto inválido.');
    if (quantity <= 0) {
      await api.delete('/cart/items/$id');
    } else {
      await api.patch('/cart/items/$id', {'quantity': quantity});
    }
    await atualizarCarrinho();
  }

  Future<void> esvaziarCarrinhoOnline() async {
    await api.delete('/cart');
    await atualizarCarrinho();
  }

  Future<void> atualizarEnderecos() async {
    if (!api.isAuthenticated || isAdmin) return;
    final body = await api.get('/addresses');
    addresses = apiList(body['data']).map(apiAddress).toList();
    notifyListeners();
  }

  Map<String, dynamic> _dadosEndereco(Address a) => {
    'label': a.apelido.trim(),
    'recipientName': user.nome.trim().isEmpty ? 'Cliente DVanille' : user.nome.trim(),
    'street': a.rua.trim(), 'number': a.numero.trim(),
    'complement': a.complemento.trim(), 'neighborhood': a.bairro.trim(),
    'city': a.cidade.trim(), 'state': a.estado.trim().toUpperCase(),
    'zipCode': a.cep.trim(), 'isDefault': a.principal,
  };

  Future<void> salvarEnderecoOnline(Address a, {bool novo = false}) async {
    if (novo) {
      await api.post('/addresses', _dadosEndereco(a));
    } else {
      await api.put('/addresses/${a.id}', _dadosEndereco(a));
    }
    await atualizarEnderecos();
  }

  Future<void> apagarEnderecoOnline(String id) async {
    await api.delete('/addresses/$id');
    await atualizarEnderecos();
  }

  Future<void> definirEnderecoPrincipalOnline(String id) async {
    await api.patch('/addresses/$id/default', {});
    await atualizarEnderecos();
  }

  Future<void> atualizarPedidos() async {
    if (!api.isAuthenticated || isAdmin) return;
    final body = await api.get('/orders?limit=100');
    orders
      ..clear()
      ..addAll(apiList(body['data']).map((data) => apiOrder(data, products)));
    notifyListeners();
  }

  Future<Order> criarPedidoOnline() async {
    if (cartItems.isEmpty) throw const MobileApiException('Adicione produtos ao carrinho antes de finalizar.');
    final method = metodoPagamentoSelecionado;
    if (method == null) throw const MobileApiException('Selecione a forma de pagamento.');
    // O gateway de cartões não deve ser usado em HTTP local nem neste protótipo.
    if (method != MetodoPagamento.pix && method != MetodoPagamento.dinheiro) {
      throw const MobileApiException('Para a demonstração, selecione PIX ou dinheiro.');
    }
    final delivery = tipoEntregaSelecionada == TipoEntrega.delivery;
    final address = enderecoSelecionado ?? enderecoPrincipal;
    if (delivery && address == null) {
      throw const MobileApiException('Cadastre um endereço para receber seu pedido.');
    }
    final body = await api.post('/orders', {
      'deliveryType': delivery ? 'DELIVERY' : 'PICKUP',
      if (delivery) 'addressId': int.parse(address!.id),
      'paymentMethod': apiPaymentMethod(method),
    });
    final order = apiOrder(body['data'], products);
    ultimoPedidoCriado = order;
    cartItems.clear();
    resetCheckout();
    notifyListeners();
    // O pedido JÁ foi criado; falha ao atualizar a tela não pode solicitar
    // outro envio e duplicar a compra.
    try {
      await atualizarPedidos();
      await atualizarProdutos();
    } catch (error) {
      erroSincronizacao = 'Pedido criado, mas a lista não atualizou: $error';
      notifyListeners();
    }
    return order;
  }

  Future<void> atualizarStatusPedidoOnline(Order order) async {
    final body = await api.get('/orders/${order.id}');
    final latest = apiOrder(body['data'], products);
    order.status = latest.status;
    notifyListeners();
  }

  Future<void> atualizarPerfilOnline({required String nome, required String telefone}) async {
    final body = await api.put('/users/me', {
      'name': nome.trim(), 'phone': telefone.trim(),
    });
    final data = apiMap(body['data']);
    user.nome = apiString(data['name'], nome);
    user.telefone = apiString(data['phone'], telefone);
    notifyListeners();
  }


  // ------------------------------------------------------------------
  // Autenticação
  // ------------------------------------------------------------------
  bool isDarkMode = false;

  void setDarkMode(bool enabled) {
    if (isDarkMode == enabled) return;
    isDarkMode = enabled;
    notifyListeners();
  }

  bool isLoggedIn = false;
  bool isAdmin = false;
  AppUser user = AppUser(
    nome: '',
    email: '',
    telefone: '',
  );

  /// Login local antigo removido: use loginOnline para autenticar no Supabase.
  void logout() {
    if (api.isAuthenticated) {
      unawaited(api.post('/auth/logout', {})
          .then((_) {})
          .catchError((Object _) {}));
    }
    api.clearToken();
    products.clear();
    cartItems.clear();
    favoriteIds.clear();
    orders.clear();
    giftCards.clear();
    ultimoPedidoCriado = null;
    isLoggedIn = false;
    isAdmin = false;

    user.nome = '';
    user.email = '';
    user.telefone = '';
    user.restricoes.clear();
    addresses.clear();
    enderecoSelecionado = null;
    resetCheckout();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Catálogo
  // ------------------------------------------------------------------
  late List<Product> products;

  void addProduct(Product p) {
    products.add(p);
    notifyListeners();
  }

  void updateProduct(Product p) {
    final idx = products.indexWhere((e) => e.id == p.id);
    if (idx != -1) products[idx] = p;
    notifyListeners();
  }

  void removeProduct(String id) {
    products.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Favoritos
  // ------------------------------------------------------------------
  final Set<String> favoriteIds = {};

  bool isFavorite(String productId) => favoriteIds.contains(productId);

  void toggleFavorite(String productId) {
    if (favoriteIds.contains(productId)) {
      favoriteIds.remove(productId);
    } else {
      favoriteIds.add(productId);
    }
    notifyListeners();
  }

  List<Product> get favoriteProducts =>
      products.where((p) => favoriteIds.contains(p.id)).toList();

  // ------------------------------------------------------------------
  // Carrinho
  // ------------------------------------------------------------------
  final List<CartItem> cartItems = [];

  double get cartSubtotal =>
      cartItems.fold(0, (sum, item) => sum + item.subtotal);

  int get cartCount => cartItems.fold(0, (sum, item) => sum + item.quantidade);

  void addToCart(Product product, {int quantidade = 1}) {
    final existing = cartItems.where((c) => c.produto.id == product.id);
    if (existing.isNotEmpty) {
      existing.first.quantidade += quantidade;
    } else {
      cartItems.add(CartItem(produto: product, quantidade: quantidade));
    }
    notifyListeners();
  }

  void incrementCartItem(CartItem item) {
    item.quantidade++;
    notifyListeners();
  }

  void decrementCartItem(CartItem item) {
    item.quantidade--;
    if (item.quantidade <= 0) {
      cartItems.remove(item);
    }
    notifyListeners();
  }

  void removeFromCart(CartItem item) {
    cartItems.remove(item);
    notifyListeners();
  }

  void clearCart() {
    cartItems.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Checkout em andamento
  // ------------------------------------------------------------------
  TipoEntrega tipoEntregaSelecionada = TipoEntrega.delivery;
  Address? enderecoSelecionado;
  MetodoPagamento? metodoPagamentoSelecionado;
  double? trocoPara;

  double get taxaEntregaAtual =>
      tipoEntregaSelecionada == TipoEntrega.delivery ? 5.0 : 0.0;

  void setTipoEntrega(TipoEntrega tipo) {
    tipoEntregaSelecionada = tipo;
    notifyListeners();
  }

  void setEnderecoSelecionado(Address address) {
    enderecoSelecionado = address;
    notifyListeners();
  }

  void setMetodoPagamento(MetodoPagamento metodo) {
    metodoPagamentoSelecionado = metodo;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Endereços
  // ------------------------------------------------------------------
  late List<Address> addresses;

  Address? get enderecoPrincipal {
    if (addresses.isEmpty) return null;
    return addresses.firstWhere(
      (a) => a.principal,
      orElse: () => addresses.first,
    );
  }

  void addAddress(Address address) {
    if (addresses.isEmpty) address.principal = true;
    addresses.add(address);
    notifyListeners();
  }

  void updateAddress(Address address) {
    final idx = addresses.indexWhere((a) => a.id == address.id);
    if (idx != -1) addresses[idx] = address;
    notifyListeners();
  }

  void removeAddress(String id) {
    addresses.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void setEnderecoPrincipal(String id) {
    for (final a in addresses) {
      a.principal = a.id == id;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Pedidos
  // ------------------------------------------------------------------
  final List<Order> orders = [];

  Order createOrder() {
    throw StateError('Pedidos devem ser criados pela API. Use criarPedidoOnline().');
  }

  void resetCheckout() {
    tipoEntregaSelecionada = TipoEntrega.delivery;
    enderecoSelecionado = null;
    metodoPagamentoSelecionado = null;
    trocoPara = null;
  }

  void advanceOrderStatus(Order order) {
    final flow = order.fluxoStatus;
    final idx = flow.indexOf(order.status);
    if (idx != -1 && idx < flow.length - 1) {
      order.status = flow[idx + 1];
      addNotification(
        titulo: 'Atualização do pedido',
        mensagem: 'Pedido ${order.numeroPedido}: ${order.status.label}.',
        icone: Icons.local_shipping_rounded,
      );
      notifyListeners();
    }
  }

  void setOrderStatus(Order order, StatusPedido status) {
    order.status = status;
    notifyListeners();
  }

  List<Order> get ongoingOrders => orders
      .where(
        (o) =>
            o.status != StatusPedido.entregue &&
            o.status != StatusPedido.retirado &&
            o.status != StatusPedido.cancelado,
      )
      .toList();

  List<Order> get historyOrders => orders
      .where(
        (o) =>
            o.status == StatusPedido.entregue ||
            o.status == StatusPedido.retirado ||
            o.status == StatusPedido.cancelado,
      )
      .toList();

  // ------------------------------------------------------------------
  // Vale-presente
  // ------------------------------------------------------------------
  final List<GiftCard> giftCards = [];

  GiftCard buyGiftCard(double valor) {
    final code =
        'DV-${DateTime.now().year}-${IdGen.next('').substring(0, 4).toUpperCase()}';
    final card = GiftCard(
      codigo: code,
      valor: valor,
      validade: DateTime.now().add(const Duration(days: 365)),
    );
    giftCards.add(card);
    notifyListeners();
    return card;
  }

  // ------------------------------------------------------------------
  // Notificações
  // ------------------------------------------------------------------
  late List<AppNotification> notifications;

  int get unreadNotifications => notifications.where((n) => !n.lida).length;

  void addNotification({
    required String titulo,
    required String mensagem,
    required IconData icone,
  }) {
    notifications.insert(
      0,
      AppNotification(
        id: IdGen.next('n'),
        titulo: titulo,
        mensagem: mensagem,
        data: DateTime.now(),
        icone: icone,
      ),
    );
  }

  void markAllNotificationsRead() {
    for (final n in notifications) {
      n.lida = true;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Perfil / restrições do usuário
  // ------------------------------------------------------------------
  void updateProfile({
    required String nome,
    required String email,
    required String telefone,
  }) {
    user.nome = nome;
    user.email = email;
    user.telefone = telefone;
    notifyListeners();
  }

  void updateUserRestrictions(Set<DietaryRestriction> restrictions) {
    user.restricoes = restrictions;
    notifyListeners();
  }
}