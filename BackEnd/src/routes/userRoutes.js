const { Router } = require('express');
const userController = require('../controllers/userController');
const { authenticateToken } = require('../middlewares/authMiddleware');
const { uploadProfileImage } = require('../middlewares/uploadMiddleware');
const { validate } = require('../middlewares/validationMiddleware');
const { updateProfileRules, changePasswordRules } = require('../validators/userValidator');
const { preferenceRules } = require('../validators/userPreferencesValidator');

const router = Router();

router.use(authenticateToken);

router.get('/me', userController.getMyProfile);
router.get('/me/preferences', userController.getMyPreferences);
router.put('/me/preferences', preferenceRules, validate, userController.updateMyPreferences);
router.delete('/me/preferences', userController.deleteMyPreferences);
router.put('/me', updateProfileRules, validate, userController.updateMyProfile);
router.put('/me/password', changePasswordRules, validate, userController.changeMyPassword);
router.post('/me/avatar', ...uploadProfileImage, userController.uploadMyAvatar);

module.exports = router;
