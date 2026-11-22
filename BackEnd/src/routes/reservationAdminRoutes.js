const { Router } = require('express');
const controller = require('../controllers/reservationController');
const { authenticateToken } = require('../middlewares/authMiddleware');
const { requireAdmin } = require('../middlewares/adminMiddleware');
const { validate } = require('../middlewares/validationMiddleware');
const { idParam } = require('../validators/commonValidator');
const { adminListRules, adminStatusRules } = require('../validators/reservationValidator');

const router = Router();
router.use(authenticateToken, requireAdmin);
router.get('/', adminListRules, validate, controller.listAdmin);
router.get('/:id', idParam(), validate, controller.getAdmin);
router.patch('/:id/status', idParam(), adminStatusRules, validate, controller.updateAdminStatus);

module.exports = router;
