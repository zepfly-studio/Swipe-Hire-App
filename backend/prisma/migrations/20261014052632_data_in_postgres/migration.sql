-- CreateEnum
CREATE TYPE "OpportunityStatus" AS ENUM ('applied', 'shortlisted', 'interviewScheduled', 'offered', 'rejected', 'hired');

-- CreateEnum
CREATE TYPE "SwipeState" AS ENUM ('wishlist', 'shortlist', 'rejected');

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "fcmToken" TEXT;

-- CreateTable
CREATE TABLE "candidate_profiles" (
    "userId" TEXT NOT NULL,
    "age" INTEGER NOT NULL DEFAULT 0,
    "qualification" TEXT NOT NULL DEFAULT '',
    "experience" TEXT NOT NULL DEFAULT '',
    "desiredRole" TEXT NOT NULL DEFAULT '',
    "location" TEXT NOT NULL DEFAULT '',
    "skills" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "expectedSalaryLpa" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "noticePeriod" TEXT NOT NULL DEFAULT '',
    "about" TEXT NOT NULL DEFAULT '',
    "currentCompany" TEXT NOT NULL DEFAULT '',
    "currentSalaryLpa" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "photoUrl" TEXT NOT NULL DEFAULT '',
    "resumeUrl" TEXT NOT NULL DEFAULT '',
    "introVideoUrl" TEXT NOT NULL DEFAULT '',
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "candidate_profiles_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "job_postings" (
    "id" TEXT NOT NULL,
    "recruiterId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "skills" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "location" TEXT NOT NULL DEFAULT '',
    "employmentType" TEXT NOT NULL DEFAULT '',
    "salaryMinLpa" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "salaryMaxLpa" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "isOpen" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "job_postings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "opportunities" (
    "id" TEXT NOT NULL,
    "candidateId" TEXT NOT NULL,
    "recruiterId" TEXT NOT NULL,
    "jobPostingId" TEXT,
    "role" TEXT NOT NULL DEFAULT '',
    "status" "OpportunityStatus" NOT NULL DEFAULT 'shortlisted',
    "interviewDate" TIMESTAMP(3),
    "interviewMode" TEXT NOT NULL DEFAULT '',
    "interviewDetails" TEXT NOT NULL DEFAULT '',
    "offerSalaryLpa" DOUBLE PRECISION,
    "offerJoiningDate" TIMESTAMP(3),
    "offerNotes" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "opportunities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "messages" (
    "id" TEXT NOT NULL,
    "opportunityId" TEXT NOT NULL,
    "senderId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "sentAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "saved_jobs" (
    "candidateId" TEXT NOT NULL,
    "jobPostingId" TEXT NOT NULL,
    "savedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "saved_jobs_pkey" PRIMARY KEY ("candidateId","jobPostingId")
);

-- CreateTable
CREATE TABLE "swipes" (
    "recruiterId" TEXT NOT NULL,
    "candidateId" TEXT NOT NULL,
    "state" "SwipeState" NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "swipes_pkey" PRIMARY KEY ("recruiterId","candidateId")
);

-- CreateIndex
CREATE INDEX "job_postings_recruiterId_createdAt_idx" ON "job_postings"("recruiterId", "createdAt");

-- CreateIndex
CREATE INDEX "job_postings_isOpen_createdAt_idx" ON "job_postings"("isOpen", "createdAt");

-- CreateIndex
CREATE INDEX "opportunities_candidateId_updatedAt_idx" ON "opportunities"("candidateId", "updatedAt");

-- CreateIndex
CREATE INDEX "opportunities_recruiterId_updatedAt_idx" ON "opportunities"("recruiterId", "updatedAt");

-- CreateIndex
CREATE INDEX "opportunities_candidateId_jobPostingId_idx" ON "opportunities"("candidateId", "jobPostingId");

-- CreateIndex
CREATE INDEX "messages_opportunityId_sentAt_idx" ON "messages"("opportunityId", "sentAt");

-- CreateIndex
CREATE INDEX "swipes_recruiterId_state_idx" ON "swipes"("recruiterId", "state");

-- AddForeignKey
ALTER TABLE "candidate_profiles" ADD CONSTRAINT "candidate_profiles_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "job_postings" ADD CONSTRAINT "job_postings_recruiterId_fkey" FOREIGN KEY ("recruiterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "opportunities" ADD CONSTRAINT "opportunities_candidateId_fkey" FOREIGN KEY ("candidateId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "opportunities" ADD CONSTRAINT "opportunities_recruiterId_fkey" FOREIGN KEY ("recruiterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "opportunities" ADD CONSTRAINT "opportunities_jobPostingId_fkey" FOREIGN KEY ("jobPostingId") REFERENCES "job_postings"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "messages" ADD CONSTRAINT "messages_opportunityId_fkey" FOREIGN KEY ("opportunityId") REFERENCES "opportunities"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "messages" ADD CONSTRAINT "messages_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_jobs" ADD CONSTRAINT "saved_jobs_candidateId_fkey" FOREIGN KEY ("candidateId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saved_jobs" ADD CONSTRAINT "saved_jobs_jobPostingId_fkey" FOREIGN KEY ("jobPostingId") REFERENCES "job_postings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "swipes" ADD CONSTRAINT "swipes_recruiterId_fkey" FOREIGN KEY ("recruiterId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "swipes" ADD CONSTRAINT "swipes_candidateId_fkey" FOREIGN KEY ("candidateId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
