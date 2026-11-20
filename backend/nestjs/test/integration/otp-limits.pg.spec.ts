import { HttpException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { PrismaClient } from "@prisma/client";
import { randomInt } from "crypto";
import { AuthService } from "../../src/auth/auth.service";
import { VerifyPhoneOtpDto } from "../../src/auth/dto/auth.dto";

/**
 * REAL PostgreSQL integration tests for the OTP security fixes.
 *
 * Runs only when INTEGRATION_DB_NAME is set and DATABASE_URL points at that
 * disposable database on 127.0.0.1:55432 (the yallacash-offers-e2e-pg test
 * container). Otherwise the whole suite is skipped, so the normal unit-test
 * run never touches a database. SMS delivery is always mocked.
 */

function isolatedDatabase(): boolean {
  const name = process.env.INTEGRATION_DB_NAME;
  const raw = process.env.DATABASE_URL;
  if (!name || !raw) return false;
  const url = new URL(raw);
  const ok =
    url.hostname === "127.0.0.1" &&
    url.port === "55432" &&
    url.pathname.slice(1) === name &&
    /^yallacash_security_it_\d{14}$/.test(name) &&
    !/neon|amazonaws|render|supabase/i.test(raw);
  if (!ok) throw new Error("Refusing to run: DATABASE_URL is not the disposable test database.");
  return true;
}

const describePg = isolatedDatabase() ? describe : describe.skip;
jest.setTimeout(60_000);

describePg("OTP security fixes against real PostgreSQL", () => {
  const prisma = new PrismaClient();
  const sms: { phone: string; code: string }[] = [];

  beforeAll(async () => {
    const [{ db }] = await prisma.$queryRaw<{ db: string }[]>`SELECT current_database() AS db`;
    if (db !== process.env.INTEGRATION_DB_NAME) throw new Error(`connected to ${db}`);
  });
  afterAll(() => prisma.$disconnect());
  beforeEach(async () => {
    sms.length = 0;
    await prisma.$executeRawUnsafe(
      'TRUNCATE "OtpChallenge", "RefreshToken", "CustomerProfile", "User" CASCADE',
    );
  });

  function service(overrides: Record<string, unknown> = {}) {
    const values: Record<string, unknown> = { NODE_ENV: "test", ...overrides };
    const config = {
      get: (key: string, fallback?: unknown) => (key in values ? values[key] : fallback),
      getOrThrow: (key: string) => {
        if (key === "SECRET_PEPPER") return "it-pepper-not-a-secret-0123";
        throw new Error(`unexpected config ${key}`);
      },
    };
    const linkSyria = {
      isConfigured: () => true,
      sendOtp: jest.fn(async (phone: string, code: string) => {
        sms.push({ phone, code });
      }),
    };
    const jwt = new JwtService({ secret: "it-access-secret-not-real-0123456789" });
    const auth = new AuthService(
      prisma as never,
      config as never,
      jwt,
      {} as never,
      {} as never,
      linkSyria as never,
    );
    return { auth, linkSyria };
  }

  const newPhone = () => `+9639${randomInt(10_000_000, 99_999_999)}`;
  const NO_SEND_LIMITS = {
    OTP_RESEND_COOLDOWN_SECONDS: 0,
    OTP_MAX_SENDS_PER_HOUR: 100,
    OTP_MAX_SENDS_PER_DAY: 100,
  };

  async function start(auth: AuthService, phone: string) {
    const res = await auth.requestPhoneOtp({ phone });
    const code = sms.filter((s) => s.phone === phone).at(-1)!.code;
    return { challengeId: res.challengeId, code };
  }
  const verify = (auth: AuthService, phone: string, challengeId: string, code: string) =>
    auth.verifyPhoneOtp({ challengeId, phone, code, name: "IT Customer" } as VerifyPhoneOtpDto);
  const wrong = (code: string) => (code === "000000" ? "111111" : "000000");
  const failedSum = async (phone: string) =>
    (
      await prisma.otpChallenge.aggregate({
        where: { phone, consumedAt: null },
        _sum: { attempts: true },
      })
    )._sum.attempts ?? 0;
  const backdate = (phone: string, seconds: number) =>
    prisma.$executeRaw`UPDATE "OtpChallenge" SET "createdAt" = "createdAt" - make_interval(secs => ${seconds}) WHERE phone = ${phone}`;
  async function settle(promises: Promise<unknown>[]) {
    const results = await Promise.allSettled(promises);
    const messages = results.map((r) => (r.status === "fulfilled" ? "ok" : (r.reason as Error).message));
    return (m: string) => messages.filter((x) => x === m).length;
  }

  it("executes pg_advisory_xact_lock and serializes holders of the same phone", async () => {
    const { auth } = service();
    const lock = (tx: unknown, phone: string) =>
      (auth as unknown as { lockPhone: (t: unknown, p: string) => Promise<void> }).lockPhone(tx, phone);
    const phone = newPhone();
    let releaseFirst!: () => void;
    const firstHolds = new Promise<void>((r) => (releaseFirst = r));
    let firstAcquired!: () => void;
    const acquired = new Promise<void>((r) => (firstAcquired = r));

    const first = prisma.$transaction(async (tx) => {
      await lock(tx, phone);
      firstAcquired();
      await firstHolds;
    }, { timeout: 20_000 });
    await acquired;

    const held = await prisma.$queryRaw<{ n: bigint }[]>`SELECT count(*)::bigint AS n FROM pg_locks WHERE locktype = 'advisory' AND granted`;
    expect(Number(held[0].n)).toBeGreaterThanOrEqual(1);

    let secondDone = false;
    const second = prisma.$transaction(async (tx) => {
      await lock(tx, phone);
      secondDone = true;
    }, { timeout: 20_000 });
    await new Promise((r) => setTimeout(r, 500));
    expect(secondDone).toBe(false); // blocked by the first holder

    // A different phone is not blocked.
    await prisma.$transaction((tx) => lock(tx, newPhone()));

    releaseFirst();
    await Promise.all([first, second]);
    expect(secondDone).toBe(true);
    const after = await prisma.$queryRaw<{ n: bigint }[]>`SELECT count(*)::bigint AS n FROM pg_locks WHERE locktype = 'advisory'`;
    expect(Number(after[0].n)).toBe(0); // released at commit
  });

  it("caps concurrent wrong guesses on one challenge at exactly the limit", async () => {
    const { auth } = service();
    const phone = newPhone();
    const a = await start(auth, phone);
    const count = await settle(
      Array.from({ length: 12 }, () => verify(auth, phone, a.challengeId, wrong(a.code))),
    );
    expect(count("OTP code is incorrect.")).toBe(5);
    expect(count("Too many OTP attempts.")).toBe(7);
    const row = await prisma.otpChallenge.findUniqueOrThrow({ where: { id: a.challengeId } });
    expect(row.attempts).toBe(5);
    expect(row.consumedAt).toBeNull();
  });

  it("caps concurrent wrong guesses spread across several challenges", async () => {
    const { auth } = service(NO_SEND_LIMITS);
    const phone = newPhone();
    const cs = [await start(auth, phone), await start(auth, phone), await start(auth, phone)];
    const count = await settle(
      cs.flatMap((c) => Array.from({ length: 4 }, () => verify(auth, phone, c.challengeId, wrong(c.code)))),
    );
    expect(count("OTP code is incorrect.")).toBe(5);
    expect(await failedSum(phone)).toBe(5);
  });

  it("persists failed attempts across new OTP requests (no reset)", async () => {
    const { auth } = service(NO_SEND_LIMITS);
    const phone = newPhone();
    const a = await start(auth, phone);
    for (let i = 0; i < 3; i++) {
      await expect(verify(auth, phone, a.challengeId, wrong(a.code))).rejects.toThrow("OTP code is incorrect.");
    }
    const b = await start(auth, phone);
    expect(await failedSum(phone)).toBe(3);
    for (let i = 0; i < 2; i++) {
      await expect(verify(auth, phone, b.challengeId, wrong(b.code))).rejects.toThrow("OTP code is incorrect.");
    }
    await expect(verify(auth, phone, b.challengeId, b.code)).rejects.toThrow("Too many OTP attempts.");
    expect(await prisma.user.count({ where: { phone } })).toBe(0);
  });

  it("locks the phone (no new codes, no SMS) until the window passes; other phones unaffected", async () => {
    const { auth, linkSyria } = service(NO_SEND_LIMITS);
    const phone = newPhone();
    const a = await start(auth, phone);
    for (let i = 0; i < 5; i++) {
      await verify(auth, phone, a.challengeId, wrong(a.code)).catch(() => undefined);
    }
    const err = await auth.requestPhoneOtp({ phone }).catch((e) => e);
    expect(err).toBeInstanceOf(HttpException);
    expect((err as HttpException).getStatus()).toBe(429);
    expect(linkSyria.sendOtp).toHaveBeenCalledTimes(1);
    expect(await prisma.otpChallenge.count({ where: { phone } })).toBe(1); // nothing inserted

    const other = newPhone();
    const o = await start(auth, other);
    await expect(verify(auth, other, o.challengeId, o.code)).resolves.toBeDefined();

    await backdate(phone, 16 * 60); // past the 15-minute window
    const b = await start(auth, phone);
    await expect(verify(auth, phone, b.challengeId, b.code)).resolves.toBeDefined();
  });

  it("enforces the resend cooldown", async () => {
    const { auth, linkSyria } = service({ OTP_RESEND_COOLDOWN_SECONDS: 60 });
    const phone = newPhone();
    await start(auth, phone);
    const err = (await auth.requestPhoneOtp({ phone }).catch((e) => e)) as HttpException;
    expect(err.getStatus()).toBe(429);
    expect(err.getResponse()).toMatchObject({ message: "Please wait before requesting another code." });
    expect((err.getResponse() as { retryAfterSeconds: number }).retryAfterSeconds).toBeGreaterThan(50);
    await backdate(phone, 61);
    await expect(start(auth, phone)).resolves.toBeDefined();
    expect(linkSyria.sendOtp).toHaveBeenCalledTimes(2);
  });

  it("sends a single SMS for concurrent start requests", async () => {
    const { auth, linkSyria } = service({ OTP_RESEND_COOLDOWN_SECONDS: 60 });
    const phone = newPhone();
    const count = await settle(Array.from({ length: 8 }, () => auth.requestPhoneOtp({ phone })));
    expect(count("ok")).toBe(1);
    expect(linkSyria.sendOtp).toHaveBeenCalledTimes(1);
    expect(await prisma.otpChallenge.count({ where: { phone } })).toBe(1);
  });

  it("enforces the hourly SMS limit", async () => {
    const { auth } = service({ OTP_RESEND_COOLDOWN_SECONDS: 0, OTP_MAX_SENDS_PER_HOUR: 3, OTP_MAX_SENDS_PER_DAY: 100 });
    const phone = newPhone();
    for (let i = 0; i < 3; i++) await start(auth, phone);
    await expect(auth.requestPhoneOtp({ phone })).rejects.toMatchObject({ status: 429 });
    await backdate(phone, 61 * 60);
    await expect(start(auth, phone)).resolves.toBeDefined();
  });

  it("enforces the daily SMS limit", async () => {
    const { auth } = service({ OTP_RESEND_COOLDOWN_SECONDS: 0, OTP_MAX_SENDS_PER_HOUR: 100, OTP_MAX_SENDS_PER_DAY: 4 });
    const phone = newPhone();
    for (let i = 0; i < 4; i++) await start(auth, phone);
    await expect(auth.requestPhoneOtp({ phone })).rejects.toMatchObject({ status: 429 });
    await backdate(phone, 2 * 3600); // still within 24h
    await expect(auth.requestPhoneOtp({ phone })).rejects.toMatchObject({ status: 429 });
    await backdate(phone, 23 * 3600); // now > 24h old
    await expect(start(auth, phone)).resolves.toBeDefined();
  });

  it("logs in successfully and persists user, profile, refresh token and consumed challenge", async () => {
    const { auth } = service();
    const phone = newPhone();
    const a = await start(auth, phone);
    const res = await verify(auth, phone, a.challengeId, a.code);
    expect(res.accessToken).toEqual(expect.any(String));
    expect(res.refreshToken).toEqual(expect.any(String));
    const user = await prisma.user.findUniqueOrThrow({ where: { phone }, include: { customer: true } });
    expect(user.role).toBe("CUSTOMER");
    expect(user.customer?.name).toBe("IT Customer");
    expect(await prisma.refreshToken.count({ where: { userId: user.id } })).toBe(1);
    const row = await prisma.otpChallenge.findUniqueOrThrow({ where: { id: a.challengeId } });
    expect(row.consumedAt).not.toBeNull();
    expect(row.userId).toBe(user.id);
    // Replay of the same challenge is refused.
    await expect(verify(auth, phone, a.challengeId, a.code)).rejects.toThrow("OTP challenge is invalid.");
  });

  it("invalidates other open challenges after a successful login and clears the failure count", async () => {
    const { auth } = service(NO_SEND_LIMITS);
    const phone = newPhone();
    const a = await start(auth, phone);
    await verify(auth, phone, a.challengeId, wrong(a.code)).catch(() => undefined);
    const b = await start(auth, phone);
    const c = await start(auth, phone);
    await expect(verify(auth, phone, b.challengeId, b.code)).resolves.toBeDefined();
    const open = await prisma.otpChallenge.count({ where: { phone, consumedAt: null } });
    expect(open).toBe(0);
    await expect(verify(auth, phone, a.challengeId, a.code)).rejects.toThrow("OTP challenge is invalid.");
    await expect(verify(auth, phone, c.challengeId, c.code)).rejects.toThrow("OTP challenge is invalid.");
    expect(await failedSum(phone)).toBe(0);
  });

  it("rolls back the whole login when a step fails, leaving no partial state and no held lock", async () => {
    const { auth } = service();
    const phone = newPhone();
    const a = await start(auth, phone);
    const original = prisma.$transaction.bind(prisma);
    const spy = jest
      .spyOn(prisma, "$transaction")
      .mockImplementationOnce(((fn: (tx: unknown) => Promise<unknown>, opts: unknown) =>
        original(
          (tx) =>
            fn(
              new Proxy(tx, {
                get: (target, prop) =>
                  prop === "customerProfile"
                    ? { upsert: async () => { throw new Error("injected failure"); } }
                    : (target as never)[prop],
              }),
            ),
          opts as never,
        )) as never);

    await expect(verify(auth, phone, a.challengeId, a.code)).rejects.toThrow("injected failure");
    spy.mockRestore();

    // user.upsert ran before the failure but was rolled back.
    expect(await prisma.user.count({ where: { phone } })).toBe(0);
    const row = await prisma.otpChallenge.findUniqueOrThrow({ where: { id: a.challengeId } });
    expect(row.consumedAt).toBeNull();
    expect(row.attempts).toBe(0);
    const locks = await prisma.$queryRaw<{ n: bigint }[]>`SELECT count(*)::bigint AS n FROM pg_locks WHERE locktype = 'advisory'`;
    expect(Number(locks[0].n)).toBe(0);

    // The same code still works afterwards: state is consistent.
    await expect(verify(auth, phone, a.challengeId, a.code)).resolves.toBeDefined();
  });

  it("commits a wrong-guess increment even though the request fails", async () => {
    const { auth } = service();
    const phone = newPhone();
    const a = await start(auth, phone);
    await expect(verify(auth, phone, a.challengeId, wrong(a.code))).rejects.toThrow("OTP code is incorrect.");
    const row = await prisma.otpChallenge.findUniqueOrThrow({ where: { id: a.challengeId } });
    expect(row.attempts).toBe(1);
  });

  it("leaves the database consistent after the whole suite's traffic", async () => {
    const { auth } = service(NO_SEND_LIMITS);
    const phones = [newPhone(), newPhone(), newPhone()];
    await Promise.all(
      phones.map(async (phone) => {
        const a = await start(auth, phone);
        await settle(Array.from({ length: 8 }, () => verify(auth, phone, a.challengeId, wrong(a.code))));
      }),
    );
    const violations = await prisma.$queryRaw<{ phone: string; total: bigint }[]>`
      SELECT phone, sum(attempts)::bigint AS total FROM "OtpChallenge"
      WHERE "consumedAt" IS NULL GROUP BY phone HAVING sum(attempts) > 5`;
    expect(violations).toEqual([]);
    const overPerChallenge = await prisma.otpChallenge.count({ where: { attempts: { gt: 5 } } });
    expect(overPerChallenge).toBe(0);
  });
});
