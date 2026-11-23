'use strict';
const { Router } = require('express');
const { rateLimit } = require('express-rate-limit');
const { authenticateToken } = require('../middlewares/authMiddleware');
const { requireAdmin } = require('../middlewares/adminMiddleware');
const asyncHandler = require('../utils/asyncHandler');
const { sendSuccess, sendCreated } = require('../utils/response');
const service = require('../services/giftVoucherService');
const router = Router();
const issueLimiter = rateLimit({ windowMs: 60 * 60 * 1000, limit: 10, standardHeaders: 'draft-7', legacyHeaders: false });
router.use(authenticateToken);
router.get('/me', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendSuccess(res, { data: await service.listMine(req.user) });
}));
router.post('/demo-issue', issueLimiter, asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  return sendCreated(res, await service.issueDemo(req.user, req.body), 'Vales emitidos para demonstração; não houve cobrança real.');
}));
module.exports = router;
