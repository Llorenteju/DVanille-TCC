import '../models/models.dart';
import 'mobile_api_service.dart';

Map<String, dynamic> apiMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<dynamic> apiList(Object? value) => value is List ? value : const [];

String apiString(Object? value, [String fallback = '']) =>
    value == null ? fallback : value.toString();

double apiDouble(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : double.tryParse(apiString(value)) ?? fallback;

int apiInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse(apiString(value)) ?? fallback;

ProductCategory apiCategory(Object? source) {
  final category = source is Map ? apiString(source['slug'] ?? source['name']) : apiString(source);
  final value = category.toLowerCase().replaceAll(' ', '-').replaceAll('_', '-');
  if (value.contains('salgad')) return ProductCategory.salgados;
  if (value.contains('sobremesa')) return ProductCategory.sobremesasGeladas;
  if (value.contains('bebida') && (value.contains('quente') || value.contains('hot'))) return ProductCategory.bebidasQuentes;
  if (value.contains('bebida') && (value.contains('gelada') || value.contains('cold'))) return ProductCategory.bebidasGeladas;
  if (value.contains('bolo')) return ProductCategory.bolos;
  return ProductCategory.doces;
}

const _verifiedSlugs = <String, DietaryRestriction>{
  'sem-aplv': DietaryRestriction.aplv,
  'sem-soja': DietaryRestriction.soja,
  'sem-oleaginosas': DietaryRestriction.oleaginosas,
  'sem-acucar-adicionado': DietaryRestriction.semAcucarAdicionado,
  'sem-sal-adicionado': DietaryRestriction.semSalAdicionado,
  'low-fodmap': DietaryRestriction.fodmap,
  'low-carb': DietaryRestriction.lowCarb,
  'sem-aditivos-artificiais': DietaryRestriction.semAditivosArtificiais,
  'vegano': DietaryRestriction.vegano,
  'vegetariano': DietaryRestriction.vegetariano,
  'sem-lactose': DietaryRestriction.lactose,
  'sem-gluten': DietaryRestriction.semGluten,
};

/// Os selos alimentares só são atribuídos quando a API fornece um vínculo
/// explícito em restricoesAlimentares/dietaryRestrictions.
Product apiProduct(Object? source, MobileApiService api) {
  final p = apiMap(source);
  final slugs = <String>{};
  for (final value in apiList(p['restricoesAlimentares'])) {
    if (value is String) slugs.add(value);
  }
  for (final value in apiList(p['dietaryRestrictions'])) {
    final item = apiMap(value);
    final slug = apiString(item['slug']);
    if (slug.isNotEmpty) slugs.add(slug);
  }
  final verified = <DietaryRestriction>{};
  for (final slug in slugs) {
    final restriction = _verifiedSlugs[slug];
    if (restriction != null) verified.add(restriction);
  }
  final rawIngredients = p['ingredients'];
  final ingredients = rawIngredients is List
      ? rawIngredients.map((e) => apiString(e)).toList()
      : apiString(rawIngredients).split(RegExp(r'[,;\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final rawAllergens = p['allergens'];
  final allergens = rawAllergens is List
      ? rawAllergens.map((e) => apiString(e)).toList()
      : apiString(rawAllergens).split(RegExp(r'[,;\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final promo = p['promotionalPrice'];
  final price = apiDouble(p['price']);
  final promoPrice = promo == null ? null : apiDouble(promo);
  final isPromo = promoPrice != null && promoPrice > 0 && promoPrice < price;
  return Product(
    id: apiString(p['id']),
    nome: apiString(p['name'], 'Produto'),
    descricao: apiString(p['description']),
    categoria: apiCategory(p['category']),
    preco: price,
    imagem: api.imageUrl(apiString(p['image'])),
    ingredientes: ingredients,
    alergenicos: allergens,
    restricoes: verified,
    popular: p['isFeatured'] == true,
    emOferta: isPromo,
    precoOferta: isPromo ? promoPrice : null,
    stock: apiInt(p['stock']),
    disponivel: p['isAvailable'] == true && p['isActive'] != false,
    nutricao: NutritionInfo(
      calorias: apiInt(p['calories']),
      carboidratos: apiDouble(p['carbohydrates']),
      proteinas: apiDouble(p['proteins']),
      gorduraTotal: apiDouble(p['fats']),
      sodio: apiDouble(p['sodium']),
      glutenStatus: 'Não informado',
    ),
  );
}

Address apiAddress(Object? source) {
  final a = apiMap(source);
  return Address(
    id: apiString(a['id']),
    apelido: apiString(a['label'], 'Casa'),
    cep: apiString(a['zipCode']),
    rua: apiString(a['street']),
    numero: apiString(a['number']),
    complemento: apiString(a['complement']),
    bairro: apiString(a['neighborhood']),
    cidade: apiString(a['city']),
    estado: apiString(a['state']),
    principal: a['isDefault'] == true,
  );
}

String _paymentName(MetodoPagamento payment) => switch (payment) {
  MetodoPagamento.dinheiro => 'CASH',
  MetodoPagamento.pix => 'PIX',
  MetodoPagamento.cartaoCredito => 'CREDIT_CARD',
  MetodoPagamento.cartaoDebito => 'DEBIT_CARD',
  MetodoPagamento.carteira => 'UNSUPPORTED',
};

String apiPaymentMethod(MetodoPagamento payment) => _paymentName(payment);

MetodoPagamento _paymentFromApi(String raw) => switch (raw) {
  'CASH' => MetodoPagamento.dinheiro,
  'CREDIT_CARD' => MetodoPagamento.cartaoCredito,
  'DEBIT_CARD' => MetodoPagamento.cartaoDebito,
  _ => MetodoPagamento.pix,
};

StatusPedido _statusFromApi(String raw, TipoEntrega delivery) => switch (raw) {
  'PREPARING' => StatusPedido.emPreparacao,
  'READY' => StatusPedido.prontoRetirada,
  'OUT_FOR_DELIVERY' => StatusPedido.saiuEntrega,
  'DELIVERED' => delivery == TipoEntrega.retirada ? StatusPedido.retirado : StatusPedido.entregue,
  'CANCELLED' => StatusPedido.cancelado,
  _ => StatusPedido.recebido,
};

Order apiOrder(Object? source, List<Product> products) {
  final data = apiMap(source);
  final delivery = apiString(data['deliveryType']) == 'PICKUP' ? TipoEntrega.retirada : TipoEntrega.delivery;
  final items = <CartItem>[];
  for (final itemData in apiList(data['items'])) {
    final item = apiMap(itemData);
    final id = apiString(item['productId']);
    final existing = products.where((p) => p.id == id);
    final p = existing.isNotEmpty
        ? existing.first
        : Product(
            id: id,
            nome: apiString(item['productName'], 'Produto'),
            descricao: '',
            categoria: ProductCategory.doces,
            preco: apiDouble(item['unitPrice']),
            imagem: '',
          );
    final productSnapshot = Product(
      id: p.id,
      nome: apiString(item['productName'], p.nome),
      descricao: p.descricao,
      categoria: p.categoria,
      preco: apiDouble(item['unitPrice'], p.preco),
      imagem: p.imagem,
    );
    items.add(CartItem(produto: productSnapshot, quantidade: apiInt(item['quantity'], 1)));
  }
  final createdAt = DateTime.tryParse(apiString(data['createdAt'])) ?? DateTime.now();
  final addressData = apiMap(data['deliveryAddress']);
  return Order(
    id: apiString(data['id']),
    numeroPedido: apiString(data['orderNumber'], '#${apiString(data['id'])}'),
    data: createdAt.toLocal(),
    produtos: items,
    subtotal: apiDouble(data['subtotal']),
    taxaEntrega: apiDouble(data['deliveryFee']),
    total: apiDouble(data['total']),
    tipoEntrega: delivery,
    endereco: addressData.isEmpty ? null : apiAddress(addressData),
    metodoPagamento: _paymentFromApi(apiString(data['paymentMethod'])),
    status: _statusFromApi(apiString(data['orderStatus']), delivery),
    observacoes: apiString(data['notes']),
  );
}
