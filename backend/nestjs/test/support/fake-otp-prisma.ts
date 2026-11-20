/**
 * In-memory stand-in for the Prisma calls used by AuthService's phone-OTP
 * flow. It models the Postgres pieces the fix depends on:
 *  - `pg_advisory_xact_lock` (via tx.$queryRaw) as a FIFO mutex per key,
 *    held until the surrounding $transaction finishes;
 *  - Read Committed visibility (writes are visible as soon as they happen).
 * Every operation yields to the event loop first, so concurrent requests
 * genuinely interleave and a missing lock shows up as a race.
 */

export interface FakeChallenge {
  id: string;
  phone: string;
  codeHash: string;
  expiresAt: Date;
  consumedAt: Date | null;
  attempts: number;
  userId: string | null;
  createdAt: Date;
}

type Where = {
  id?: string | { not: string };
  phone?: string;
  consumedAt?: null;
  createdAt?: { gte?: Date };
};

const tick = () => new Promise<void>((resolve) => setImmediate(resolve));

function matches(row: FakeChallenge, where: Where = {}): boolean {
  if (typeof where.id === "string" && row.id !== where.id) return false;
  if (typeof where.id === "object" && row.id === where.id.not) return false;
  if (where.phone !== undefined && row.phone !== where.phone) return false;
  if (where.consumedAt === null && row.consumedAt !== null) return false;
  if (where.createdAt?.gte && row.createdAt < where.createdAt.gte) return false;
  return true;
}

export function createFakeOtpPrisma(options: { skipLock?: boolean } = {}) {
  const challenges: FakeChallenge[] = [];
  const users: { id: string; phone: string; role: string; isActive: boolean }[] =
    [];
  const lockTails = new Map<string, Promise<void>>();
  const lockKeys: string[] = [];
  const transactionOptions: unknown[] = [];
  let seq = 0;

  const otpChallenge = {
    create: async ({ data }: { data: Partial<FakeChallenge> }) => {
      await tick();
      const row: FakeChallenge = {
        id: `challenge-${++seq}`,
        attempts: 0,
        consumedAt: null,
        userId: null,
        createdAt: new Date(Date.now()),
        phone: "",
        codeHash: "",
        expiresAt: new Date(0),
        ...data,
      };
      challenges.push(row);
      return { ...row };
    },
    findUnique: async ({ where }: { where: { id: string } }) => {
      await tick();
      const row = challenges.find((c) => c.id === where.id);
      return row ? { ...row } : null;
    },
    findFirst: async ({ where }: { where: Where }) => {
      await tick();
      const rows = challenges
        .filter((c) => matches(c, where))
        .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
      return rows[0] ? { ...rows[0] } : null;
    },
    count: async ({ where }: { where: Where }) => {
      await tick();
      return challenges.filter((c) => matches(c, where)).length;
    },
    aggregate: async ({ where }: { where: Where }) => {
      await tick();
      const rows = challenges.filter((c) => matches(c, where));
      return {
        _sum: {
          attempts: rows.length
            ? rows.reduce((sum, c) => sum + c.attempts, 0)
            : null,
        },
      };
    },
    update: async ({
      where,
      data,
    }: {
      where: { id: string };
      data: {
        attempts?: { increment: number };
        consumedAt?: Date;
        userId?: string;
      };
    }) => {
      await tick();
      const row = challenges.find((c) => c.id === where.id);
      if (!row) throw new Error(`challenge ${where.id} not found`);
      if (data.attempts) row.attempts += data.attempts.increment;
      if (data.consumedAt) row.consumedAt = data.consumedAt;
      if (data.userId) row.userId = data.userId;
      return { ...row };
    },
    updateMany: async ({
      where,
      data,
    }: {
      where: Where;
      data: { consumedAt?: Date };
    }) => {
      await tick();
      const rows = challenges.filter((c) => matches(c, where));
      for (const row of rows) {
        if (data.consumedAt) row.consumedAt = data.consumedAt;
      }
      return { count: rows.length };
    },
  };

  const user = {
    upsert: async ({ where }: { where: { phone: string } }) => {
      await tick();
      let row = users.find((u) => u.phone === where.phone);
      if (!row) {
        row = { id: `user-${++seq}`, phone: where.phone, role: "CUSTOMER", isActive: true };
        users.push(row);
      }
      return { ...row };
    },
  };

  const customerProfile = {
    upsert: async () => {
      await tick();
      return {};
    },
  };

  async function acquire(key: string, held: (() => void)[]) {
    lockKeys.push(key);
    if (options.skipLock) return;
    const previous = lockTails.get(key) ?? Promise.resolve();
    let release!: () => void;
    const mine = new Promise<void>((resolve) => (release = resolve));
    lockTails.set(
      key,
      previous.then(() => mine),
    );
    await previous;
    held.push(release);
  }

  const prisma = {
    otpChallenge,
    user,
    customerProfile,
    $transaction: async (
      fn: (tx: unknown) => Promise<unknown>,
      txOptions?: unknown,
    ) => {
      transactionOptions.push(txOptions);
      const held: (() => void)[] = [];
      const tx = {
        otpChallenge,
        user,
        customerProfile,
        // Tagged template: the lock key is the single interpolated value.
        $queryRaw: async (_strings: TemplateStringsArray, ...values: unknown[]) => {
          await acquire(String(values[0]), held);
          return [{ locked: 1 }];
        },
      };
      try {
        return await fn(tx);
      } finally {
        held.forEach((release) => release());
      }
    },
  };

  return { prisma, challenges, users, lockKeys, transactionOptions };
}
