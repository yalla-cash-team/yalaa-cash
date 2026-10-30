import { ConflictException } from "@nestjs/common";
import { BroadcastStatus, Prisma } from "@prisma/client";
import { PrismaService } from "../src/prisma/prisma.service";
import { FcmService } from "../src/notifications/fcm.service";
import { NotificationBroadcastService } from "../src/notifications/notification-broadcast.service";

// Mocked collaborators: no test ever reaches Firebase or a real device.
function setup() {
  const prisma = {
    notificationBroadcast: {
      findUnique: jest.fn().mockResolvedValue(null),
      findFirst: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockImplementation(async ({ data }) => ({
        id: "b1",
        ...data,
      })),
      update: jest.fn().mockImplementation(async ({ data }) => ({
        id: "b1",
        ...data,
      })),
      findMany: jest.fn(),
    },
  };
  const fcm = {
    sendToAllCustomers: jest.fn().mockResolvedValue({
      recipients: 10,
      sent: 9,
      failed: 1,
      staleRemoved: 1,
    }),
  };
  const service = new NotificationBroadcastService(
    prisma as unknown as PrismaService,
    fcm as unknown as FcmService,
  );
  return { service, prisma, fcm };
}

const request = {
  title: "Hello",
  body: "New offers this week",
  idempotencyKey: "key-0123456789abcdef",
};

describe("NotificationBroadcastService", () => {
  it("returns the original record for a repeated key without sending again", async () => {
    const { service, prisma, fcm } = setup();
    prisma.notificationBroadcast.findUnique.mockResolvedValueOnce({
      id: "old",
      status: BroadcastStatus.SENT,
    });

    const result = await service.send("admin-1", request);

    expect(result.id).toBe("old");
    expect(fcm.sendToAllCustomers).not.toHaveBeenCalled();
    expect(prisma.notificationBroadcast.create).not.toHaveBeenCalled();
  });

  it("blocks a second broadcast while another one is still pending", async () => {
    const { service, prisma, fcm } = setup();
    prisma.notificationBroadcast.findFirst.mockResolvedValueOnce({ id: "p" });

    await expect(service.send("admin-1", request)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(fcm.sendToAllCustomers).not.toHaveBeenCalled();
  });

  it("records real delivery counts after sending", async () => {
    const { service, prisma, fcm } = setup();

    const result = await service.send("admin-1", request);

    expect(fcm.sendToAllCustomers).toHaveBeenCalledWith({
      title: "Hello",
      body: "New offers this week",
    });
    expect(result.status).toBe(BroadcastStatus.PARTIAL);
    expect(result.recipientCount).toBe(10);
    expect(result.sentCount).toBe(9);
    expect(result.failedCount).toBe(1);
    expect(result.staleTokensRemoved).toBe(1);
    expect(prisma.notificationBroadcast.update).toHaveBeenCalled();
  });

  it("records a failure instead of throwing when FCM rejects", async () => {
    const { service, fcm } = setup();
    fcm.sendToAllCustomers.mockRejectedValueOnce(new Error("db down"));

    const result = await service.send("admin-1", request);

    expect(result.status).toBe(BroadcastStatus.FAILED);
    expect(result.errorMessage).toMatch(/Sending failed/);
  });

  it("returns the racing record when a duplicate key wins the insert", async () => {
    const { service, prisma, fcm } = setup();
    prisma.notificationBroadcast.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ id: "winner" });
    prisma.notificationBroadcast.create.mockRejectedValueOnce(
      new Prisma.PrismaClientKnownRequestError("duplicate", {
        code: "P2002",
        clientVersion: "test",
      }),
    );

    const result = await service.send("admin-1", request);

    expect(result.id).toBe("winner");
    expect(fcm.sendToAllCustomers).not.toHaveBeenCalled();
  });

  it("maps delivery counts to a status", () => {
    const { service } = setup();
    const status = (recipients: number, sent: number, failed: number) =>
      service.statusFor({ recipients, sent, failed, staleRemoved: 0 });

    expect(status(0, 0, 0)).toBe(BroadcastStatus.SENT);
    expect(status(5, 5, 0)).toBe(BroadcastStatus.SENT);
    expect(status(5, 3, 2)).toBe(BroadcastStatus.PARTIAL);
    expect(status(5, 0, 5)).toBe(BroadcastStatus.FAILED);
  });
});
