const prisma = require('../config/database');
const AppError = require('../utils/AppError');
const { parsePagination, buildPagination } = require('../utils/pagination');
const { generateUniqueSlug } = require('../utils/slug');
const { getEffectivePrice, isOnPromotion } = require('../utils/money');
const { toPublicPath, removeStoredFile } = require('../utils/storage');

// O backend original também roda com o Prisma MySQL, que não possui estas tabelas.
// Detectamos as operações disponíveis no Prisma Client gerado, sem consultar ou alterar o banco.
const hasDietaryRelations = Boolean(prisma.productRestriction && prisma.dietaryRestriction);

const productInclude = {
  category: { select: { id: true, name: true, slug: true } },
  ...(hasDietaryRelations ? {
    restricoesAlimentares: {
      select: {
        restriction: { select: { id: true, name: true, slug: true } },
      },
    },
  } : {}),
};


// Exigimos VÍNCULO EXPLÍCITO com uma restrição validada, nunca inferimos
// "sem alérgenos" a partir dos booleanos containsX que têm default false.
// Alguns filtros legados NÃO equivalem a nenhum dos 12 selos do projeto:
// eles retornam zero itens em vez de emitir uma afirmação alimentar insegura.
const VERIFIED_LEGACY_FILTERS = {
  glutenFree: 'sem-gluten',
  lactoseFree: 'sem-lactose',
  soyFree: 'sem-soja',
  nutFree: 'sem-oleaginosas',
  vegan: 'vegano',
  vegetarian: 'vegetariano',
};
const UNVERIFIABLE_LEGACY_FILTERS = ['milkFree', 'eggFree', 'peanutFree', 'sugarFree'];

const SORT_OPTIONS = {
  name: (order) => ({ name: order }),
  price: (order) => ({ price: order }),
  newest: (order) => ({ createdAt: order }),
  featured: () => [{ isFeatured: 'desc' }, { name: 'asc' }],
};

const isTrue = (value) => value === true || value === 'true' || value === '1';

/**
 * Retorna apenas restrições COM vínculo explícito no banco.
 * product_restrictions vazio significa "não verificado", e NÃO "livre de alérgenos".
 * Converte o id BigInt para Number para evitar falha ao serializar JSON.
 */
function serializeProduct(product) {
  if (!product) return product;

  const { restricoesAlimentares: associations, ...attributes } = product;
  const verified = hasDietaryRelations && Array.isArray(associations)
    ? associations.map((link) => link.restriction).filter(Boolean)
    : [];
  const slugs = verified.map((restriction) => restriction.slug);
  const has = (slug) => slugs.includes(slug);

  return {
    ...attributes,
    effectivePrice: getEffectivePrice(product),
    isOnPromotion: isOnPromotion(product),
    inStock: product.isActive && product.isAvailable && product.stock > 0,
    // Associação cadastrada não substitui validação técnica de ingredientes e contaminação cruzada.
    dietaryClassificationStatus: verified.length ? 'HAS_EXPLICIT_LINKS' : 'UNCLASSIFIED',
    // Formato lido pelo Flutter Web atual.
    restricoesAlimentares: slugs,
    // Formato detalhado para o formulário administrativo.
    dietaryRestrictions: verified.map((r) => ({ id: Number(r.id), name: r.name, slug: r.slug })),
    dietary: {
      glutenFree: has('sem-gluten'),
      lactoseFree: has('sem-lactose'),
      soyFree: has('sem-soja'),
      nutFree: has('sem-oleaginosas'),
      vegetarian: has('vegetariano'),
      vegan: has('vegano'),
      // Não existem critérios verificados correspondentes a estes quatro filtros legados.
      milkFree: false,
      eggFree: false,
      peanutFree: false,
      sugarFree: false,
    },
  };
}

function dietaryConditions(filters) {
  const slugs = [];
  for (const [parameter, slug] of Object.entries(VERIFIED_LEGACY_FILTERS)) {
    if (isTrue(filters[parameter])) slugs.push(slug);
  }
  for (const parameter of UNVERIFIABLE_LEGACY_FILTERS) {
    if (isTrue(filters[parameter])) return { impossible: true, slugs: [] };
  }
  if (filters.restrictions) {
    slugs.push(...String(filters.restrictions).split(',').map((x) => x.trim()).filter(Boolean));
  }
  return { impossible: false, slugs: [...new Set(slugs)] };
}

