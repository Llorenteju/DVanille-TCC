const asyncHandler = require('../utils/asyncHandler');
const { sendSuccess, sendCreated } = require('../utils/response');
const authService = require('../services/authService');
const userService = require('../services/userService');
const env = require('../config/env');

// A sessão Web fica no cookie HttpOnly. O JWT retornado pela API
// continua disponível para o aplicativo mobile via Authorization: Bearer.
const NOME_COOKIE = 'dvanille_session';

function definirCookieSessao(res, token) {
  res.cookie(NOME_COOKIE, token, {
    httpOnly: true,
    secure: env.isProduction, // HTTPS em produção. HTTP em localhost no desenvolvimento.
    sameSite: 'lax',           // Funciona com localhost:8080 e localhost:3001.
    path: '/api',
    // Cookie de sessão: não gravamos a senha nem o token em localStorage.
  });
}

function limparCookieSessao(res) {
  res.clearCookie(NOME_COOKIE, {
    httpOnly: true,
    secure: env.isProduction,
    sameSite: 'lax',
    path: '/api',
  });
}

const register = asyncHandler(async (req, res) => {
  const result = await authService.registerUser(req.body);
  definirCookieSessao(res, result.token);
  return sendCreated(res, result, 'Cadastro realizado com sucesso.');
});

const login = asyncHandler(async (req, res) => {
  const result = await authService.loginUser(req.body);
  definirCookieSessao(res, result.token);
  return sendSuccess(res, { data: result, message: 'Login realizado com sucesso.' });
});

const me = asyncHandler(async (req, res) => {
  const user = await userService.getUserById(req.user.id);
  return sendSuccess(res, { data: user, message: 'Usuário autenticado.' });
});

const logout = asyncHandler(async (req, res) => {
  await authService.logoutUser(req.token);
  limparCookieSessao(res);
  return sendSuccess(res, { message: 'Logout realizado com sucesso.' });
});

module.exports = { register, login, me, logout };
