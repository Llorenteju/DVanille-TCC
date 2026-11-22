const asyncHandler = require('../utils/asyncHandler');
const {sendSuccess} = require('../utils/response');
const passwordResetService = require('../services/passwordResetService');

const forgotPassword = asyncHandler(async (req, res) => {
  const message = await passwordResetService.requestPasswordReset(req.body.email);
  return sendSuccess(res, {message});
});

const resetPassword = asyncHandler(async (req, res) => {
  await passwordResetService.resetPassword(req.body.token, req.body.newPassword);
  return sendSuccess(res, {message: 'Senha redefinida. Faça login com sua nova senha.'});
});

module.exports = {forgotPassword, resetPassword};
