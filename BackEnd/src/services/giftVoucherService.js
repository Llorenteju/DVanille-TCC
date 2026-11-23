'use strict';

const crypto = require('node:crypto');
const prisma = require('../config/database');
const AppError = require('../utils/AppError');

const ALLOWED_CENTS = new Set([3000, 5000, 10000, 15000]);
const MAX_ITEMS = 20;

// Feriados nacionais de data fixa. Datas móveis precisam ser revistas anualmente
// antes de qualquer operação comercial real.
const FIXED_HOLIDAYS = new Set([
  '01-01', '04-21', '05-01', '09-07', '10-12', '11-02', '11-15', '11-20', '12-25',
]);

function nextBusinessExpiry(start = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(start);
  const map = Object.fromEntries(parts.map(part => [part.type, part.value]));
  let date = new Date(Date.UTC(Number(map.year), Number(map.month) - 1, Number(map.day)));
  let count = 0;
  while (count < 30) {
    date.setUTCDate(date.getUTCDate() + 1);
    const weekday = date.getUTCDay();
    const fixed = `${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`;
    if (weekday !== 0 && weekday !== 6 && !FIXED_HOLIDAYS.has(fixed)) count++;
  }
  // 23:59:59 America/Sao_Paulo no dia do vencimento (UTC-3).
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1, 2, 59, 59));
}

function statusOf(row) {
  if (row.status === 'ativo' && new Date(row.expires_at).getTime() < Date.now()) return 'expirado';
  return row.status;
}
function serialize(row) {
  return {
    id: row.id, code: row.code, value: Number(row.face_value_cents) / 100,
    recipient: row.recipient, message: row.message || '',
    buyerEmail: row.buyer_email, status: statusOf(row),
    createdAt: row.created_at, expiresAt: row.expires_at, redeemedAt: row.redeemed_at,
  };
}
function checkUser(user) {
  if (user.role !== 'CUSTOMER') throw AppError.forbidden('Esta operação é exclusiva de clientes.');
}
function checkId(value) {
  if (typeof value !== 'string' || !/^[a-zA-Z0-9-]{3,80}$/.test(value)) {
    throw AppError.unprocessable('Identificador da solicitação inválido.');
  }
  return value;
}
function validateItems(items) {
  if (!Array.isArray(items) || items.length < 1 || items.length > MAX_ITEMS) {
    throw AppError.unprocessable('Informe entre 1 e 20 vales.');
  }
  let totalQty = 0;
  const normalized = items.map(item => {
    const value = Number(item.value);
    const cents = Math.round(value * 100);
    const quantity = Number(item.quantity ?? 1);
    const recipient = String(item.recipient ?? '').trim();
    const message = String(item.message ?? '').trim();
    if (!Number.isFinite(value) || !ALLOWED_CENTS.has(cents) ||
        !Number.isInteger(quantity) || quantity < 1 || quantity > 10 ||
        recipient.length < 1 || recipient.length > 120 || message.length > 500) {
      throw AppError.unprocessable('Confira o valor, a quantidade e o destinatário dos vales.');
    }
    totalQty += quantity;
    return { cents, quantity, recipient, message };
  });
  if (totalQty > MAX_ITEMS) throw AppError.unprocessable('Limite de 20 vales por solicitação.');
  return normalized;
}

