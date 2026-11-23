'use strict';
const crypto = require('node:crypto');
const prisma = require('../config/database');
const AppError = require('../utils/AppError');

const NEXT_STATUSES = Object.freeze({
  recebido: ['em preparação', 'cancelado'],
  'em preparação': ['pronto', 'cancelado'],
  pronto: ['finalizado', 'cancelado'],
  finalizado: [], cancelado: [],
});
function table(value) {
  if (typeof value !== 'string' || !/^[0-9A-Za-z-]{1,16}$/.test(value)) {
    throw AppError.unprocessable('Identificador de mesa inválido.');
  }
  return value;
}
function qrSecret() {
  const secret = process.env.DVANILLE_TABLE_QR_SECRET || '';
  if (secret.length < 32) {
    throw AppError.forbidden('QRCode da mesa não configurado pelo administrador.');
  }
  return secret;
}
function tokenForTable(value) {
  return crypto.createHmac('sha256', qrSecret()).update(`DVANILLE:MESA:${table(value)}`).digest('hex');
}
function verifyTableToken(value, qrToken) {
  const expected = Buffer.from(tokenForTable(value), 'hex');
  if (typeof qrToken !== 'string' || !/^[0-9a-f]{64}$/i.test(qrToken)) {
    throw AppError.forbidden('Abra a comanda pelo QR Code válido da mesa.');
  }
  const received = Buffer.from(qrToken, 'hex');
  if (received.length !== expected.length || !crypto.timingSafeEqual(received, expected)) {
    throw AppError.forbidden('QR Code da mesa inválido.');
  }
}
function serialize(order, items = []) {
  return {
    id: order.id, table: order.table_label, status: order.status,
    subtotal: Number(order.subtotal_cents) / 100,
    discount: Number(order.discount_cents) / 100,
    total: Number(order.total_cents) / 100,
    coupon: order.coupon || null, userId: Number(order.user_id),
    buyerEmail: order.buyer_email,
    createdAt: order.created_at, updatedAt: order.updated_at,
    items: items.map(item => ({ productId: Number(item.product_id), name: item.product_name,
      quantity: Number(item.quantity), price: Number(item.unit_price_cents) / 100 })),
  };
}
async function readOrder(db, id) {
  const rows = await db.$queryRaw`SELECT * FROM table_orders WHERE id = ${id} LIMIT 1`;
  if (!rows.length) throw AppError.notFound('Pedido da mesa não encontrado.');
  const items = await db.$queryRaw`SELECT * FROM table_order_items WHERE table_order_id = ${id} ORDER BY created_at ASC`;
  return serialize(rows[0], items);
}
async function create(user, input) {
  if (user.role !== 'CUSTOMER') throw AppError.forbidden('Contas administrativas não fazem pedidos de mesa.');
  const mesa = table((input || {}).table);
  verifyTableToken(mesa, input.qrToken);
  const requestId = String(input.requestId || '');
  if (!/^[0-9A-Za-z-]{8,80}$/.test(requestId)) throw AppError.unprocessable('Identificador de envio inválido.');
  if (input.coupon) {
    throw AppError.unprocessable('Este cupom ainda não está validado no caixa. Remova o cupom para enviar o pedido.');
  }
  const rawItems = input.items;
  if (!Array.isArray(rawItems) || rawItems.length < 1 || rawItems.length > 20) {
    throw AppError.unprocessable('A comanda deve conter entre 1 e 20 produtos.');
  }
  const byId = new Map();
  for (const rawItem of rawItems) {
    const id = Number(rawItem.productId), quantity = Number(rawItem.quantity);
    if (!Number.isSafeInteger(id) || id <= 0 || !Number.isSafeInteger(quantity) || quantity < 1 || quantity > 30) {
      throw AppError.unprocessable('Itens de pedido inválidos.');
    }
    byId.set(id, (byId.get(id) || 0) + quantity);
  }
  if ([...byId.values()].some(quantity => quantity > 30)) {
    throw AppError.unprocessable('Quantidade por produto excedida.');
  }
  // Idempotência: se a conexão cair após gravar, um novo clique não duplica o pedido.
  const exists = await prisma.$queryRaw`SELECT id, user_id FROM table_orders WHERE client_request_id = ${requestId} LIMIT 1`;
  if (exists.length) {
    if (Number(exists[0].user_id) !== user.id) throw AppError.conflict('Identificador de envio já utilizado.');
    return readOrder(prisma, exists[0].id);
  }
  const ids = [...byId.keys()];
  const products = await prisma.product.findMany({
    where: { id: { in: ids }, isActive: true, isAvailable: true },
    select: { id: true, name: true, price: true, promotionalPrice: true },
  });
  if (products.length !== ids.length) throw AppError.unprocessable('Um ou mais produtos não estão disponíveis.');
  let cents = 0;
  const items = products.map(product => {
    const quantity = byId.get(product.id);
    const price = Number(product.promotionalPrice ?? product.price);
    const unitCents = Math.round(price * 100);
    if (!Number.isSafeInteger(unitCents) || unitCents < 1) {
      throw AppError.unprocessable('Preço de produto inválido.');
    }
    cents += unitCents * quantity;
    return { productId: product.id, name: product.name, quantity, unitCents };
  });
  if (cents > 10000000) throw AppError.unprocessable('Valor do pedido excedido.');

  try {
    return await prisma.$transaction(async tx => {
      // Baixa o estoque na mesma transacao que registra a comanda.
      // Ordem deterministica de produtos reduz conflitos entre pedidos simultaneos.
      for (const item of [...items].sort((a, b) => a.productId - b.productId)) {
        const reserved = await tx.product.updateMany({
          where: {
            id: item.productId,
            isActive: true,
            isAvailable: true,
            stock: { gte: item.quantity },
          },
          data: { stock: { decrement: item.quantity } },
        });
        if (reserved.count !== 1) {
          throw AppError.conflict(`Estoque insuficiente para "${item.name}". Atualize a comanda.`);
        }
      }

      const id = crypto.randomUUID();
      await tx.$executeRaw`
        INSERT INTO table_orders (id, client_request_id, table_label, user_id, buyer_email,
          subtotal_cents, discount_cents, total_cents, status, coupon, created_at, updated_at)
        VALUES (${id}, ${requestId}, ${mesa}, ${user.id}, ${user.email},
          ${cents}, 0, ${cents}, 'recebido', NULL, NOW(), NOW())
      `;
      for (const item of items) {
        const itemId = crypto.randomUUID();
        await tx.$executeRaw`
          INSERT INTO table_order_items (id, table_order_id, product_id, product_name,
            quantity, unit_price_cents, created_at)
          VALUES (${itemId}, ${id}, ${item.productId}, ${item.name},
            ${item.quantity}, ${item.unitCents}, NOW())
        `;
      }
      return readOrder(tx, id);
    });
  } catch (error) {
    const duplicate = await prisma.$queryRaw`SELECT id, user_id FROM table_orders WHERE client_request_id = ${requestId} LIMIT 1`;
    if (duplicate.length && Number(duplicate[0].user_id) === user.id) return readOrder(prisma, duplicate[0].id);
    throw error;
  }
}
async function listMine(user) {
  if (user.role !== 'CUSTOMER') throw AppError.forbidden('Acesso somente para clientes.');
  const rows = await prisma.$queryRaw`SELECT * FROM table_orders WHERE user_id = ${user.id} ORDER BY created_at DESC LIMIT 80`;
  const out = [];
  for (const row of rows) out.push(await readOrder(prisma, row.id));
  return out;
}
async function listAdmin() {
  const rows = await prisma.$queryRaw`SELECT * FROM table_orders ORDER BY created_at DESC LIMIT 100`;
  const out = [];
  for (const row of rows) out.push(await readOrder(prisma, row.id));
  return out;
}
async function updateStatus(id, nextStatus) {
  if (typeof id !== 'string' || !/^[0-9a-f-]{36}$/i.test(id)) throw AppError.unprocessable('ID inválido.');
  if (typeof nextStatus !== 'string' || !Object.hasOwn(NEXT_STATUSES, nextStatus)) {
    throw AppError.unprocessable('Status inválido.');
  }
  const old = await readOrder(prisma, id);
  if (old.status === nextStatus) return old;
  if (!NEXT_STATUSES[old.status]?.includes(nextStatus)) throw AppError.conflict('Mudança de status não permitida.');
  const changed = await prisma.$executeRaw`
    UPDATE table_orders SET status = ${nextStatus}, updated_at = NOW()
    WHERE id = ${id} AND status = ${old.status}
  `;
  if (changed !== 1) throw AppError.conflict('Pedido alterado por outro operador. Atualize a tela.');
  return readOrder(prisma, id);
}
module.exports = { create, listMine, listAdmin, updateStatus, table, tokenForTable };
