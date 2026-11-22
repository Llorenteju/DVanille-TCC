const { authenticateToken } = require('./authMiddleware');
const env = require('../config/env');
const AppError = require('../utils/AppError');

/**
 * Visitantes podem criar uma solicitação sem conta. Se houver cookie de sessão
 * ou bearer, a autenticação obrigatória existente deve validar esse token.
 * Não tratar uma sessão inválida como anônima.
 *
 * A mesma proteção de Origin também vale para POST sem cookie no navegador.
 */
function optionalReservationAuth(req, res, next) {
  const origin = req.get('Origin');
  if (origin && !env.corsOrigins.includes(origin)
    && (env.isProduction || env.corsOrigins.length > 0)) {
    return next(AppError.forbidden('Origem não autorizada para criar reservas.'));
  }

  const hasBearer = Boolean(req.get('Authorization'));
  const hasSessionCookie = /(?:^|;\s*)dvanille_session=/.test(req.get('Cookie') || '');
  if (hasBearer || hasSessionCookie) {
    return authenticateToken(req, res, next);
  }
  return next();
}

module.exports = { optionalReservationAuth };
