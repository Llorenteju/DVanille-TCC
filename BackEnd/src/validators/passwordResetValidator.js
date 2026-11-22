const {body} = require('express-validator');
const {passwordRules} = require('./authValidator');

const forgotPasswordRules = [
  body('email').isString().trim().toLowerCase().isEmail().withMessage('E-mail inválido.'),
];

const resetPasswordRules = [
  body('token').isString().matches(/^[A-Za-z0-9_-]{43}$/).withMessage('Token de recuperação inválido.'),
  passwordRules('newPassword'),
];

module.exports = {forgotPasswordRules, resetPasswordRules};
