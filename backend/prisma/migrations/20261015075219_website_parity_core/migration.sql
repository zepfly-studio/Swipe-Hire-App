-- CreateEnum
CREATE TYPE "PipelineStage" AS ENUM ('shortlisted', 'contacted', 'task', 'interview', 'hired', 'rejected');

-- AlterTable
ALTER TABLE "companies" ADD COLUMN     "address" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "contactEmail" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "creditedOrders" TEXT[] DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "foundedYear" INTEGER,
ADD COLUMN     "linkedin" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "phone" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "swipesLeft" INTEGER NOT NULL DEFAULT 5,
ADD COLUMN     "swipesPurchased" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "job_postings" ADD COLUMN     "maxExperienceYears" DOUBLE PRECISION,
ADD COLUMN     "openings" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN     "status" TEXT NOT NULL DEFAULT 'open',
ADD COLUMN     "workMode" TEXT NOT NULL DEFAULT 'onsite';

-- AlterTable
ALTER TABLE "notifications" ADD COLUMN     "link" TEXT NOT NULL DEFAULT '';

-- CreateTable
CREATE TABLE "candidate_swipes" (
    "id" TEXT NOT NULL,
    "recruiterId" TEXT NOT NULL,
    "candidateId" TEXT NOT NULL,
    "jobPostingId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "stage" "PipelineStage" NOT NULL DEFAULT 'shortlisted',
    "notes" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "candidate_swipes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "wishlist_entries" (
    "recruiterId" TEXT NOT NULL,
    "candidateId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wishlist_entries_pkey" PRIMARY KEY ("recruiterId","candidateId")
);

-- CreateTable
CREATE TABLE "chat_messages" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "candidateId" TEXT NOT NULL,
    "senderId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "interviews" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "candidateId" TEXT NOT NULL,
    "jobPostingId" TEXT,
    "slots" TIMESTAMP(3)[],
    "chosenSlot" TIMESTAMP(3),
    "durationMins" INTEGER NOT NULL DEFAULT 30,
    "mode" TEXT NOT NULL DEFAULT 'video',
    "meetingLink" TEXT NOT NULL DEFAULT '',
    "location" TEXT NOT NULL DEFAULT '',
    "note" TEXT NOT NULL DEFAULT '',
    "status" TEXT NOT NULL DEFAULT 'proposed',
    "cancelledById" TEXT,
    "cancelReason" TEXT NOT NULL DEFAULT '',
    "remindersSent" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "interviews_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "hiring_tasks" (
    "id" TEXT NOT NULL,
    "companyId" TEXT NOT NULL,
    "candidateId" TEXT NOT NULL,
    "jobPostingId" TEXT,
    "createdById" TEXT,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "briefUrl" TEXT NOT NULL DEFAULT '',
    "dueAt" TIMESTAMP(3) NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'assigned',
    "liveUrl" TEXT NOT NULL DEFAULT '',
    "repoUrl" TEXT NOT NULL DEFAULT '',
    "submissionNote" TEXT NOT NULL DEFAULT '',
    "submittedAt" TIMESTAMP(3),
    "reminderSentAt" TIMESTAMP(3),
    "reviewReminderSentAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "hiring_tasks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "saved_searches" (
    "id" TEXT NOT NULL,
    "recruiterId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "filters" JSONB NOT NULL,
    "alerts" BOOLEAN NOT NULL DEFAULT true,
    "notifiedCandidates" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "saved_searches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payments" (
    "id" TEXT NOT NULL,
    "recruiterId" TEXT NOT NULL,
    "planId" TEXT NOT NULL,
    "amountRupees" INTEGER NOT NULL,
    "swipes" INTEGER NOT NULL,
    "orderId" TEXT NOT NULL,
    "paymentId" TEXT,
    "mode" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'created',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "candidate_swipes_recruiterId_createdAt_idx" ON "candidate_swipes"("recruiterId", "createdAt");

-- CreateIndex
CREATE INDEX "candidate_swipes_candidateId_action_idx" ON "candidate_swipes"("candidateId", "action");

-- CreateIndex
CREATE UNIQUE INDEX "candidate_swipes_recruiterId_candidateId_jobPostingId_key" ON "candidate_swipes"("recruiterId", "candidateId", "jobPostingId");

-- CreateIndex
CREATE INDEX "chat_messages_companyId_candidateId_createdAt_idx" ON "chat_messages"("companyId", "candidateId", "createdAt");

-- CreateIndex
CREATE INDEX "chat_messages_candidateId_readAt_idx" ON "chat_messages"("candidateId", "readAt");

-- CreateIndex
CREATE INDEX "interviews_companyId_createdAt_idx" ON "interviews"("companyId", "createdAt");

-- CreateIndex
CREATE INDEX "interviews_candidateId_createdAt_idx" ON "interviews"("candidateId", "createdAt");

-- CreateIndex
CREATE INDEX "hiring_tasks_companyId_createdAt_idx" ON "hiring_tasks"("companyId", "createdAt");

-- CreateIndex
CREATE INDEX "hiring_tasks_candidateId_createdAt_idx" ON "hiring_tasks"("candidateId", "createdAt");

-- CreateIndex
CREATE INDEX "saved_searches_recruiterId_createdAt_idx" ON "saved_searches"("recruiterId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "payments_orderId_key" ON "payments"("orderId");

-- CreateIndex
CREATE INDEX "payments_recruiterId_createdAt_idx" ON "payments"("recruiterId", "createdAt");

-- AddForeignKey
ALTER TABLE "candidate_swipes" ADD CONSTRAINT "candidate_swipes_recruiterId_fkey" FOREIGN KEY ("recruiterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "candidate_swipes" ADD CONSTRAINT "candidate_swipes_candidateId_fkey" FOREIGN KEY ("candidateId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "candidate_swipes" ADD CONSTRAINT "candidate_swipes_jobPostingId_fkey" FOREIGN KEY ("jobPostingId") REFERENCES "job_postings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wishlist_entries" ADD CONSTRAINT "wishlist_entries_recruiterId_fkey" FOREIGN KEY ("recruiterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "wishlist_entries" ADD CONSTRAINT "wishlist_entries_candidateId_fkey" FOREIGN KEY ("candidateId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_candidateId_fkey" FOREIGN KEY ("candidateId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "interviews" ADD CONSTRAINT "interviews_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "interviews" ADD CONSTRAINT "interviews_candidateId_fkey" FOREIGN KEY ("candidateId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "interviews" ADD CONSTRAINT "interviews_jobPostingId_fkey" FOREIGN KEY ("jobPostingId") REFERENCES "job_postings"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "hiring_tasks" ADD CONSTRAINT "hiring_tasks_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "hiring_tasks" ADD CONSTRAINT "hiring_tasks_candidateId_fkey" FOREIGN KEY ("candidateId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "hiring_tasks" ADD CONSTRAINT "hiring_tasks_jobPostingId_fkey" FOREIGN KEY ("jobPostingId") REFERENCES "job_postings"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_searches" ADD CONSTRAINT "saved_searches_recruiterId_fkey" FOREIGN KEY ("recruiterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_recruiterId_fkey" FOREIGN KEY ("recruiterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill: existing postings keep their open/closed state in the new status column.
UPDATE "job_postings" SET "status" = CASE WHEN "isOpen" THEN 'open' ELSE 'closed' END;
