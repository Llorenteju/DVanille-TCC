const { body } = require('express-validator');
const { isValidBirthDate, isValidDietaryPreferences } = require('../utils/userPreferences');

// Campos opcionais. Data vazia ("") ou null indica remoção da data.
const preferenceRules = [
  body('birthDate')
    .optional({ values: 'null' })
    .custom((value) => value === '' || isValidBirthDate(value))
    .withMessage('Data de nascimento inválida. Use AAAA-MM-DD, sem datas futuras.'),
  body('dietaryPreferences')
    .optional()
    .custom(isValidDietaryPreferences)
    .withMessage('Preferências inválidas, repetidas ou com Nenhuma combinada com outra opção.'),
  body('notificationsOptIn')
    .optional()
    .isBoolean({ strict: true })
    .withMessage('notificationsOptIn deve ser true ou false.'),
];

module.exports = { preferenceRules };
