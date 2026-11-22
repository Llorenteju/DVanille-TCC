const crypto = require('node:crypto');
const prisma = require('../config/database');
const AppError = require('../utils/AppError');
const { parsePagination, buildPagination } = require('../utils/pagination');
const { HORARIOS } = require('../validators/reservationValidator');

const SP_TIMEZONE = 'America/Sao_Paulo';
const STATUS_ACTIVE = ['solicitada', 'confirmada'];
const TRANSITIONS = Object.freeze({
  solicitada: ['confirmada', 'cancelada'],
  confirmada: ['finalizada', 'cancelada'],
  cancelada: [],
  finalizada: [],
});

// Uma reserva não confirma disponibilidade: a aprovação deve ser feita pelo admin.
// Não devolva guestTokenHash nem dados adicionais internos da tabela.
const selectReservation = {
  id: true,
  userId: true,
  name: true,
  email: true,
  phone: true,
  reservationDate: true,
  reservationTime: true,
  guests: true,
  preferences: true,
  notes: true,
  status: true,
  createdAt: true,
  updatedAt: true,
};

function formatReservation(record) {
  if (!record) return null;
  const date = record.reservationDate instanceof Date
    ? record.reservationDate.toISOString().slice(0, 10)
    : String(record.reservationDate).slice(0, 10);
  const time = record.reservationTime instanceof Date
    ? record.reservationTime.toISOString().slice(11, 16)
    : String(record.reservationTime).slice(0, 5);
  return { ...record, reservationDate: date, reservationTime: time };
}

function SaoPauloNowParts(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: SP_TIMEZONE,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(now);
  const map = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return {
    date: `${map.year}-${map.month}-${map.day}`,
    time: `${map.hour}:${map.minute}`,
  };
}

function dateToPrisma(value) {
  return new Date(`${value}T00:00:00.000Z`);
}

function timeToPrisma(value) {
  return new Date(`1970-01-01T${value}:00.000Z`);
}

function checkReservationWindow(date, time) {
  // Validação adicional na camada de serviço (o front-end não é fonte de confiança).
  if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)
    || Number.isNaN(Date.parse(`${date}T00:00:00Z`))
    || dateToPrisma(date).toISOString().slice(0, 10) !== date
    || !HORARIOS.includes(time)) {
    throw AppError.unprocessable('Data ou horário da reserva inválidos.');
  }
  const now = SaoPauloNowParts();
  if (date < now.date || (date === now.date && time <= now.time)) {
    throw AppError.unprocessable('Escolha uma data e horário futuros.');
  }
  // Evita agendamentos muito distantes, mas não presume capacidade da cafeteria.
  const limite = dateToPrisma(now.date);
  limite.setUTCFullYear(limite.getUTCFullYear() + 2);
  if (date > limite.toISOString().slice(0, 10)) {
    throw AppError.unprocessable('Selecione uma data dentro dos próximos dois anos.');
  }
}

function asId(raw) {
  const id = Number(raw);
  if (!Number.isSafeInteger(id) || id < 1) throw AppError.badRequest('ID de reserva inválido.');
  return id;
}

function digestToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function compareToken(token, existingHash) {
  if (!existingHash || typeof token !== 'string' || token.length > 100) return false;
  const calculated = Buffer.from(digestToken(token), 'hex');
  const stored = Buffer.from(existingHash, 'hex');
  return stored.length === calculated.length && crypto.timingSafeEqual(stored, calculated);
}

async function createReservation(userId, input) {
  const date = String(input.reservationDate ?? '');
  const time = String(input.reservationTime ?? '');
  checkReservationWindow(date, time);
  if (!Number.isInteger(input.guests) || input.guests < 1 || input.guests > 100) {
    throw AppError.unprocessable('Quantidade de pessoas inválida.');
  }

  // Contas autenticadas possuem uma reserva ativa por data/horário.
  // O UNIQUE parcial do Postgres também impede concorrência simultânea.
  if (userId !== null) {
    const duplicate = await prisma.reservation.findFirst({
      where: {
        userId,
        reservationDate: dateToPrisma(date),
        reservationTime: timeToPrisma(time),
        status: { in: STATUS_ACTIVE },
      },
      select: { id: true },
    });
    if (duplicate) {
      throw AppError.conflict('Você já possui uma reserva solicitada ou confirmada nessa data e horário.');
    }
  }

  const guestAccessToken = userId === null ? crypto.randomBytes(32).toString('base64url') : null;
  const reservation = await prisma.reservation.create({
    data: {
      userId,
      name: input.name.trim(),
      email: input.email.trim().toLowerCase(),
      phone: input.phone.trim(),
      reservationDate: dateToPrisma(date),
      reservationTime: timeToPrisma(time),
      guests: input.guests,
      preferences: (input.preferences ?? '').trim(),
      notes: (input.notes ?? '').trim(),
      status: 'solicitada',
      guestTokenHash: guestAccessToken ? digestToken(guestAccessToken) : null,
    },
    select: selectReservation,
  });

  return {
    ...formatReservation(reservation),
    ...(guestAccessToken ? { guestAccessToken } : {}),
  };
}

