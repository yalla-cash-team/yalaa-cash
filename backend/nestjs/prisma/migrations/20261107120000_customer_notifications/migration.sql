-- Customer notification inbox. Purely additive: one new table, its indexes
-- and foreign keys. No existing table, column or row is changed, so admin
-- broadcast logs, push delivery, points, balances and offers are untouched.
--
-- One row per customer per admin broadcast. The unique (broadcastId, userId)
-- pair makes delivery idempotent: a retried send never duplicates an entry.
-- "readAt" is set only when the customer opens that one notification.

CREATE TABLE "CustomerNotification" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "userId" UUID NOT NULL,
    "broadcastId" UUID,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "readAt" TIMESTAMP(3),

    CONSTRAINT "CustomerNotification_pkey" PRIMARY KEY ("id")
);

-- Serves "my unread notifications, newest first" and the unread count.
CREATE INDEX "CustomerNotification_userId_readAt_createdAt_idx"
    ON "CustomerNotification"("userId", "readAt", "createdAt");

CREATE UNIQUE INDEX "CustomerNotification_broadcastId_userId_key"
    ON "CustomerNotification"("broadcastId", "userId");

ALTER TABLE "CustomerNotification" ADD CONSTRAINT "CustomerNotification_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Deleting a broadcast log (never done by the API) keeps the inbox entries.
ALTER TABLE "CustomerNotification" ADD CONSTRAINT "CustomerNotification_broadcastId_fkey"
    FOREIGN KEY ("broadcastId") REFERENCES "NotificationBroadcast"("id") ON DELETE SET NULL ON UPDATE CASCADE;