function buildProductWhere(filters = {}, { includeInactive = false } = {}) {
  const and = [];
  const where = {};

  if (!includeInactive) {
    where.isActive = true;
    where.category = { isActive: true };
  }

  if (filters.search) {
    and.push({ OR: [{ name: { contains: filters.search } }, { description: { contains: filters.search } }] });
  }

  if (filters.categoryId) where.categoryId = Number(filters.categoryId);
  if (filters.category) {
    where.category = { ...(where.category || {}), slug: String(filters.category) };
  }

  // Preço considerado = preço promocional (quando existe) ou preço normal.
  const range = {};
  if (filters.minPrice !== undefined && filters.minPrice !== '') range.gte = Number(filters.minPrice);
  if (filters.maxPrice !== undefined && filters.maxPrice !== '') range.lte = Number(filters.maxPrice);
  if (Object.keys(range).length > 0) {
    and.push({
      OR: [{ promotionalPrice: { not: null, ...range } }, { promotionalPrice: null, price: range }],
    });
  }

  if (isTrue(filters.onPromotion)) where.promotionalPrice = { not: null };
  if (filters.featured !== undefined && filters.featured !== '') where.isFeatured = isTrue(filters.featured);
  if (isTrue(filters.available)) {
    where.isAvailable = true;
    where.stock = { gt: 0 };
  }

  const dietary = dietaryConditions(filters);
  if (dietary.impossible || (dietary.slugs.length > 0 && !hasDietaryRelations)) {
    // Fail-closed: banco sem vínculos não pode apresentar produto como seguro.
    and.push({ id: -1 });
  } else {
    // Cada selo selecionado deve possuir um vínculo EXPLÍCITO no Supabase.
    for (const slug of dietary.slugs) {
      and.push({ restricoesAlimentares: { some: { restriction: { slug, isActive: true } } } });
    }
  }

  if (and.length > 0) where.AND = and;
  return where;
}

async function listProducts(query = {}, { includeInactive = false } = {}) {
  const { page, limit, skip, take } = parsePagination(query);
  const where = buildProductWhere(query, { includeInactive });

  const order = query.order === 'desc' ? 'desc' : 'asc';
  const sortBuilder = SORT_OPTIONS[query.sort] || SORT_OPTIONS.name;

  const [items, total] = await Promise.all([
    prisma.product.findMany({ where, include: productInclude, orderBy: sortBuilder(order), skip, take }),
    prisma.product.count({ where }),
  ]);

  return { items: items.map(serializeProduct), pagination: buildPagination({ page, limit, total }) };
}

async function getRatingSummary(productId) {
  const aggregate = await prisma.review.aggregate({
    where: { productId },
    _avg: { rating: true },
    _count: { rating: true },
  });

  return {
    average: aggregate._avg.rating ? Math.round(aggregate._avg.rating * 10) / 10 : null,
    count: aggregate._count.rating,
  };
}

/** Aceita id numérico ou slug. */
async function getProduct(idOrSlug, { includeInactive = false } = {}) {
  const isNumeric = /^\d+$/.test(String(idOrSlug));
  const product = await prisma.product.findFirst({
    where: {
      ...(isNumeric ? { id: Number(idOrSlug) } : { slug: String(idOrSlug) }),
      ...(includeInactive ? {} : { isActive: true }),
    },
    include: productInclude,
  });

  if (!product) throw AppError.notFound('Produto não encontrado.');

  const rating = await getRatingSummary(product.id);
  return { ...serializeProduct(product), rating };
}

async function getAvailability(id) {
  const product = await prisma.product.findFirst({
    where: { id, isActive: true },
    select: { id: true, name: true, isAvailable: true, stock: true },
  });
  if (!product) throw AppError.notFound('Produto não encontrado.');

  const inStock = product.isAvailable && product.stock > 0;
  return {
    productId: product.id,
    name: product.name,
    isAvailable: product.isAvailable,
    stock: product.stock,
    inStock,
    maxQuantity: inStock ? product.stock : 0,
  };
}

