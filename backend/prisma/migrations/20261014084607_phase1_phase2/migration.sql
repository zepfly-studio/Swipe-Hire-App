-- AlterEnum
ALTER TYPE "OpportunityStatus" ADD VALUE 'withdrawn';

-- AlterTable
ALTER TABLE "candidate_profiles" ADD COLUMN     "experienceYears" DOUBLE PRECISION NOT NULL DEFAULT 0,
ADD COLUMN     "noticeDays" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "skillsNormalized" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "job_postings" ADD COLUMN     "minExperienceYears" DOUBLE PRECISION NOT NULL DEFAULT 0,
ADD COLUMN     "skillsNormalized" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "opportunities" ADD COLUMN     "candidateReadAt" TIMESTAMP(3),
ADD COLUMN     "interviewRemindersSent" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "interviewRespondedAt" TIMESTAMP(3),
ADD COLUMN     "interviewResponse" TEXT,
ADD COLUMN     "interviewResponseNote" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "offerRespondedAt" TIMESTAMP(3),
ADD COLUMN     "offerResponse" TEXT,
ADD COLUMN     "recruiterReadAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "tasks" ADD COLUMN     "reviewReminderSentAt" TIMESTAMP(3),
ADD COLUMN     "submissionFileName" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "submissionFileUrl" TEXT NOT NULL DEFAULT '';

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "emailNotifications" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "task_templates" (
    "id" TEXT NOT NULL,
    "recruiterId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "link" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "task_templates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" TEXT NOT NULL DEFAULT 'info',
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL DEFAULT '',
    "opportunityId" TEXT,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "companies" (
    "id" TEXT NOT NULL,
    "ownerId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "website" TEXT NOT NULL DEFAULT '',
    "about" TEXT NOT NULL DEFAULT '',
    "industry" TEXT NOT NULL DEFAULT '',
    "size" TEXT NOT NULL DEFAULT '',
    "location" TEXT NOT NULL DEFAULT '',
    "logoUrl" TEXT NOT NULL DEFAULT '',
    "verificationStatus" TEXT NOT NULL DEFAULT 'unverified',
    "verificationNote" TEXT NOT NULL DEFAULT '',
    "verifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "companies_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "task_templates_recruiterId_createdAt_idx" ON "task_templates"("recruiterId", "createdAt");

-- CreateIndex
CREATE INDEX "notifications_userId_createdAt_idx" ON "notifications"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "notifications_userId_readAt_idx" ON "notifications"("userId", "readAt");

-- CreateIndex
CREATE UNIQUE INDEX "companies_ownerId_key" ON "companies"("ownerId");

-- CreateIndex
CREATE INDEX "candidate_profiles_experienceYears_idx" ON "candidate_profiles"("experienceYears");

-- CreateIndex
CREATE INDEX "candidate_profiles_expectedSalaryLpa_idx" ON "candidate_profiles"("expectedSalaryLpa");

-- AddForeignKey
ALTER TABLE "task_templates" ADD CONSTRAINT "task_templates_recruiterId_fkey" FOREIGN KEY ("recruiterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "companies" ADD CONSTRAINT "companies_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill the derived columns for rows that existed before this migration.
-- (New and edited profiles get the same values from backend/src/lib/derive.js.)
UPDATE "candidate_profiles" SET
  "skillsNormalized" = ARRAY(
    SELECT DISTINCT lower(trim(s)) FROM unnest("skills") AS s WHERE trim(s) <> ''
  ),
  "experienceYears" = COALESCE(NULLIF(substring("experience" from '[0-9]+(\.[0-9]+)?'), '')::float, 0),
  "noticeDays" = CASE
    WHEN lower("noticePeriod") ~ 'immediate|none|no notice|serving' THEN 0
    WHEN lower("noticePeriod") ~ 'month' THEN COALESCE(NULLIF(substring("noticePeriod" from '[0-9]+'), '')::int, 1) * 30
    WHEN lower("noticePeriod") ~ 'week' THEN COALESCE(NULLIF(substring("noticePeriod" from '[0-9]+'), '')::int, 1) * 7
    ELSE COALESCE(NULLIF(substring("noticePeriod" from '[0-9]+'), '')::int, 0)
  END;

UPDATE "job_postings" SET
  "skillsNormalized" = ARRAY(
    SELECT DISTINCT lower(trim(s)) FROM unnest("skills") AS s WHERE trim(s) <> ''
  );
