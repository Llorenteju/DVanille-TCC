const asyncHandler = require('../utils/asyncHandler');
const { sendSuccess } = require('../utils/response');
const { pick } = require('../utils/pick');
const userService = require('../services/userService');

const getMyProfile = asyncHandler(async (req, res) => {
  const user = await userService.getUserById(req.user.id);
  return sendSuccess(res, { data: user });
});

const updateMyProfile = asyncHandler(async (req, res) => {
  const user = await userService.updateProfile(req.user.id, pick(req.body, ['name', 'phone']));
  return sendSuccess(res, { data: user, message: 'Perfil atualizado com sucesso.' });
});

const changeMyPassword = asyncHandler(async (req, res) => {
  await userService.changePassword(req.user.id, req.body);
  return sendSuccess(res, { message: 'Senha alterada com sucesso.' });
});

const uploadMyAvatar = asyncHandler(async (req, res) => {
  const user = await userService.updateProfileImage(req.user.id, req.file.filename);
  return sendSuccess(res, { data: user, message: 'Foto de perfil atualizada.' });
});

const getMyPreferences = asyncHandler(async (req, res) => {
  const preferences = await userService.getMyPreferences(req.user.id);
  return sendSuccess(res, { data: preferences });
});

const updateMyPreferences = asyncHandler(async (req, res) => {
  const input = pick(req.body, ['birthDate', 'dietaryPreferences', 'notificationsOptIn']);
  const preferences = await userService.updateMyPreferences(req.user.id, input);
  return sendSuccess(res, { data: preferences, message: 'Preferências atualizadas com sucesso.' });
});

const deleteMyPreferences = asyncHandler(async (req, res) => {
  const preferences = await userService.deleteMyPreferences(req.user.id);
  return sendSuccess(res, { data: preferences, message: 'Preferências pessoais apagadas.' });
});

module.exports = { getMyPreferences, updateMyPreferences, deleteMyPreferences, getMyProfile, updateMyProfile, changeMyPassword, uploadMyAvatar };
