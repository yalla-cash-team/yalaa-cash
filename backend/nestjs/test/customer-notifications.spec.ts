import { INestApplication, ValidationPipe } from "@nestjs/common";
import { APP_GUARD } from "@nestjs/core";
import { JwtService } from "@nestjs/jwt";
import { Test } from "@nestjs/testing";
import { BroadcastStatus, UserRole } from "@prisma/client";
import { JwtAuthGuard } from "../src/auth/guards/jwt-auth.guard";
import { RolesGuard } from "../src/auth/guards/roles.guard";
import { CustomerNotificationService } from "../src/notifications/customer-notification.service";
import { CustomerNotificationsController } from "../src/notifications/customer-notifications.controller";
import { FcmService } from "../src/notifications/fcm.service";
import { NotificationBroadcastService } from "../src/notifications/notification-broadcast.service";
import { PrismaService } from "../src/prisma/prisma.service";

/**
 * Customer notification inbox: delivery from admin broadcasts (with an
 * in-memory Prisma fake and a mocked FCM, so nothing reaches Firebase or a
 * database), recipient isolation, unread counts, single-item read marking and
 * duplicate prevention, plus HTTP-level auth through the real global guards.
 */

interface Row {
  id: string;
  userId: string;
  broadcastId: string | null;
  title: string;
  body: string;
  createdAt: Date;
  readAt: Date | null;
}

interface FakeUser {
  id: string;
  role: UserRole;
  isActive: boolean;
}

function uuid(n: number) {
  return `00000000-0000-4000-8000-${n.toString().padStart(12, "0")}`;
}

function createFakePrisma(users: FakeUser[]) {
  const rows: Row[] = [];
  const broadcasts: any[] = [];
  let seq = 0;
  let clock = Date.UTC(2026, 10, 7, 10);
  const matches = (row: Row, where: any) =>
    Object.entries(where).every(([key, value]) => (row as any)[key] === value);
  const pick = (row: Row) => ({
    id: row.id,
    broadcastId: row.broadcastId,
    title: row.title,
    body: row.body,
    createdAt: row.createdAt,
    readAt: row.readAt,
  });
  return {
    rows,
    broadcasts,
    user: {
      findMany: jest.fn(async ({ where }: any) =>
        users
          .filter((u) => u.role === where.role && u.isActive === where.isActive)
          .map((u) => ({ id: u.id })),
      ),
      findUnique: jest.fn(async ({ where }: any) => {
        const user = users.find((u) => u.id === where.id);
        return user ? { ...user } : null;
      }),
    },
    customerNotification: {
      createMany: jest.fn(async ({ data, skipDuplicates }: any) => {
        let count = 0;
        for (const item of data) {
          const duplicate = rows.some(
            (r) => r.broadcastId === item.broadcastId && r.userId === item.userId,
          );
          if (duplicate) {
            if (skipDuplicates) continue;
            throw new Error("unique violation");
          }
          rows.push({
            id: uuid(++seq),
            createdAt: new Date((clock += 1000)),
            readAt: null,
            ...item,
          });
          count++;
        }
        return { count };
      }),
      findMany: jest.fn(async ({ where, take }: any) =>
        rows
          .filter((r) => matches(r, where))
          .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
          .slice(0, take)
          .map(pick),
      ),
      count: jest.fn(async ({ where }: any) =>
        rows.filter((r) => matches(r, where)).length,
      ),
      updateMany: jest.fn(async ({ where, data }: any) => {
        const hits = rows.filter((r) => matches(r, where));
        hits.forEach((r) => Object.assign(r, data));
        return { count: hits.length };
      }),
      findFirst: jest.fn(async ({ where }: any) => {
        const row = rows.find((r) => matches(r, where));
        return row ? pick(row) : null;
      }),
    },
    notificationBroadcast: {
      findUnique: jest.fn(async ({ where }: any) =>
        broadcasts.find((b) => b.idempotencyKey === where.idempotencyKey) ?? null,
      ),
      findFirst: jest.fn(async () => null),
      create: jest.fn(async ({ data }: any) => {
        const record = { id: uuid(900 + broadcasts.length), status: BroadcastStatus.PENDING, ...data };
        broadcasts.push(record);
        return record;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const record = broadcasts.find((b) => b.id === where.id);
        Object.assign(record, data);
        return record;
      }),
    },
  };
}

