'use strict';
const { Router } = require('express');
const { authenticateToken } = require('../middlewares/authMiddleware');
const { requireAdmin } = require('../middlewares/adminMiddleware');
const asyncHandler = require('../utils/asyncHandler');
const { sendSuccess } = require('../utils/response');
const service = require('../services/giftVoucherService');
const router = Router();
router.use(authenticateToken, requireAdmin);
router.get('/', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: await service.listAdmin() });
}));
router.patch('/redeem', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: await service.redeem(req.body.code), message: 'Vale resgatado presencialmente.' });
}));
router.patch('/:id/cancel', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: await service.cancel(req.params.id), message: 'Vale cancelado.' });
}));
module.exports = router;
