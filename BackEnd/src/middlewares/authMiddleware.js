const prisma = require('../config/database');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { verifyToken } = require('../utils/jwt');
const env = require('../config/env');

function extractBearerToken(req) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (!scheme || scheme.toLowerCase() !== 'bearer' || !token) return null;
  return token;
}

/** Extrai somente o cookie de sessão estabelecido pela API, sem bibliotecas extras. */
function extractCookieToken(req) {
  const cookieHeader = req.headers.cookie || '';
  for (const item of cookieHeader.split(';')) {
    const parte = item.trim();
    const separador = parte.indexOf('=');
    if (separador < 0) continue;
    if (parte.slice(0, separador) !== 'dvanille_session') continue;
    const valor = parte.slice(separador + 1);
    try {
      return decodeURIComponent(valor);
    } catch (_) {
      return null;
    }
  }
  return null;
}

/**
 * Exige um JWT válido (Authorization: Bearer <token>).
 * Confere se o token não foi encerrado (logout) e recarrega o usuário do banco,
 * de modo que mudanças de papel/desativação valem imediatamente.
 */
const authenticateToken = asyncHandler(async (req, res, next) => {
  const bearer = extractBearerToken(req);
  const token = bearer || extractCookieToken(req);
  if (!token) throw AppError.unauthorized('Token de autenticação não informado.');

  // Proteção CSRF: solicitações com cookie não podem executar ações
  // de escrita a partir de origens não autorizadas. Apps mobile com Bearer
  // continuam funcionando sem o cabeçalho Origin.
  if (!bearer && !['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
    const origin = req.get('Origin');
    if (!origin || !env.corsOrigins.includes(origin)) {
      throw AppError.forbidden('Origem não autorizada para esta sessão.');
    }
  }

  let payload;
  try {
    payload = verifyToken(token);
  } catch (error) {
    const message = error.name === 'TokenExpiredError' ? 'Token expirado. Faça login novamente.' : 'Token inválido.';
    throw AppError.unauthorized(message);
  }

  const revoked = await prisma.revokedToken.findUnique({ where: { jti: payload.jti } });
  if (revoked) throw AppError.unauthorized('Sessão encerrada. Faça login novamente.');

  const user = await prisma.user.findUnique({
    where: { id: Number(payload.sub) },
    select: { id: true, name: true, email: true, role: true, isActive: true, passwordResetAt: true },
  });

  if (!user) throw AppError.unauthorized('Usuário do token não existe mais.');
  if (!user.isActive) throw AppError.forbidden('Conta desativada. Entre em contato com o suporte.');

  // Revoga todos os JWT/cookies emitidos antes da última recuperação de senha.
  // Tokens antigos têm apenas iat (segundos). Novos tokens carregam issuedAtMs.
  if (user.passwordResetAt) {
    const issuedMs = Number.isSafeInteger(payload.issuedAtMs)
      ? payload.issuedAtMs
      : (Number.isSafeInteger(payload.iat) ? payload.iat * 1000 : 0);
    if (issuedMs <= user.passwordResetAt.getTime()) {
      throw AppError.unauthorized('Senha alterada. Faça login novamente.');
    }
  }


  req.user = user;
  req.token = { jti: payload.jti, exp: payload.exp };
  next();
});

module.exports = { authenticateToken };
