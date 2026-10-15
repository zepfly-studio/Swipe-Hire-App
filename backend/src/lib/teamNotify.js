// Notifications meant for "the company" go to the owner AND every teammate
// who joined through an invite, once each (deduped by user id).

const { prisma } = require("./prisma");
const { notify, inBackground } = require("./notify");

/** Owner id + every member id of a hiring account, deduped. */
async function companyUserIds(companyId) {
  if (!companyId) return [];
  const members = await prisma.user.findMany({ where: { companyOwnerId: companyId }, select: { id: true } });
  return [...new Set([companyId, ...members.map((m) => m.id)])];
}

/**
 * Fans an event out to the owner and all members through lib/notify.js.
 * `event` is the same object notify() takes.
 *   exceptUserId  skip one person (the teammate who caused the event)
 *   dedupeUnread  chat style: a person who still has an unread notification of
 *                 this type + link only gets a push (no new bell row, no
 *                 email). The bell rows are written before returning; pushes
 *                 and emails follow in the background (see notify.idle()).
 * @returns the saved inbox rows (nulls dropped)
 */
async function notifyCompany(companyId, event, { exceptUserId = null, dedupeUnread = false } = {}) {
  const ids = (await companyUserIds(companyId)).filter((id) => id !== exceptUserId);

  if (!dedupeUnread) {
    const rows = await Promise.all(ids.map((id) => notify(id, event)));
    return rows.filter(Boolean);
  }

  const { title, body = "", type = "info", link = "", email = false } = event;
  const rows = [];
  for (const id of ids) {
    const unread = await prisma.notification.findFirst({
      where: { userId: id, type, link, readAt: null },
      select: { id: true },
    });
    if (!unread) {
      const row = await prisma.notification.create({ data: { userId: id, type, title, body, link } });
      rows.push(row);
    }
    inBackground(notify(id, { title, body, type, link, inbox: false, email: unread ? false : email }));
  }
  return rows;
}

/** The owner User row for the hiring account `user` belongs to (the user itself for an owner). */
async function companyOwner(user) {
  if (!user.companyOwnerId) return user;
  return (await prisma.user.findUnique({ where: { id: user.companyOwnerId } })) || user;
}

module.exports = { notifyCompany, companyUserIds, companyOwner };