async function listMine(userId, query = {}) {
  const { page, limit, skip, take } = parsePagination(query);
  const where = { userId };
  const [items, total] = await Promise.all([
    prisma.reservation.findMany({ where, select: selectReservation,
      orderBy: [{ reservationDate: 'desc' }, { reservationTime: 'desc' }, { id: 'desc' }],
      skip, take,
    }),
    prisma.reservation.count({ where }),
  ]);
  return { items: items.map(formatReservation), pagination: buildPagination({ page, limit, total }) };
}

async function getMine(userId, rawId) {
  const id = asId(rawId);
  const record = await prisma.reservation.findFirst({ where: { id, userId }, select: selectReservation });
  if (!record) throw AppError.notFound('Reserva não encontrada.');
  return formatReservation(record);
}

async function cancelMine(userId, rawId) {
  const id = asId(rawId);
  const changed = await prisma.reservation.updateMany({
    where: { id, userId, status: { in: STATUS_ACTIVE } },
    data: { status: 'cancelada' },
  });
  if (changed.count !== 1) {
    const exists = await prisma.reservation.findFirst({ where: { id, userId }, select: { status: true } });
    if (!exists) throw AppError.notFound('Reserva não encontrada.');
    throw AppError.conflict('Essa reserva não pode ser cancelada no status atual.');
  }
  return getMine(userId, id);
}

async function getGuest(rawId, token) {
  const id = asId(rawId);
  // Não permitir token de convidado em registros ligados a contas.
  const record = await prisma.reservation.findUnique({ where: { id } });
  if (!record || record.userId !== null || !compareToken(token, record.guestTokenHash)) {
    throw AppError.notFound('Reserva não encontrada.');
  }
  return formatReservation(Object.fromEntries(Object.keys(selectReservation).map((field) => [field, record[field]])));
}

async function cancelGuest(rawId, token) {
  const record = await getGuest(rawId, token);
  const changed = await prisma.reservation.updateMany({
    where: { id: record.id, userId: null, guestTokenHash: digestToken(token), status: { in: STATUS_ACTIVE } },
    data: { status: 'cancelada' },
  });
  if (changed.count !== 1) throw AppError.conflict('Essa reserva não pode ser cancelada no status atual.');
  return getGuest(rawId, token);
}

async function listAdmin(query = {}) {
  const { page, limit, skip, take } = parsePagination(query);
  const where = {};
  if (query.status) where.status = query.status;
  if (query.dateFrom || query.dateTo) {
    where.reservationDate = {};
    if (query.dateFrom) where.reservationDate.gte = dateToPrisma(query.dateFrom);
    if (query.dateTo) where.reservationDate.lte = dateToPrisma(query.dateTo);
  }
  if (query.search?.trim()) {
    const search = query.search.trim();
    where.OR = [
      { name: { contains: search, mode: 'insensitive' } },
      { email: { contains: search, mode: 'insensitive' } },
      { phone: { contains: search } },
    ];
  }
  const [items, total] = await Promise.all([
    prisma.reservation.findMany({ where, select: selectReservation,
      orderBy: [{ reservationDate: 'desc' }, { reservationTime: 'desc' }, { id: 'desc' }],
      skip, take,
    }),
    prisma.reservation.count({ where }),
  ]);
  return { items: items.map(formatReservation), pagination: buildPagination({ page, limit, total }) };
}

async function getAdmin(rawId) {
  const id = asId(rawId);
  const record = await prisma.reservation.findUnique({ where: { id }, select: selectReservation });
  if (!record) throw AppError.notFound('Reserva não encontrada.');
  return formatReservation(record);
}

async function updateAdminStatus(rawId, nextStatus) {
  const id = asId(rawId);
  const current = await prisma.reservation.findUnique({ where: { id }, select: { status: true } });
  if (!current) throw AppError.notFound('Reserva não encontrada.');
  if (nextStatus === current.status) return getAdmin(id);
  if (!TRANSITIONS[current.status]?.includes(nextStatus)) {
    throw AppError.conflict(`Não é permitido alterar uma reserva de ${current.status} para ${nextStatus}.`);
  }
  const changed = await prisma.reservation.updateMany({
    where: { id, status: current.status }, data: { status: nextStatus },
  });
  if (changed.count !== 1) throw AppError.conflict('A reserva foi alterada por outra operação. Atualize a tela.');
  return getAdmin(id);
}

module.exports = {
  formatReservation, SaoPauloNowParts, checkReservationWindow,
  createReservation, listMine, getMine, cancelMine,
  getGuest, cancelGuest, listAdmin, getAdmin, updateAdminStatus,
};
