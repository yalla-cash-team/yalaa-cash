import { Injectable, Logger } from "@nestjs/common";
import { getMessaging } from "firebase-admin/messaging";
import { FirebaseOAuthService } from "../auth/firebase-oauth.service";
import { PrismaService } from "../prisma/prisma.service";

interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushSendStats {
  sent: number;
  failed: number;
  staleRemoved: number;
}

export interface BroadcastSendStats extends PushSendStats {
  recipients: number;
}

/**
 * Sends push notifications through Firebase Cloud Messaging, reusing the
 * same Firebase Admin app FirebaseOAuthService initializes for Google
 * Sign-In verification.
 *
 * sendToUser is best-effort and never rejects: customer-facing requests must
 * not fail because a push could not be delivered. sendToAllCustomers reports
 * real counts and may reject on database errors, so the broadcast service can
 * record the send as failed.
 */
@Injectable()
export class FcmService {
  private readonly logger = new Logger(FcmService.name);
  private static readonly BATCH_SIZE = 500;

  constructor(
    private readonly firebaseOAuth: FirebaseOAuthService,
    private readonly prisma: PrismaService,
  ) {}

  async sendToUser(userId: string, message: PushMessage): Promise<void> {
    try {
      const tokens = await this.prisma.deviceToken.findMany({
        where: { userId },
        select: { token: true },
      });
      if (tokens.length === 0) return;
      await this.sendToTokens(
        tokens.map((t) => t.token),
        message,
      );
    } catch (error) {
      this.logger.warn(
        `sendToUser failed, notification skipped: ${this.describeError(error)}`,
      );
    }
  }

  /** Sends to every registered customer device and reports the counts. */
  async sendToAllCustomers(
    message: PushMessage,
  ): Promise<BroadcastSendStats> {
    const tokens = await this.prisma.deviceToken.findMany({
      where: { user: { role: "CUSTOMER" } },
      select: { token: true },
    });
    const stats = await this.sendToTokens(
      tokens.map((t) => t.token),
      message,
    );
    return { recipients: tokens.length, ...stats };
  }

  private async sendToTokens(
    tokens: string[],
    message: PushMessage,
  ): Promise<PushSendStats> {
    const empty: PushSendStats = { sent: 0, failed: 0, staleRemoved: 0 };
    if (tokens.length === 0) return empty;

    let app;
    try {
      app = this.firebaseOAuth.getApp();
    } catch {
      this.logger.warn("Skipped push send: Firebase Admin is not configured.");
      return { ...empty, failed: tokens.length };
    }

    let messaging;
    try {
      messaging = getMessaging(app);
    } catch (error) {
      this.logger.warn(
        `Skipped push send: could not obtain messaging client: ${this.describeError(error)}`,
      );
      return { ...empty, failed: tokens.length };
    }

    const stats: PushSendStats = { ...empty };
    const staleTokens: string[] = [];

    for (let i = 0; i < tokens.length; i += FcmService.BATCH_SIZE) {
      const batch = tokens.slice(i, i + FcmService.BATCH_SIZE);
      try {
        const response = await messaging.sendEachForMulticast({
          tokens: batch,
          notification: { title: message.title, body: message.body },
          ...(message.data ? { data: message.data } : {}),
        });
        stats.sent += response.successCount;
        stats.failed += response.failureCount;
        response.responses.forEach((res, index) => {
          const code = (res.error as { code?: string } | undefined)?.code;
          if (
            !res.success &&
            (code === "messaging/registration-token-not-registered" ||
              code === "messaging/invalid-registration-token")
          ) {
            staleTokens.push(batch[index]);
          }
        });
      } catch (error) {
        stats.failed += batch.length;
        this.logger.warn(`FCM batch send failed: ${this.describeError(error)}`);
      }
    }

    if (staleTokens.length > 0) {
      try {
        const removed = await this.prisma.deviceToken.deleteMany({
          where: { token: { in: staleTokens } },
        });
        stats.staleRemoved = removed.count;
      } catch (error) {
        this.logger.warn(
          `Failed to clean up ${staleTokens.length} stale token(s): ${this.describeError(error)}`,
        );
      }
    }

    return stats;
  }

  /** Never includes token values or credentials — message/error text only. */
  private describeError(error: unknown): string {
    return error instanceof Error ? error.message : "unknown error";
  }
}
