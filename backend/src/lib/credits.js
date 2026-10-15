// Swipe credits. Every swipe (left or right) costs one; wishlisting is free.
// All balance changes are single SQL statements (or run inside the caller's
// transaction) so concurrent requests can never overspend or double-credit.

const { prisma } = require("./prisma");

const FREE_SWIPES = 5;

/**
 * The recruiter's Company row, created on first need so recruiters who signed
 * up before companies existed (or skipped onboarding) can still swipe.
 * `user` is the signed-in recruiter (id, company, name).
 */
async function ensureCompany(user) {
  const existing = await prisma.company.findUnique({ where: { ownerId: user.id } });
  if (existing) return existing;
  const name = String(user.company || user.name || "My company").trim().slice(0, 150) || "My company";
  return prisma.company.upsert({
    where: { ownerId: user.id },
    create: { ownerId: user.id, name, swipesLeft: FREE_SWIPES },
    update: {},
  });
}

/**
 * Takes one credit, atomically. Returns the new balance, or null when there
 * is none left. `db` is `prisma` or a transaction client.
 */
async function spendSwipe(db, ownerId) {
  const rows = await db.$queryRaw`
    UPDATE "companies" SET "swipesLeft" = "swipesLeft" - 1
    WHERE "ownerId" = ${ownerId} AND "swipesLeft" > 0
    RETURNING "swipesLeft"`;
  return rows.length ? rows[0].swipesLeft : null;
}

/** Gives one credit back. Returns the new balance. */
async function refundSwipe(db, ownerId) {
  const rows = await db.$queryRaw`
    UPDATE "companies" SET "swipesLeft" = "swipesLeft" + 1
    WHERE "ownerId" = ${ownerId}
    RETURNING "swipesLeft"`;
  return rows.length ? rows[0].swipesLeft : null;
}

async function balanceOf(db, ownerId) {
  const row = await db.company.findUnique({ where: { ownerId }, select: { swipesLeft: true } });
  return row ? row.swipesLeft : 0;
}

/**
 * Adds a purchased pack to the balance, once per `orderId` (the order id is
 * appended to creditedOrders in the same statement that adds the swipes, so
 * the webhook and /payment/verify cannot both credit it).
 * @returns {{ swipesLeft: number, added: number }}
 */
async function creditOrder(ownerId, orderId, swipes) {
  const rows = await prisma.$queryRaw`
    UPDATE "companies"
    SET "swipesLeft" = "swipesLeft" + ${swipes}::int,
        "swipesPurchased" = "swipesPurchased" + ${swipes}::int,
        "creditedOrders" = array_append("creditedOrders", ${orderId}::text)
    WHERE "ownerId" = ${ownerId} AND NOT (${orderId}::text = ANY("creditedOrders"))
    RETURNING "swipesLeft"`;
  if (rows.length) return { swipesLeft: rows[0].swipesLeft, added: swipes };
  return { swipesLeft: await balanceOf(prisma, ownerId), added: 0 };
}

module.exports = { FREE_SWIPES, ensureCompany, spendSwipe, refundSwipe, balanceOf, creditOrder };