/** Regras de coerência dos dados (usado em criação e edição, já com os dados mesclados). */
function assertProductRules(data) {
  const errors = [];

  if (data.promotionalPrice !== null && data.promotionalPrice !== undefined) {
    if (Number(data.promotionalPrice) >= Number(data.price)) {
      errors.push({ field: 'promotionalPrice', message: 'O preço promocional deve ser menor que o preço normal.' });
    }
  }

  if (data.isVegan) {
    if (!data.isVegetarian) {
      errors.push({ field: 'isVegetarian', message: 'Produto vegano também deve ser marcado como vegetariano.' });
    }
    ['containsMilk', 'containsLactose', 'containsEggs'].forEach((field) => {
      if (data[field]) errors.push({ field, message: 'Produto vegano não pode conter leite, lactose ou ovos.' });
    });
  }

  if (data.containsLactose && !data.containsMilk) {
    // Lactose vem do leite; mantém o dado consistente para os filtros.
    errors.push({ field: 'containsMilk', message: 'Se contém lactose, também contém leite.' });
  }

  if (errors.length > 0) throw AppError.unprocessable('Dados do produto inconsistentes.', errors);
}

async function assertCategoryUsable(categoryId) {
  const category = await prisma.category.findUnique({ where: { id: categoryId }, select: { id: true } });
  if (!category) {
    throw AppError.unprocessable('Categoria inexistente.', [{ field: 'categoryId', message: 'Categoria inexistente.' }]);
  }
}

async function assertSkuAvailable(sku, excludeId = null) {
  if (!sku) return;
  const existing = await prisma.product.findUnique({ where: { sku }, select: { id: true } });
  if (existing && existing.id !== excludeId) {
    throw AppError.conflict('Já existe um produto com este SKU.', [{ field: 'sku', message: 'SKU já utilizado.' }]);
  }
}

// Chamado somente após a validação de formato no controller.
// Não confundir IDs de doença/preferência da conta com os 12 selos do cardápio.
async function verifyRestrictionIds(restrictionIds) {
  if (restrictionIds === undefined) return null;
  if (!hasDietaryRelations) {
    throw new AppError('Este banco ainda não possui suporte a vínculos alimentares.', 501);
  }
  if (!Array.isArray(restrictionIds)) {
    throw AppError.unprocessable('restrictionIds deve ser uma lista.');
  }
  const ids = restrictionIds.map(Number);
  if (ids.some((id) => !Number.isSafeInteger(id) || id <= 0) || new Set(ids).size !== ids.length) {
    throw AppError.unprocessable('IDs de restrições inválidos ou repetidos.');
  }
  if (ids.length === 0) return [];

  const active = await prisma.dietaryRestriction.findMany({
    where: { id: { in: ids.map(BigInt) }, isActive: true },
    select: { id: true },
  });
  if (active.length !== ids.length) {
    throw AppError.unprocessable('Uma ou mais restrições não existem ou estão inativas.');
  }
  return ids.map(BigInt);
}

/**
 * Criação/edição com vínculos atômicos (transação).
 * Sem restrictionIds => não alterar vínculos em edição; lista [] => remover vínculos.
 * A interface administrativa deve exigir revisão das declarações antes de enviar IDs.
 */
async function createProduct(data) {
  const { restrictionIds, ...productData } = data;
  await assertCategoryUsable(productData.categoryId);
  await assertSkuAvailable(productData.sku);
  assertProductRules({
    ...productData,
    isVegetarian: productData.isVegetarian || false,
    isVegan: productData.isVegan || false,
  });
  const ids = await verifyRestrictionIds(restrictionIds);
  const slug = await generateUniqueSlug(prisma.product, productData.name);

  if (ids === null || ids.length === 0) {
    const product = await prisma.product.create({ data: { ...productData, slug }, include: productInclude });
    return serializeProduct(product);
  }
  const product = await prisma.$transaction(async (tx) => {
    const created = await tx.product.create({ data: { ...productData, slug } });
    await tx.productRestriction.createMany({
      data: ids.map((restrictionId) => ({ productId: created.id, restrictionId })),
    });
    return tx.product.findUnique({ where: { id: created.id }, include: productInclude });
  });
  return serializeProduct(product);
}

