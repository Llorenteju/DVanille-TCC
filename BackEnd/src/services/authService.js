const prisma = require('../config/database');
const env = require('../config/env');
const AppError = require('../utils/AppError');
const { hashPassword, comparePassword } = require('../utils/password');
const { signToken } = require('../utils/jwt');
const { userPublicSelect } = require('./userService');
const { hasPreferenceFields, toPreferenceDatabaseFields } = require('../utils/userPreferences');

// Hash válido gerado uma vez, usado para manter o tempo de resposta parecido
// quando o e-mail informado não existe (evita enumerar usuários pelo tempo).
let dummyHashPromise = null;
const getDummyHash = () => {
  if (!dummyHashPromise) dummyHashPromise = hashPassword('dvanille-dummy-password');
  return dummyHashPromise;
};

function buildAuthResult(user) {
  return { user, token: signToken(user), tokenType: 'Bearer', expiresIn: env.jwt.expiresIn };
}

/** Cadastro público: sempre cria um CUSTOMER (o papel nunca vem do cliente). */
async function registerUser({ name, email, phone, password, birthDate, dietaryPreferences, notificationsOptIn }) {
  const existing = await prisma.user.findUnique({ where: { email }, select: { id: true } });
  if (existing) {
    throw AppError.conflict('Este e-mail já está cadastrado.', [{ field: 'email', message: 'E-mail já cadastrado.' }]);
  }

  const passwordHash = await hashPassword(password);
  const preferenceInput = { birthDate, dietaryPreferences, notificationsOptIn };
  const provided = Object.fromEntries(
    Object.entries(preferenceInput).filter(([, value]) => value !== undefined)
  );
  const data = { name, email, phone: phone || null, passwordHash, role: 'CUSTOMER' };
  if (hasPreferenceFields(provided)) {
    // Escrita atômica: ou o usuário e suas preferências são salvos juntos,
    // ou nenhuma das duas operações é confirmada.
    data.preference = { create: toPreferenceDatabaseFields(provided) };
  }
  const user = await prisma.user.create({ data, select: userPublicSelect });

  return buildAuthResult(user);
}

async function loginUser({ email, password }) {
  const record = await prisma.user.findUnique({ where: { email } });
  const passwordMatches = await comparePassword(password, record ? record.passwordHash : await getDummyHash());

  if (!record || !passwordMatches) throw AppError.unauthorized('E-mail ou senha inválidos.');
  if (!record.isActive) throw AppError.forbidden('Conta desativada. Entre em contato com o suporte.');

  const user = await prisma.user.findUnique({ where: { id: record.id }, select: userPublicSelect });
  return buildAuthResult(user);
}

/** Logout real: registra o jti do token como encerrado até a data de expiração dele. */
async function logoutUser({ jti, exp }) {
  const expiresAt = new Date(exp * 1000);

  await prisma.revokedToken.upsert({
    where: { jti },
    update: {},
    create: { jti, expiresAt },
  });

  // Limpeza oportunista de tokens que já expirariam sozinhos.
  await prisma.revokedToken.deleteMany({ where: { expiresAt: { lt: new Date() } } });
}

module.exports = { registerUser, loginUser, logoutUser };
