const asyncHandler = require('../utils/asyncHandler');
const { sendSuccess, sendCreated, sendPaginated } = require('../utils/response');
const { pick } = require('../utils/pick');
const service = require('../services/reservationService');
const AppError = require('../utils/AppError');

const create = asyncHandler(async (req, res) => {
  if (req.user?.role === 'ADMIN') throw AppError.forbidden('Contas administrativas não podem solicitar reservas.');
  const input = pick(req.body, [
    'name', 'email', 'phone', 'reservationDate', 'reservationTime',
    'guests', 'preferences', 'notes',
  ]);
  const created = await service.createReservation(req.user?.id ?? null, input);
  res.set('Cache-Control', 'no-store');
  return sendCreated(res, created, 'Solicitação de reserva recebida. Aguarde confirmação da cafeteria.');
});

const listMine = asyncHandler(async (req, res) => {
  const result = await service.listMine(req.user.id, req.query);
  return sendPaginated(res, result);
});

const getMine = asyncHandler(async (req, res) => {
  const result = await service.getMine(req.user.id, req.params.id);
  return sendSuccess(res, { data: result });
});

const cancelMine = asyncHandler(async (req, res) => {
  const result = await service.cancelMine(req.user.id, req.params.id);
  return sendSuccess(res, { data: result, message: 'Reserva cancelada.' });
});

const lookupGuest = asyncHandler(async (req, res) => {
  const result = await service.getGuest(req.body.id, req.body.guestAccessToken);
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: result });
});

const cancelGuest = asyncHandler(async (req, res) => {
  const result = await service.cancelGuest(req.body.id, req.body.guestAccessToken);
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: result, message: 'Reserva cancelada.' });
});

const listAdmin = asyncHandler(async (req, res) => {
  const result = await service.listAdmin(req.query);
  res.set('Cache-Control', 'no-store');
  return sendPaginated(res, result);
});

const getAdmin = asyncHandler(async (req, res) => {
  const result = await service.getAdmin(req.params.id);
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: result });
});

const updateAdminStatus = asyncHandler(async (req, res) => {
  const result = await service.updateAdminStatus(req.params.id, req.body.status);
  return sendSuccess(res, { data: result, message: 'Status atualizado.' });
});

module.exports = { create, listMine, getMine, cancelMine, lookupGuest, cancelGuest, listAdmin, getAdmin, updateAdminStatus };
