-- CreateEnum
CREATE TYPE "TaskStatus" AS ENUM ('assigned', 'submitted', 'approved', 'rejected');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "OpportunityStatus" ADD VALUE 'taskAssigned';
ALTER TYPE "OpportunityStatus" ADD VALUE 'taskSubmitted';

-- AlterTable
ALTER TABLE "messages" ADD COLUMN     "kind" TEXT NOT NULL DEFAULT 'text';

-- CreateTable
CREATE TABLE "tasks" (
    "id" TEXT NOT NULL,
    "opportunityId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "link" TEXT NOT NULL DEFAULT '',
    "dueDate" TIMESTAMP(3),
    "status" "TaskStatus" NOT NULL DEFAULT 'assigned',
    "answer" TEXT NOT NULL DEFAULT '',
    "submissionLink" TEXT NOT NULL DEFAULT '',
    "submittedAt" TIMESTAMP(3),
    "feedback" TEXT NOT NULL DEFAULT '',
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "tasks_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "tasks_opportunityId_createdAt_idx" ON "tasks"("opportunityId", "createdAt");

-- AddForeignKey
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_opportunityId_fkey" FOREIGN KEY ("opportunityId") REFERENCES "opportunities"("id") ON DELETE CASCADE ON UPDATE CASCADE;
