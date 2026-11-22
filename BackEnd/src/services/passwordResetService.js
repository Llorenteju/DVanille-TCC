const crypto = require('crypto');
const prisma = require('../config/database');
const AppError = require('../utils/AppError');
const {hashPassword} = require('../utils/password');
const {sendPasswordResetEmail} = require('../utils/passwordResetEmail');

const TOKEN_VALIDITY_MS = 30 * 60 * 1000;
const REQUEST_COOLDOWN_MS = 60 * 1000;
const GENERIC_MESSAGE = 'Se o e-mail estiver cadastrado, você receberá instruções para redefinir a senha.';

const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');

async function requestPasswordReset(email) {
  const user = await prisma.user.findUnique({where: {email}, select: {id: true, email: true, isActive: true}});
  if (!user || !user.isActive) return GENERIC_MESSAGE;

  const now = new Date();
  const last = await prisma.passwordResetToken.findFirst({
    where: {userId: user.id}, orderBy: {createdAt: 'desc'}, select: {createdAt: true},
  });
  if (last && now.getTime() - last.createdAt.getTime() < REQUEST_COOLDOWN_MS) {
    return GENERIC_MESSAGE;
  }

  const token = crypto.randomBytes(32).toString('base64url');
  const tokenHash = sha256(token);
  const record = await prisma.passwordResetToken.create({
    data: {userId: user.id, tokenHash, expiresAt: new Date(now.getTime() + TOKEN_VALIDITY_MS)},
    select: {id: true},
  });
  try {
    await sendPasswordResetEmail({to: user.email, token});
    // Invalida tokens anteriores apenas após enviar o novo link com sucesso.
    await prisma.passwordResetToken.updateMany({
      where: {userId: user.id, id: {not: record.id}, usedAt: null},
      data: {usedAt: new Date()},
    });
  } catch (error) {
    // Não revelar se existe conta, nem imprimir e-mail/tokens/credenciais.
    console.error('[password-reset] Falha ao enviar e-mail; confira SMTP no ambiente.');
    await prisma.passwordResetToken.deleteMany({where: {id: record.id}});
  }
  return GENERIC_MESSAGE;
}

async function resetPassword(token, newPassword) {
  const tokenHash = sha256(token);
  const newHash = await hashPassword(newPassword);
  const now = new Date();

  await prisma.$transaction(async (tx) => {
    const record = await tx.passwordResetToken.findUnique({
      where: {tokenHash},
      select: {id: true, userId: true, expiresAt: true, usedAt: true},
    });
    const invalid = !record || record.usedAt || record.expiresAt <= now;
    if (invalid) throw AppError.badRequest('Link inválido ou expirado. Solicite outro e-mail.');

    const claimed = await tx.passwordResetToken.updateMany({
      where: {id: record.id, usedAt: null, expiresAt: {gt: now}},
      data: {usedAt: now},
    });
    if (claimed.count !== 1) throw AppError.badRequest('Link inválido ou expirado. Solicite outro e-mail.');

    await tx.user.update({
      where: {id: record.userId},
      data: {passwordHash: newHash, passwordResetAt: now},
    });
    // Todos os outros links da conta perdem a validade.
    await tx.passwordResetToken.updateMany({
      where: {userId: record.userId, usedAt: null}, data: {usedAt: now},
    });
  });
}

module.exports = {requestPasswordReset, resetPassword};
