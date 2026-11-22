const prisma = require('../config/database');
const AppError = require('../utils/AppError');

async function listRestrictions() {
  // Modelo PostgreSQL tem BigInt: não envie o objeto Prisma cru em JSON.
  if (!prisma.dietaryRestriction || !prisma.productRestriction) {
    throw new AppError('Restrições alimentares ainda não configuradas neste banco.', 501);
  }
  const entries = await prisma.dietaryRestriction.findMany({
    where: { isActive: true },
    select: { id: true, name: true, slug: true, description: true },
    orderBy: { name: 'asc' },
  });
  return entries.map((entry) => ({
    id: Number(entry.id),
    name: entry.name,
    slug: entry.slug,
    description: entry.description,
  }));
}

module.exports = { listRestrictions };
