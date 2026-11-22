const { Router } = require('express');
const controller = require('../controllers/dietaryRestrictionController');
const router = Router();

// Consulta pública aos tipos de restrições; SEM classificações automáticas.
router.get('/', controller.listRestrictions);

module.exports = router;
