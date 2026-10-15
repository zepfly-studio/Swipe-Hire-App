-- AlterTable
ALTER TABLE "companies" ADD COLUMN     "gstin" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "verificationMethod" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "verificationOtp" JSONB;

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "companyOwnerId" TEXT,
ADD COLUMN     "tokenVersion" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "team_invites" (
    "id" TEXT NOT NULL,
    "ownerId" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "invitedById" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "acceptedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "team_invites_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "team_invites_tokenHash_key" ON "team_invites"("tokenHash");

-- CreateIndex
CREATE INDEX "team_invites_ownerId_createdAt_idx" ON "team_invites"("ownerId", "createdAt");

-- CreateIndex
CREATE INDEX "team_invites_email_idx" ON "team_invites"("email");

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_companyOwnerId_fkey" FOREIGN KEY ("companyOwnerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "team_invites" ADD CONSTRAINT "team_invites_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill: companies already verified by the domain match are "email" verified.
UPDATE "companies" SET "verificationMethod" = 'email' WHERE "verificationStatus" = 'verified' AND "verificationMethod" = '';