async function updateProduct(id, data) {
  const { restrictionIds, ...productData } = data;
  const current = await prisma.product.findUnique({ where: { id } });
  if (!current) throw AppError.notFound('Produto não encontrado.');

  if (productData.categoryId !== undefined) await assertCategoryUsable(productData.categoryId);
  if (productData.sku !== undefined) await assertSkuAvailable(productData.sku, id);
  assertProductRules({ ...current, ...productData });

  const ids = await verifyRestrictionIds(restrictionIds);
  if (ids === null) {
    const product = await prisma.product.update({ where: { id }, data: productData, include: productInclude });
    return serializeProduct(product);
  }
  const product = await prisma.$transaction(async (tx) => {
    if (Object.keys(productData).length > 0) {
      await tx.product.update({ where: { id }, data: productData });
    }
    await tx.productRestriction.deleteMany({ where: { productId: id } });
    if (ids.length > 0) {
      await tx.productRestriction.createMany({
        data: ids.map((restrictionId) => ({ productId: id, restrictionId })),
      });
    }
    return tx.product.findUnique({ where: { id }, include: productInclude });
  });
  return serializeProduct(product);
}

/**
 * Exclui o produto se ele nunca foi vendido; caso contrário apenas desativa,
 * preservando o histórico de pedidos.
 */
async function deleteProduct(id) {
  const product = await prisma.product.findUnique({
    where: { id },
    include: { _count: { select: { orderItems: true } } },
  });
  if (!product) throw AppError.notFound('Produto não encontrado.');

  if (product._count.orderItems === 0) {
    await prisma.product.delete({ where: { id } });
    await removeStoredFile(product.image);
    return { deleted: true, deactivated: false };
  }

  await prisma.product.update({ where: { id }, data: { isActive: false, isAvailable: false } });
  return { deleted: false, deactivated: true };
}

async function setProductImage(id, filename) {
  const current = await prisma.product.findUnique({ where: { id }, select: { image: true } });
  const publicPath = toPublicPath('products', filename);

  if (!current) {
    await removeStoredFile(publicPath);
    throw AppError.notFound('Produto não encontrado.');
  }

  const product = await prisma.product.update({ where: { id }, data: { image: publicPath }, include: productInclude });
  await removeStoredFile(current.image);
  return serializeProduct(product);
}

// ---------- Estoque (admin) ----------

/** Define o estoque absoluto (stock) ou aplica uma variação (adjustment, pode ser negativa). */
async function updateStock(id, { stock, adjustment }) {
  const exists = await prisma.product.findUnique({ where: { id }, select: { id: true } });
  if (!exists) throw AppError.notFound('Produto não encontrado.');

  if (stock !== undefined) {
    await prisma.product.update({ where: { id }, data: { stock } });
  } else {
    // Condicional no banco: nunca deixa o estoque negativo, mesmo com concorrência.
    const result = await prisma.product.updateMany({
      where: { id, ...(adjustment < 0 ? { stock: { gte: -adjustment } } : {}) },
      data: { stock: { increment: adjustment } },
    });
    if (result.count !== 1) throw AppError.conflict('Ajuste inválido: o estoque não pode ficar negativo.');
  }

  const product = await prisma.product.findUnique({ where: { id }, include: productInclude });
  return serializeProduct(product);
}

async function listStock(query = {}) {
  const { page, limit, skip, take } = parsePagination(query);
  const threshold = Number.isNaN(parseInt(query.threshold, 10)) ? 10 : parseInt(query.threshold, 10);

  const where = { isActive: true };
  if (isTrue(query.lowStock)) where.stock = { lte: threshold };
  if (query.search) where.OR = [{ name: { contains: query.search } }, { sku: { contains: query.search } }];

  const [items, total] = await Promise.all([
    prisma.product.findMany({
      where,
      select: { id: true, name: true, sku: true, stock: true, isAvailable: true, category: { select: { id: true, name: true } } },
      orderBy: [{ stock: 'asc' }, { name: 'asc' }],
      skip,
      take,
    }),
    prisma.product.count({ where }),
  ]);

  return { items, pagination: buildPagination({ page, limit, total }), lowStockThreshold: threshold };
}

module.exports = {
  productInclude,
  serializeProduct,
  buildProductWhere,
  listProducts,
  getProduct,
  getAvailability,
  createProduct,
  updateProduct,
  deleteProduct,
  setProductImage,
  updateStock,
  listStock,
};
