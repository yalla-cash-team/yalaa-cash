import { HttpException, HttpStatus } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { AuthService } from "../src/auth/auth.service";
import { VerifyPhoneOtpDto } from "../src/auth/dto/auth.dto";
import { envValidationSchema } from "../src/config/env.validation";
import { createFakeOtpPrisma } from "./support/fake-otp-prisma";

/**
 * Regression tests for the security audit findings on customer phone OTP:
 *  - auth-otp-bruteforce-unbounded-challenges: wrong guesses are limited per
 *    normalized phone across every challenge, atomically, and requesting a
 *    new code never resets the count.
 *  - auth-otp-send-no-per-phone-limit: resend cooldown plus hourly and daily
 *    SMS caps per phone.
 *  - auth-otp-dev-mode-in-production: dev mode can never be active in
 *    production.
 * SMS delivery is mocked; no network or database is used.
 */

const PEPPER = "test-pepper-0123456789";
const PHONE = "+963900000001";
const OTHER_PHONE = "+963900000002";
const START = Date.UTC(2026, 0, 1, 12, 0, 0);

let now = START;
beforeEach(() => {
  now = START;
  jest.spyOn(Date, "now").mockImplementation(() => now);
});
afterEach(() => jest.restoreAllMocks());
const advance = (seconds: number) => {
  now += seconds * 1000;
};

function setup(
  config: Record<string, unknown> = {},
  fakeOptions: { skipLock?: boolean } = {},
) {
  const fake = createFakeOtpPrisma(fakeOptions);
  const values: Record<string, unknown> = { NODE_ENV: "test", ...config };
  const configService = {
    get: jest.fn((key: string, fallback?: unknown) =>
      key in values ? values[key] : fallback,
    ),
    getOrThrow: jest.fn(() => PEPPER),
  };
  const sentCodes: { phone: string; code: string }[] = [];
  const linkSyria = {
    isConfigured: jest.fn(() => true),
    sendOtp: jest.fn(async (phone: string, code: string) => {
      sentCodes.push({ phone, code });
    }),
  };
  const service = new AuthService(
    fake.prisma as never,
    configService as never,
    {} as never,
    {} as never,
    {} as never,
    linkSyria as never,
  );
  const issue = jest
    .spyOn(
      service as unknown as { issueAuthResponse: (u: unknown) => unknown },
      "issueAuthResponse",
    )
    .mockImplementation(async (user) => ({ accessToken: "a", user }));

  const start = async (phone = PHONE) => {
    const res = await service.requestPhoneOtp({ phone });
    return { challengeId: res.challengeId, code: sentCodes[sentCodes.length - 1].code };
  };
  const verify = (challengeId: string, code: string, phone = PHONE) =>
    service.verifyPhoneOtp({
      challengeId,
      phone,
      code,
      name: "Customer",
    } as VerifyPhoneOtpDto);
  const wrong = (code: string) => (code === "000000" ? "111111" : "000000");

  return { fake, service, linkSyria, sentCodes, issue, start, verify, wrong };
}

async function settleAll(promises: Promise<unknown>[]) {
  const results = await Promise.allSettled(promises);
  const messages = results.map((r) =>
    r.status === "fulfilled" ? "ok" : (r.reason as Error).message,
  );
  const count = (m: string) => messages.filter((x) => x === m).length;
  return { messages, count };
}

const NO_COOLDOWN = { OTP_RESEND_COOLDOWN_SECONDS: 0, OTP_MAX_SENDS_PER_HOUR: 100, OTP_MAX_SENDS_PER_DAY: 100 };