const USERS: FakeUser[] = [
  { id: uuid(101), role: UserRole.CUSTOMER, isActive: true }, // has a push token
  { id: uuid(102), role: UserRole.CUSTOMER, isActive: true }, // no push token
  { id: uuid(103), role: UserRole.CUSTOMER, isActive: false }, // deactivated
  { id: uuid(104), role: UserRole.MERCHANT, isActive: true },
  { id: uuid(105), role: UserRole.ADMIN, isActive: true },
];
const [ALICE, BOB, INACTIVE, MERCHANT, ADMIN] = USERS.map((u) => u.id);

function setup(fcmImpl?: jest.Mock) {
  const prisma = createFakePrisma(USERS);
  const fcm = {
    sendToAllCustomers:
      fcmImpl ??
      jest.fn().mockResolvedValue({ recipients: 1, sent: 1, failed: 0, staleRemoved: 0 }),
  };
  const inbox = new CustomerNotificationService(prisma as unknown as PrismaService);
  const broadcasts = new NotificationBroadcastService(
    prisma as unknown as PrismaService,
    fcm as unknown as FcmService,
    inbox,
  );
  return { prisma, fcm, inbox, broadcasts };
}

const send = (broadcasts: NotificationBroadcastService, key: string, title = "عرض جديد") =>
  broadcasts.send(ADMIN, { title, body: `نص ${title}`, idempotencyKey: key });

describe("customer inbox delivery", () => {
  it("saves an admin broadcast for every active customer, with or without a token", async () => {
    const { prisma, broadcasts } = setup();

    const record = await send(broadcasts, "key-a-0123456789");

    expect(record.status).toBe(BroadcastStatus.SENT);
    expect(prisma.rows.map((r) => r.userId).sort()).toEqual([ALICE, BOB].sort());
    expect(prisma.rows.every((r) => r.broadcastId === record.id && r.readAt === null)).toBe(true);
    expect(prisma.rows[0].title).toBe("عرض جديد");
  });

  it("never delivers to merchants, admins or deactivated customers", async () => {
    const { prisma, broadcasts } = setup();
    await send(broadcasts, "key-b-0123456789");
    const recipients = prisma.rows.map((r) => r.userId);
    expect(recipients).not.toContain(INACTIVE);
    expect(recipients).not.toContain(MERCHANT);
    expect(recipients).not.toContain(ADMIN);
  });

  it("the inbox is written before the push, which carries the broadcast id", async () => {
    let rowsAtPush = -1;
    const { prisma, broadcasts } = setup(
      jest.fn().mockImplementation(async () => {
        rowsAtPush = prisma.rows.length;
        return { recipients: 1, sent: 1, failed: 0, staleRemoved: 0 };
      }),
    );
    const record = await send(broadcasts, "key-c-0123456789");
    expect(rowsAtPush).toBe(2);
    const { fcm } = { fcm: (broadcasts as any).fcm };
    expect(fcm.sendToAllCustomers).toHaveBeenCalledWith(
      expect.objectContaining({ data: { type: "broadcast", broadcastId: record.id } }),
    );
  });

  it("customers keep the notification even when push delivery fails", async () => {
    const { prisma, broadcasts } = setup(jest.fn().mockRejectedValue(new Error("fcm down")));
    const record = await send(broadcasts, "key-d-0123456789");
    expect(record.status).toBe(BroadcastStatus.FAILED);
    expect(prisma.rows).toHaveLength(2);
  });

  it("no push is sent if the inbox cannot be saved", async () => {
    const { prisma, fcm, broadcasts } = setup();
    prisma.customerNotification.createMany.mockRejectedValueOnce(new Error("db"));
    const record = await send(broadcasts, "key-e-0123456789");
    expect(record.status).toBe(BroadcastStatus.FAILED);
    expect(record.errorMessage).toMatch(/inbox/);
    expect(fcm.sendToAllCustomers).not.toHaveBeenCalled();
  });

  it("duplicates are impossible: a retried key and a re-delivery add nothing", async () => {
    const { prisma, fcm, inbox, broadcasts } = setup();
    const first = await send(broadcasts, "key-f-0123456789");
    const again = await send(broadcasts, "key-f-0123456789");
    expect(again.id).toBe(first.id);
    expect(fcm.sendToAllCustomers).toHaveBeenCalledTimes(1);
    await inbox.deliverBroadcast(first); // e.g. a manual retry of the inbox step
    expect(prisma.rows).toHaveLength(2);
  });
});

