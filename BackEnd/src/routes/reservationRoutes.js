const { Router } = require('express');
const { rateLimit } = require('express-rate-limit');
const controller = require('../controllers/reservationController');
const { optionalReservationAuth } = require('../middlewares/optionalReservationAuth');
const { authenticateToken } = require('../middlewares/authMiddleware');
const { validate } = require('../middlewares/validationMiddleware');
const { idParam, paginationQuery } = require('../validators/commonValidator');
const { createReservationRules, guestAccessRules } = require('../validators/reservationValidator');

const router = Router();

const requestLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { success: false, message: 'Muitas solicitações. Tente novamente mais tarde.', errors: [] },
});
const guestLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 60,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { success: false, message: 'Muitas consultas. Tente novamente mais tarde.', errors: [] },
});

// Formulário público: visitante recebe token somente na resposta da criação.
router.post('/', requestLimiter, optionalReservationAuth, createReservationRules, validate, controller.create);
router.post('/guest/lookup', guestLimiter, guestAccessRules, validate, controller.lookupGuest);
router.post('/guest/cancel', guestLimiter, guestAccessRules, validate, controller.cancelGuest);

// Reservas da própria conta (nunca pesquisar pela string de e-mail fornecida).
router.use(authenticateToken);
router.get('/me', paginationQuery, validate, controller.listMine);
router.get('/:id', idParam(), validate, controller.getMine);
router.patch('/:id/cancel', idParam(), validate, controller.cancelMine);

module.exports = router;
