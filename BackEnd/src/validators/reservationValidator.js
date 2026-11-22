const { body, query } = require('express-validator');
const { paginationQuery } = require('./commonValidator');

const STATUS = Object.freeze(['solicitada', 'confirmada', 'cancelada', 'finalizada']);
// Os horários atualmente oferecidos pelo formulário Flutter Web.
// Não representam garantia de capacidade ou de confirmação automática.
const HORARIOS = Object.freeze(['09:00', '10:30', '12:00', '14:00', '15:30', '17:00', '18:30', '20:00']);

function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

const createReservationRules = [
  body('name').isString().trim().isLength({ min: 2, max: 120 }).withMessage('Nome deve ter entre 2 e 120 caracteres.'),
  body('email').isString().trim().isEmail().withMessage('E-mail inválido.'),
  body('phone').isString().trim().matches(/^\+?[\d\s()\-]{10,30}$/).withMessage('Telefone inválido.'),
  body('reservationDate').custom(validDate).withMessage('Data inválida. Informe AAAA-MM-DD.'),
  body('reservationTime').isIn(HORARIOS).withMessage(`Escolha um dos horários: ${HORARIOS.join(', ')}.`),
  body('guests').isInt({ min: 1, max: 100 }).withMessage('Informe de 1 a 100 pessoas (sujeito à aprovação).').toInt(),
  body('preferences').optional({ values: 'undefined' }).isString().trim().isLength({ max: 2000 }).withMessage('Preferências: limite de 2000 caracteres.'),
  body('notes').optional({ values: 'undefined' }).isString().trim().isLength({ max: 2000 }).withMessage('Observações: limite de 2000 caracteres.'),
];

const guestAccessRules = [
  body('id').isInt({ min: 1 }).withMessage('ID da reserva inválido.').toInt(),
  body('guestAccessToken').isString().isLength({ min: 40, max: 100 }).withMessage('Token de visitante inválido.'),
];

const adminListRules = [
  ...paginationQuery,
  query('status').optional().isIn(STATUS).withMessage('Status inválido.'),
  query('dateFrom').optional().custom(validDate).withMessage('dateFrom deve ser AAAA-MM-DD.'),
  query('dateTo').optional().custom(validDate).withMessage('dateTo deve ser AAAA-MM-DD.'),
  query('search').optional().isString().trim().isLength({ max: 120 }).withMessage('Busca muito longa.'),
];

const adminStatusRules = [
  body('status').isIn(STATUS).withMessage(`Status deve ser: ${STATUS.join(', ')}.`),
];

module.exports = {
  STATUS,
  HORARIOS,
  createReservationRules,
  guestAccessRules,
  adminListRules,
  adminStatusRules,
};
