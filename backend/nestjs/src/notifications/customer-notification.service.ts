import { Injectable, NotFoundException } from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";

/// Rows per createMany call, keeping each insert statement small.
export const INBOX_INSERT_CHUNK = 1000;

const INBOX_SELECT = {
  id: true,
  broadcastId: true,
  title: true,
  body: true,
  createdAt: true,
  readAt: true,
} as const;

interface InboxRow {
  id: string;
  broadcastId: string | null;
  title: string;
  body: string;
  createdAt: Date;
  readAt: Date | null;
}

export function presentCustomerNotification(row: InboxRow) {
  return {
    id: row.id,
    broadcastId: row.broadcastId,
    title: row.title,
    body: row.body,
    createdAt: row.createdAt.toISOString(),
    readAt: row.readAt?.toISOString() ?? null,
  };
}

/**
 * The customer notification inbox. Every query is scoped by the signed-in
 * customer's own userId, so a customer can never read or mark another
 * customer's notifications.
 */
@Injectable()
export class CustomerNotificationService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Saves [broadcast] in the inbox of every active customer, including
   * customers without a push token. Idempotent: the unique
   * (broadcastId, userId) pair plus skipDuplicates means a retry never
   * creates a second entry. Returns the number of intended customers.
   */
  async deliverBroadcast(broadcast: {
    id: string;
    title: string;
    body: string;
  }): Promise<number> {
    const customers = await this.prisma.user.findMany({
      where: { role: UserRole.CUSTOMER, isActive: true },
      select: { id: true },
    });
    for (let i = 0; i < customers.length; i += INBOX_INSERT_CHUNK) {
      await this.prisma.customerNotification.createMany({
        data: customers.slice(i, i + INBOX_INSERT_CHUNK).map((customer) => ({
          userId: customer.id,
          broadcastId: broadcast.id,
          title: broadcast.title,
          body: broadcast.body,
        })),
        skipDuplicates: true,
      });
    }
    return customers.length;
  }

  /** The customer's notifications, newest first, plus their unread count. */
  async list(userId: string, options: { unreadOnly: boolean; limit: number }) {
    const [rows, unreadCount] = await Promise.all([
      this.prisma.customerNotification.findMany({
        where: { userId, ...(options.unreadOnly ? { readAt: null } : {}) },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: options.limit,
        select: INBOX_SELECT,
      }),
      this.unreadCount(userId),
    ]);
    return { items: rows.map(presentCustomerNotification), unreadCount };
  }

  /**
   * Marks exactly one of the customer's own notifications as read. Reading
   * an already-read notification keeps its original readAt. 404 when the id
   * does not exist or belongs to someone else (no existence leak).
   */
  async markRead(userId: string, notificationId: string, now = new Date()) {
    await this.prisma.customerNotification.updateMany({
      where: { id: notificationId, userId, readAt: null },
      data: { readAt: now },
    });
    const row = await this.prisma.customerNotification.findFirst({
      where: { id: notificationId, userId },
      select: INBOX_SELECT,
    });
    if (!row) throw new NotFoundException("Notification was not found.");
    return {
      ...presentCustomerNotification(row),
      unreadCount: await this.unreadCount(userId),
    };
  }

  private unreadCount(userId: string) {
    return this.prisma.customerNotification.count({
      where: { userId, readAt: null },
    });
  }
}