describe("customer inbox reads", () => {
  it("lists only the customer's own unread notifications, newest first, with a count", async () => {
    const { inbox, broadcasts } = setup();
    await send(broadcasts, "key-g-0123456789", "الأول");
    await send(broadcasts, "key-h-0123456789", "الثاني");

    const alice = await inbox.list(ALICE, { unreadOnly: true, limit: 50 });

    expect(alice.unreadCount).toBe(2);
    expect(alice.items.map((i) => i.title)).toEqual(["الثاني", "الأول"]);
    expect(alice.items[0]).toEqual({
      id: expect.any(String),
      broadcastId: expect.any(String),
      title: "الثاني",
      body: "نص الثاني",
      createdAt: expect.stringMatching(/Z$/),
      readAt: null,
    });
  });

  it("marking one notification read changes only that one, only for that customer", async () => {
    const { inbox, broadcasts } = setup();
    await send(broadcasts, "key-i-0123456789", "الأول");
    await send(broadcasts, "key-j-0123456789", "الثاني");
    const [newest, older] = (await inbox.list(ALICE, { unreadOnly: true, limit: 50 })).items;

    const read = await inbox.markRead(ALICE, older.id, new Date("2026-11-07T12:00:00Z"));

    expect(read.readAt).toBe("2026-11-07T12:00:00.000Z");
    expect(read.unreadCount).toBe(1);
    const aliceUnread = await inbox.list(ALICE, { unreadOnly: true, limit: 50 });
    expect(aliceUnread.items.map((i) => i.id)).toEqual([newest.id]);
    // Bob's copies are untouched.
    expect((await inbox.list(BOB, { unreadOnly: true, limit: 50 })).unreadCount).toBe(2);
    // The full list still has it, now read (persisted, does not reappear as unread).
    const all = await inbox.list(ALICE, { unreadOnly: false, limit: 50 });
    expect(all.items.find((i) => i.id === older.id)?.readAt).toBe(read.readAt);
  });

  it("reading twice keeps the first readAt", async () => {
    const { inbox, broadcasts } = setup();
    await send(broadcasts, "key-k-0123456789");
    const [item] = (await inbox.list(ALICE, { unreadOnly: true, limit: 5 })).items;
    const first = await inbox.markRead(ALICE, item.id, new Date("2026-11-07T12:00:00Z"));
    const second = await inbox.markRead(ALICE, item.id, new Date("2026-11-08T12:00:00Z"));
    expect(second.readAt).toBe(first.readAt);
  });

  it("another customer's notification cannot be marked or seen (404)", async () => {
    const { inbox, broadcasts, prisma } = setup();
    await send(broadcasts, "key-l-0123456789");
    const bobs = prisma.rows.find((r) => r.userId === BOB)!;
    await expect(inbox.markRead(ALICE, bobs.id)).rejects.toThrow("Notification was not found.");
    expect(bobs.readAt).toBeNull();
  });
});

