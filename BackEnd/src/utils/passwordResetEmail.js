// Nodemailer - transporte SMTP configurado somente por variáveis de ambiente.
// Não imprime nem expõe links/tokens de recuperação em logs.
const nodemailer = require('nodemailer');

let transporter;

function config() {
  const host = (process.env.SMTP_HOST || '').trim();
  const port = Number(process.env.SMTP_PORT || '587');
  const user = (process.env.SMTP_USER || '').trim();
  const pass = process.env.SMTP_PASSWORD || '';
  const from = (process.env.SMTP_FROM || '').trim();
  const baseUrl = (process.env.DVANILLE_WEB_URL || 'http://localhost:8080').trim();
  if (!host || !Number.isInteger(port) || port < 1 || port > 65535 || !user || !pass || !from) {
    throw new Error('SMTP não configurado: defina SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD e SMTP_FROM.');
  }
  const site = new URL(baseUrl);
  if (site.username || site.password || site.search || site.hash) throw new Error('DVANILLE_WEB_URL inválida.');
  if (process.env.NODE_ENV === 'production' && site.protocol !== 'https:') {
    throw new Error('DVANILLE_WEB_URL deve usar HTTPS em produção.');
  }
  if (!['http:', 'https:'].includes(site.protocol)) throw new Error('DVANILLE_WEB_URL inválida.');
  return {host, port, user, pass, from, site};
}

async function sendPasswordResetEmail({to, token}) {
  const {host, port, user, pass, from, site} = config();
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host, port, secure: port === 465,
      auth: {user, pass},
      requireTLS: port !== 465,
      tls: {minVersion: 'TLSv1.2'},
    });
  }
  // Fragmento #/recuperar-senha: o token não é transmitido como URL HTTP ao servidor Web.
  const base = site.toString().replace(/\/$/, '');
  const link = `${base}/#/recuperar-senha?token=${encodeURIComponent(token)}`;
  await transporter.sendMail({
    from,
    to,
    subject: "D'Vanille - Recuperação de senha",
    text: [
      "Recebemos uma solicitação para redefinir a senha da sua conta D'Vanille.",
      '',
      `Abra este link (válido por 30 minutos e utilizável uma única vez): ${link}`,
      '',
      'Se você não pediu isso, ignore esta mensagem. Sua senha não será alterada.',
    ].join('\n'),
  });
}

module.exports = {sendPasswordResetEmail};