describe("Finding auth-otp-bruteforce-unbounded-challenges", () => {
  it("counts wrong guesses across challenges: a new OTP does not reset them", async () => {
    const t = setup(NO_COOLDOWN);
    const a = await t.start();
    for (let i = 0; i < 3; i++) {
      await expect(t.verify(a.challengeId, t.wrong(a.code))).rejects.toThrow(
        "OTP code is incorrect.",
      );
    }
    const b = await t.start();
    for (let i = 0; i < 2; i++) {
      await expect(t.verify(b.challengeId, t.wrong(b.code))).rejects.toThrow(
        "OTP code is incorrect.",
      );
    }
    // Five failures across two challenges: even the correct code is refused.
    await expect(t.verify(b.challengeId, b.code)).rejects.toThrow(
      "Too many OTP attempts.",
    );
    // And a third, fresh challenge does not reopen guessing either.
    await expect(t.start()).rejects.toMatchObject({
      status: HttpStatus.TOO_MANY_REQUESTS,
    });
    expect(t.issue).not.toHaveBeenCalled();
  });

  it("caps concurrent wrong guesses on one challenge at the limit", async () => {
    const t = setup();
    const a = await t.start();
    const { count } = await settleAll(
      Array.from({ length: 12 }, () => t.verify(a.challengeId, t.wrong(a.code))),
    );
    expect(count("OTP code is incorrect.")).toBe(5);
    expect(count("Too many OTP attempts.")).toBe(7);
    expect(t.fake.challenges[0].attempts).toBe(5);
  });

  it("sanity check: without the per-phone lock the same burst exceeds the limit", async () => {
    const t = setup({}, { skipLock: true });
    const a = await t.start();
    const { count } = await settleAll(
      Array.from({ length: 12 }, () => t.verify(a.challengeId, t.wrong(a.code))),
    );
    // Proves the concurrency test above is meaningful.
    expect(count("OTP code is incorrect.")).toBeGreaterThan(5);
  });

  it("caps concurrent wrong guesses spread across several challenges", async () => {
    const t = setup(NO_COOLDOWN);
    const challenges = [await t.start(), await t.start(), await t.start()];
    const { count } = await settleAll(
      challenges.flatMap((c) =>
        Array.from({ length: 4 }, () => t.verify(c.challengeId, t.wrong(c.code))),
      ),
    );
    expect(count("OTP code is incorrect.")).toBe(5);
    expect(t.fake.challenges.reduce((s, c) => s + c.attempts, 0)).toBe(5);
  });

  it("refuses new codes (and sends no SMS) while the phone is locked", async () => {
    const t = setup(NO_COOLDOWN);
    const a = await t.start();
    for (let i = 0; i < 5; i++) {
      await t.verify(a.challengeId, t.wrong(a.code)).catch(() => undefined);
    }
    await expect(t.start()).rejects.toBeInstanceOf(HttpException);
    expect(t.linkSyria.sendOtp).toHaveBeenCalledTimes(1);
  });

  it("lets the real owner in again once the failure window has passed", async () => {
    const t = setup({ ...NO_COOLDOWN, OTP_FAILED_ATTEMPTS_WINDOW_SECONDS: 900 });
    const a = await t.start();
    for (let i = 0; i < 5; i++) {
      await t.verify(a.challengeId, t.wrong(a.code)).catch(() => undefined);
    }
    advance(901);
    const b = await t.start();
    await expect(t.verify(b.challengeId, b.code)).resolves.toBeDefined();
    expect(t.issue).toHaveBeenCalledTimes(1);
  });

  it("closes other open challenges on success, so stale codes stop working", async () => {
    const t = setup(NO_COOLDOWN);
    const a = await t.start();
    await t.verify(a.challengeId, t.wrong(a.code)).catch(() => undefined);
    const b = await t.start();
    await expect(t.verify(b.challengeId, b.code)).resolves.toBeDefined();
    expect(t.fake.challenges.every((c) => c.consumedAt !== null)).toBe(true);
    await expect(t.verify(a.challengeId, a.code)).rejects.toThrow(
      "OTP challenge is invalid.",
    );
  });

  it("still enforces the per-challenge attempt limit", async () => {
    const t = setup({ OTP_MAX_FAILED_ATTEMPTS: 100, OTP_MAX_ATTEMPTS_PER_CHALLENGE: 3 });
    const a = await t.start();
    for (let i = 0; i < 3; i++) {
      await expect(t.verify(a.challengeId, t.wrong(a.code))).rejects.toThrow(
        "OTP code is incorrect.",
      );
    }
    await expect(t.verify(a.challengeId, a.code)).rejects.toThrow(
      "Too many OTP attempts.",
    );
  });

  it("keys the lock on the normalized phone and uses Read Committed", async () => {
    const t = setup();
    const a = await t.service.requestPhoneOtp({ phone: "+963 900-000-001" });
    expect(t.fake.lockKeys).toEqual([`otp:${PHONE}`]);
    expect(t.fake.transactionOptions[0]).toMatchObject({
      isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted,
    });
    expect(a.challengeId).toBeDefined();
  });

  it("keeps phones independent: locking one does not affect another", async () => {
    const t = setup(NO_COOLDOWN);
    const a = await t.start();
    for (let i = 0; i < 5; i++) {
      await t.verify(a.challengeId, t.wrong(a.code)).catch(() => undefined);
    }
    const other = await t.start(OTHER_PHONE);
    await expect(t.verify(other.challengeId, other.code, OTHER_PHONE)).resolves.toBeDefined();
  });

  it("keeps the existing invalid/expired challenge errors", async () => {
    const t = setup();
    const a = await t.start();
    await expect(t.verify("missing", a.code)).rejects.toThrow("OTP challenge is invalid.");
    await expect(t.verify(a.challengeId, a.code, OTHER_PHONE)).rejects.toThrow(
      "OTP challenge is invalid.",
    );
    advance(301);
    await expect(t.verify(a.challengeId, a.code)).rejects.toThrow(
      "OTP challenge has expired.",
    );
  });
});

