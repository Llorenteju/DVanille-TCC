'use strict';
const { Router } = require('express');
const { rateLimit } = require('express-rate-limit');
const { authenticateToken } = require('../middlewares/authMiddleware');
const asyncHandler = require('../utils/asyncHandler');
const { sendSuccess, sendCreated } = require('../utils/response');
const service = require('../services/tableOrderService');
const router = Router();
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false });
router.use(authenticateToken);
router.get('/mine', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: await service.listMine(req.user) });
}));
router.post('/', limiter, asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendCreated(res, await service.create(req.user, req.body), 'Pedido da mesa enviado ao caixa.');
}));
module.exports = router;