describe("HTTP: /customer/notifications", () => {
  const TOKENS: Record<string, { sub: string; role: UserRole }> = {
    "alice-token": { sub: ALICE, role: UserRole.CUSTOMER },
    "bob-token": { sub: BOB, role: UserRole.CUSTOMER },
    "merchant-token": { sub: MERCHANT, role: UserRole.MERCHANT },
    "admin-token": { sub: ADMIN, role: UserRole.ADMIN },
  };
  let app: INestApplication;
  let baseUrl: string;
  let ctx: ReturnType<typeof setup>;

  beforeEach(async () => {
    ctx = setup();
    await send(ctx.broadcasts, "key-http-0123456789", "الأول");
    await send(ctx.broadcasts, "key-http2-0123456789", "الثاني");
    const moduleRef = await Test.createTestingModule({
      controllers: [CustomerNotificationsController],
      providers: [
        { provide: CustomerNotificationService, useValue: ctx.inbox },
        { provide: PrismaService, useValue: ctx.prisma },
        {
          provide: JwtService,
          useValue: {
            verifyAsync: async (token: string) => {
              const payload = TOKENS[token];
              if (!payload) throw new Error("invalid token");
              return payload;
            },
          },
        },
        { provide: APP_GUARD, useClass: JwtAuthGuard },
        { provide: APP_GUARD, useClass: RolesGuard },
      ],
    }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }),
    );
    await app.listen(0, "127.0.0.1");
    baseUrl = (await app.getUrl()).replace("[::1]", "127.0.0.1");
  });
  afterEach(() => app.close());

  const call = async (method: string, path: string, token?: string) => {
    const res = await fetch(`${baseUrl}${path}`, {
      method,
      headers: token ? { authorization: `Bearer ${token}` } : {},
    });
    return { status: res.status, body: (await res.json()) as any };
  };

  it("401 without a token; 403 for merchant and admin", async () => {
    expect((await call("GET", "/customer/notifications")).status).toBe(401);
    expect((await call("GET", "/customer/notifications", "merchant-token")).status).toBe(403);
    expect((await call("GET", "/customer/notifications", "admin-token")).status).toBe(403);
    const anyId = ctx.prisma.rows[0].id;
    expect((await call("POST", `/customer/notifications/${anyId}/read`)).status).toBe(401);
    expect((await call("POST", `/customer/notifications/${anyId}/read`, "merchant-token")).status).toBe(403);
  });

  it("lists unread by default; opening the list marks nothing", async () => {
    const first = await call("GET", "/customer/notifications", "alice-token");
    const again = await call("GET", "/customer/notifications", "alice-token");
    expect(first.status).toBe(200);
    expect(first.body.unreadCount).toBe(2);
    expect(first.body.items.map((i: any) => i.title)).toEqual(["الثاني", "الأول"]);
    expect(again.body.unreadCount).toBe(2);
  });

  it("POST /:id/read marks only that item; a read item leaves the unread list", async () => {
    const list = await call("GET", "/customer/notifications", "alice-token");
    const target = list.body.items[1];
    const read = await call("POST", `/customer/notifications/${target.id}/read`, "alice-token");
    expect(read.status).toBe(200);
    expect(read.body.id).toBe(target.id);
    expect(read.body.readAt).not.toBeNull();
    expect(read.body.unreadCount).toBe(1);
    const after = await call("GET", "/customer/notifications", "alice-token");
    expect(after.body.items.map((i: any) => i.id)).not.toContain(target.id);
    const all = await call("GET", "/customer/notifications?unread=false", "alice-token");
    expect(all.body.items).toHaveLength(2);
  });

  it("isolation: Bob cannot read or mark Alice's notification", async () => {
    const alices = ctx.prisma.rows.find((r) => r.userId === ALICE)!;
    const bobList = await call("GET", "/customer/notifications?unread=false", "bob-token");
    expect(bobList.body.items.map((i: any) => i.id)).not.toContain(alices.id);
    const attempt = await call("POST", `/customer/notifications/${alices.id}/read`, "bob-token");
    expect(attempt.status).toBe(404);
    expect(alices.readAt).toBeNull();
  });

  it("validates ids and query parameters", async () => {
    expect((await call("POST", "/customer/notifications/not-a-uuid/read", "alice-token")).status).toBe(400);
    expect((await call("GET", "/customer/notifications?limit=0", "alice-token")).status).toBe(400);
    expect((await call("GET", "/customer/notifications?limit=500", "alice-token")).status).toBe(400);
    expect((await call("GET", "/customer/notifications?other=1", "alice-token")).status).toBe(400);
  });
});