describe("Finding auth-otp-send-no-per-phone-limit", () => {
  it("enforces the resend cooldown and reports when to retry", async () => {
    const t = setup({ OTP_RESEND_COOLDOWN_SECONDS: 60 });
    await t.start();
    advance(20);
    const err = await t.service.requestPhoneOtp({ phone: PHONE }).catch((e) => e);
    expect(err).toBeInstanceOf(HttpException);
    expect(err.getStatus()).toBe(HttpStatus.TOO_MANY_REQUESTS);
    expect(err.getResponse()).toMatchObject({ retryAfterSeconds: 40 });
    expect(t.linkSyria.sendOtp).toHaveBeenCalledTimes(1);
    advance(41);
    await expect(t.start()).resolves.toBeDefined();
    expect(t.linkSyria.sendOtp).toHaveBeenCalledTimes(2);
  });

  it("enforces the hourly cap", async () => {
    const t = setup({ OTP_RESEND_COOLDOWN_SECONDS: 0, OTP_MAX_SENDS_PER_HOUR: 3 });
    for (let i = 0; i < 3; i++) {
      await t.start();
      advance(60);
    }
    await expect(t.start()).rejects.toMatchObject({ status: 429 });
    advance(3600);
    await expect(t.start()).resolves.toBeDefined();
    expect(t.linkSyria.sendOtp).toHaveBeenCalledTimes(4);
  });

  it("enforces the daily cap", async () => {
    const t = setup({
      OTP_RESEND_COOLDOWN_SECONDS: 0,
      OTP_MAX_SENDS_PER_HOUR: 100,
      OTP_MAX_SENDS_PER_DAY: 4,
    });
    for (let i = 0; i < 4; i++) {
      await t.start();
      advance(2 * 3600);
    }
    await expect(t.start()).rejects.toMatchObject({ status: 429 });
    advance(24 * 3600);
    await expect(t.start()).resolves.toBeDefined();
  });

  it("uses the documented defaults (60s cooldown, 5/hour, 10/day)", async () => {
    const t = setup();
    for (let i = 0; i < 5; i++) {
      await t.start();
      advance(61);
    }
    await expect(t.start()).rejects.toMatchObject({ status: 429 });
  });

  it("sends only one SMS for concurrent start requests on one phone", async () => {
    const t = setup({ OTP_RESEND_COOLDOWN_SECONDS: 60 });
    const { count } = await settleAll(
      Array.from({ length: 8 }, () => t.service.requestPhoneOtp({ phone: PHONE })),
    );
    expect(count("ok")).toBe(1);
    expect(t.linkSyria.sendOtp).toHaveBeenCalledTimes(1);
    expect(t.fake.challenges).toHaveLength(1);
  });

  it("limits each phone separately", async () => {
    const t = setup({ OTP_RESEND_COOLDOWN_SECONDS: 60 });
    await t.start(PHONE);
    await expect(t.start(OTHER_PHONE)).resolves.toBeDefined();
  });
});

describe("Finding auth-otp-dev-mode-in-production", () => {
  const baseEnv = {
    DATABASE_URL: "postgresql://u:p@localhost:5432/db",
    JWT_ACCESS_SECRET: "a".repeat(32),
    JWT_REFRESH_SECRET: "b".repeat(32),
    QR_TOKEN_SECRET: "c".repeat(32),
    SECRET_PEPPER: "d".repeat(16),
  };

  it("refuses to start with OTP_DEV_MODE=true in production", () => {
    const { error } = envValidationSchema.validate({
      ...baseEnv,
      NODE_ENV: "production",
      OTP_DEV_MODE: "true",
    });
    expect(error?.message).toContain("OTP_DEV_MODE must not be enabled");
  });

  it("accepts production with dev mode off or unset, and dev mode in development", () => {
    expect(
      envValidationSchema.validate({ ...baseEnv, NODE_ENV: "production", OTP_DEV_MODE: "false" }).error,
    ).toBeUndefined();
    const prod = envValidationSchema.validate({ ...baseEnv, NODE_ENV: "production" });
    expect(prod.error).toBeUndefined();
    expect(prod.value.OTP_DEV_MODE).toBe(false);
    expect(
      envValidationSchema.validate({ ...baseEnv, NODE_ENV: "development", OTP_DEV_MODE: "true" }).error,
    ).toBeUndefined();
  });

  it("applies the OTP limit defaults", () => {
    const { value } = envValidationSchema.validate(baseEnv);
    expect(value).toMatchObject({
      OTP_MAX_ATTEMPTS_PER_CHALLENGE: 5,
      OTP_MAX_FAILED_ATTEMPTS: 5,
      OTP_FAILED_ATTEMPTS_WINDOW_SECONDS: 900,
      OTP_RESEND_COOLDOWN_SECONDS: 60,
      OTP_MAX_SENDS_PER_HOUR: 5,
      OTP_MAX_SENDS_PER_DAY: 10,
    });
  });

  it("never returns the code in production even if the flag slips through", async () => {
    const t = setup({ NODE_ENV: "production", OTP_DEV_MODE: true });
    const res = await t.service.requestPhoneOtp({ phone: PHONE });
    expect(res).not.toHaveProperty("devCode");
    expect(t.linkSyria.sendOtp).toHaveBeenCalledTimes(1);
  });

  it("still returns the code in development dev mode (no SMS)", async () => {
    const t = setup({ NODE_ENV: "development", OTP_DEV_MODE: true });
    const res = await t.service.requestPhoneOtp({ phone: PHONE });
    expect(res.devCode).toMatch(/^\d{6}$/);
    expect(t.linkSyria.sendOtp).not.toHaveBeenCalled();
  });
});
