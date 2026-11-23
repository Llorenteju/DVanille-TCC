'use strict';
const { Router } = require('express');
const { authenticateToken } = require('../middlewares/authMiddleware');
const { requireAdmin } = require('../middlewares/adminMiddleware');
const asyncHandler = require('../utils/asyncHandler');
const { sendSuccess } = require('../utils/response');
const service = require('../services/tableOrderService');
const router = Router();
router.use(authenticateToken, requireAdmin);
router.get('/qr', asyncHandler(async (req, res) => {
  const table = service.table(req.query.table);
  return sendSuccess(res, { data: { table, token: service.tokenForTable(table) } });
}));
router.get('/', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: await service.listAdmin() });
}));
router.patch('/:id/status', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: await service.updateStatus(req.params.id, req.body.status), message: 'Status atualizado.' });
}));
module.exports = router;
