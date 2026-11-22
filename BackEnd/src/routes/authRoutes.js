const { Router } = require('express');
const authController = require('../controllers/authController');
const { authenticateToken } = require('../middlewares/authMiddleware');
const { authLimiter } = require('../middlewares/rateLimitMiddleware');
const { validate } = require('../middlewares/validationMiddleware');
const { registerRules, loginRules } = require('../validators/authValidator');

const passwordResetController = require('../controllers/passwordResetController');
const {forgotPasswordRules, resetPasswordRules} = require('../validators/passwordResetValidator');

const router = Router();

router.post('/register', authLimiter, registerRules, validate, authController.register);
router.post('/login', authLimiter, loginRules, validate, authController.login);
router.post('/forgot-password', authLimiter, forgotPasswordRules, validate, passwordResetController.forgotPassword);
router.post('/reset-password', authLimiter, resetPasswordRules, validate, passwordResetController.resetPassword);
router.get('/me', authenticateToken, authController.me);
router.post('/logout', authenticateToken, authController.logout);

module.exports = router;
