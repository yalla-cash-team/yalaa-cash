-- Admin push broadcast history. idempotencyKey is unique so a repeated send
-- request returns the original broadcast instead of notifying customers again.

CREATE TYPE "BroadcastStatus" AS ENUM ('PENDING', 'SENT', 'PARTIAL', 'FAILED');

CREATE TABLE "NotificationBroadcast" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "idempotencyKey" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "status" "BroadcastStatus" NOT NULL DEFAULT 'PENDING',
    "recipientCount" INTEGER NOT NULL DEFAULT 0,
    "sentCount" INTEGER NOT NULL DEFAULT 0,
    "failedCount" INTEGER NOT NULL DEFAULT 0,
    "staleTokensRemoved" INTEGER NOT NULL DEFAULT 0,
    "errorMessage" TEXT,
    "createdByUserId" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "NotificationBroadcast_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "NotificationBroadcast_idempotencyKey_key" ON "NotificationBroadcast"("idempotencyKey");
CREATE INDEX "NotificationBroadcast_status_createdAt_idx" ON "NotificationBroadcast"("status", "createdAt");
CREATE INDEX "NotificationBroadcast_createdAt_idx" ON "NotificationBroadcast"("createdAt");
