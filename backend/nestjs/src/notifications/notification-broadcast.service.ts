import {
  ConflictException,
  Injectable,
  Logger,
} from "@nestjs/common";
import { BroadcastStatus, NotificationBroadcast, Prisma } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";
import { BroadcastSendStats, FcmService } from "./fcm.service";

export interface BroadcastRequest {
  title: string;
  body: string;
  idempotencyKey: string;
}

/// A broadcast stuck in PENDING for longer than this (e.g. after a crash) no
/// longer blocks new broadcasts.
export const STALE_PENDING_MS = 10 * 60 * 1000;

/**
 * Sends admin broadcasts to all customers and records each send. The
 * idempotency key returns the original record on retries, and a pending send
 * blocks a second, different broadcast so a double-submit cannot notify twice.
 */
@Injectable()
export class NotificationBroadcastService {
  private readonly logger = new Logger(NotificationBroadcastService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly fcm: FcmService,
  ) {}

  async send(
    adminUserId: string,
    request: BroadcastRequest,
  ): Promise<NotificationBroadcast> {
    const existing = await this.findByKey(request.idempotencyKey);
    if (existing) return existing;

    const pending = await this.prisma.notificationBroadcast.findFirst({
      where: {
        status: BroadcastStatus.PENDING,
        createdAt: { gt: new Date(Date.now() - STALE_PENDING_MS) },
      },
      select: { id: true },
    });
    if (pending) {
      throw new ConflictException(
        "Another notification is still being sent. Wait before sending again.",
      );
    }

    let record: NotificationBroadcast;
    try {
      record = await this.prisma.notificationBroadcast.create({
        data: {
          idempotencyKey: request.idempotencyKey,
          title: request.title,
          body: request.body,
          createdByUserId: adminUserId,
        },
      });
    } catch (error) {
      // A concurrent request with the same key won the race.
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        const raced = await this.findByKey(request.idempotencyKey);
        if (raced) return raced;
      }
      throw error;
    }

    let stats: BroadcastSendStats;
    try {
      stats = await this.fcm.sendToAllCustomers({
        title: request.title,
        body: request.body,
      });
    } catch (error) {
      // Only the error class is logged: messages could echo request data.
      this.logger.warn(
        `Broadcast ${record.id} failed: ${error instanceof Error ? error.name : "unknown"}`,
      );
      return this.complete(record.id, {
        status: BroadcastStatus.FAILED,
        recipientCount: 0,
        sentCount: 0,
        failedCount: 0,
        staleTokensRemoved: 0,
        errorMessage: "Sending failed before any notification was delivered.",
      });
    }

    return this.complete(record.id, {
      status: this.statusFor(stats),
      recipientCount: stats.recipients,
      sentCount: stats.sent,
      failedCount: stats.failed,
      staleTokensRemoved: stats.staleRemoved,
      errorMessage: null,
    });
  }

  list(limit = 50) {
    return this.prisma.notificationBroadcast.findMany({
      orderBy: { createdAt: "desc" },
      take: limit,
    });
  }

  /** No recipients is a successful empty broadcast, not a failure. */
  statusFor(stats: BroadcastSendStats): BroadcastStatus {
    if (stats.recipients === 0) return BroadcastStatus.SENT;
    if (stats.sent === 0) return BroadcastStatus.FAILED;
    if (stats.failed > 0) return BroadcastStatus.PARTIAL;
    return BroadcastStatus.SENT;
  }

  private findByKey(idempotencyKey: string) {
    return this.prisma.notificationBroadcast.findUnique({
      where: { idempotencyKey },
    });
  }

  private complete(
    id: string,
    data: {
      status: BroadcastStatus;
      recipientCount: number;
      sentCount: number;
      failedCount: number;
      staleTokensRemoved: number;
      errorMessage: string | null;
    },
  ) {
    return this.prisma.notificationBroadcast.update({
      where: { id },
      data: { ...data, completedAt: new Date() },
    });
  }
}