async function issueDemo(user, body) {
  checkUser(user);
  // Nunca emitir crédito como se uma compra tivesse sido realmente paga.
  if (process.env.NODE_ENV === 'production' || process.env.DVANILLE_DEMO_GIFT_ISSUANCE !== 'true') {
    throw AppError.forbidden('Emissão demonstrativa desativada. É necessária confirmação de pagamento real.');
  }
  const requestId = checkId((body || {}).requestId);
  const normalized = validateItems((body || {}).items);
  const existing = await prisma.$queryRaw`
    SELECT * FROM gift_vouchers WHERE buyer_id = ${user.id} AND client_request_id = ${requestId} ORDER BY item_index ASC
  `;
  if (existing.length) return existing.map(serialize);

  const expiry = nextBusinessExpiry();
  try {
    return await prisma.$transaction(async tx => {
      let index = 0;
      for (const item of normalized) {
        for (let i = 0; i < item.quantity; i++) {
          index++;
          const id = crypto.randomUUID();
          const code = `DVAN-${crypto.randomBytes(10).toString('hex').toUpperCase()}`;
          await tx.$executeRaw`
            INSERT INTO gift_vouchers
              (id, code, buyer_id, buyer_email, face_value_cents, recipient, message,
               status, expires_at, client_request_id, item_index, created_at, updated_at)
            VALUES
              (${id}, ${code}, ${user.id}, ${user.email}, ${item.cents}, ${item.recipient}, ${item.message},
               'ativo', ${expiry}, ${requestId}, ${index}, NOW(), NOW())
          `;
        }
      }
      const created = await tx.$queryRaw`SELECT * FROM gift_vouchers WHERE buyer_id = ${user.id} AND client_request_id = ${requestId} ORDER BY item_index ASC`;
      return created.map(serialize);
    });
  } catch (error) {
    // Requisição repetida em dois cliques: devolver somente o lote já registrado.
    const duplicate = await prisma.$queryRaw`
      SELECT * FROM gift_vouchers WHERE buyer_id = ${user.id} AND client_request_id = ${requestId} ORDER BY item_index ASC
    `;
    if (duplicate.length) return duplicate.map(serialize);
    throw error;
  }
}

async function listMine(user) {
  checkUser(user);
  const rows = await prisma.$queryRaw`SELECT * FROM gift_vouchers WHERE buyer_id = ${user.id} ORDER BY created_at DESC LIMIT 200`;
  return rows.map(serialize);
}
async function listAdmin() {
  const rows = await prisma.$queryRaw`SELECT * FROM gift_vouchers ORDER BY created_at DESC LIMIT 500`;
  return rows.map(serialize);
}
async function redeem(code) {
  if (typeof code !== 'string' || !/^DVAN-[0-9A-F]{20}$/i.test(code)) {
    throw AppError.unprocessable('Código de vale-presente inválido.');
  }
  const normalized = code.toUpperCase();
  // Atualização condicional atômica: apenas uma operação pode resgatar o vale.
  const count = await prisma.$executeRaw`
    UPDATE gift_vouchers SET status = 'utilizado', redeemed_at = NOW(), updated_at = NOW()
    WHERE code = ${normalized} AND status = 'ativo' AND expires_at >= NOW()
  `;
  const rows = await prisma.$queryRaw`SELECT * FROM gift_vouchers WHERE code = ${normalized} LIMIT 1`;
  if (!rows.length) throw AppError.notFound('Vale-presente não encontrado.');
  if (count !== 1) throw AppError.conflict('Vale indisponível: já utilizado, cancelado ou expirado.');
  return serialize(rows[0]);
}
async function cancel(id) {
  if (typeof id !== 'string' || !/^[0-9a-f-]{36}$/i.test(id)) {
    throw AppError.unprocessable('Identificador inválido.');
  }
  const count = await prisma.$executeRaw`
    UPDATE gift_vouchers SET status = 'cancelado', updated_at = NOW()
    WHERE id = ${id} AND status = 'ativo' AND expires_at >= NOW()
  `;
  const rows = await prisma.$queryRaw`SELECT * FROM gift_vouchers WHERE id = ${id} LIMIT 1`;
  if (!rows.length) throw AppError.notFound('Vale-presente não encontrado.');
  if (count !== 1) throw AppError.conflict('Somente vales ativos podem ser cancelados.');
  return serialize(rows[0]);
}

module.exports = { issueDemo, listMine, listAdmin, redeem, cancel, nextBusinessExpiry };
