import { AuthMethod } from "@prisma/client";
import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { createHmac } from "crypto";
import {
  AuthService,
  legacyGovernorateOnCreate,
  legacyGovernorateUpdate,
} from "../src/auth/auth.service";
import { CustomerOAuthDto, VerifyPhoneOtpDto } from "../src/auth/dto/auth.dto";

/**
 * Customer sign-up no longer asks for a governorate: the customer picks an
 * active governorate (and city) after sign-in. The legacy free-text
 * `governorate` field stays optional so older Customer apps keep working.
 */

const PEPPER = "test-pepper";
const PHONE = "+963900000001";
const CODE = "123456";
const otpHash = (phone: string, code: string) =>
  createHmac("sha256", PEPPER).update(`${phone}:${code}`).digest("hex");

async function errorsFor<T extends object>(cls: new () => T, body: object) {
  return (await validate(plainToInstance(cls, body))).map((e) => e.property);
}

describe("registration DTOs: governorate is optional", () => {
  const phoneBody = {
    challengeId: "challenge-1",
    phone: PHONE,
    code: CODE,
    name: "Customer",
  };
  const oauthBody = {
    provider: AuthMethod.GOOGLE,
    firebaseIdToken: "x".repeat(40),
    name: "Customer",
  };

  it("accepts phone sign-up without governorate (new app)", async () => {
    expect(await errorsFor(VerifyPhoneOtpDto, phoneBody)).toEqual([]);
  });

  it("accepts phone sign-up with governorate (older app)", async () => {
    expect(
      await errorsFor(VerifyPhoneOtpDto, { ...phoneBody, governorate: "حلب" }),
    ).toEqual([]);
  });

  it("accepts OAuth sign-up with and without governorate", async () => {
    expect(await errorsFor(CustomerOAuthDto, oauthBody)).toEqual([]);
    expect(
      await errorsFor(CustomerOAuthDto, { ...oauthBody, governorate: "دمشق" }),
    ).toEqual([]);
  });

  it("still validates a governorate when one is sent", async () => {
    expect(
      await errorsFor(VerifyPhoneOtpDto, { ...phoneBody, governorate: "x" }),
    ).toContain("governorate");
    expect(
      await errorsFor(VerifyPhoneOtpDto, { ...phoneBody, governorate: 5 }),
    ).toContain("governorate");
  });

  it("keeps the other registration fields required", async () => {
    const { name: _name, ...noName } = phoneBody;
    expect(await errorsFor(VerifyPhoneOtpDto, noName)).toContain("name");
    const { code: _code, ...noCode } = phoneBody;
    expect(await errorsFor(VerifyPhoneOtpDto, noCode)).toContain("code");
  });
});

describe("legacy governorate helpers", () => {
  it("stores an omitted governorate as an empty string on create", () => {
    expect(legacyGovernorateOnCreate(undefined)).toBe("");
    expect(legacyGovernorateOnCreate("  حلب ")).toBe("حلب");
  });

  it("leaves an existing label untouched when omitted on update", () => {
    expect(legacyGovernorateUpdate(undefined)).toEqual({});
    expect(legacyGovernorateUpdate(" إدلب ")).toEqual({ governorate: "إدلب" });
  });
});

describe("AuthService customer registration", () => {
  function setup(challenge: Record<string, unknown> | null = {}) {
    const savedChallenge =
      challenge === null
        ? null
        : {
            id: "challenge-1",
            phone: PHONE,
            consumedAt: null,
            expiresAt: new Date(Date.now() + 60_000),
            attempts: 0,
            codeHash: otpHash(PHONE, CODE),
            ...challenge,
          };
    const tx = {
      user: {
        upsert: jest.fn().mockResolvedValue({ id: "user-1", role: "CUSTOMER" }),
      },
      customerProfile: { upsert: jest.fn().mockResolvedValue({}) },
      otpChallenge: { update: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      otpChallenge: {
        findUnique: jest.fn().mockResolvedValue(savedChallenge),
        update: jest.fn().mockResolvedValue({}),
      },
      user: {
        upsert: jest.fn().mockResolvedValue({ id: "user-2", role: "CUSTOMER" }),
      },
      $transaction: jest.fn((fn: (t: typeof tx) => unknown) => fn(tx)),
    };
    const config = {
      get: jest.fn((_key: string, fallback?: unknown) => fallback),
      getOrThrow: jest.fn(() => PEPPER),
    };
    const firebaseOAuth = {
      verifyCustomerToken: jest
        .fn()
        .mockResolvedValue({ subject: "sub-1", email: "a@b.c", phone: null }),
    };
    const service = new AuthService(
      prisma as never,
      config as never,
      {} as never,
      {} as never,
      firebaseOAuth as never,
      {} as never,
    );
    const tokens = { accessToken: "a", refreshToken: "r" };
    jest
      .spyOn(
        service as unknown as {
          issueAuthResponse: () => Promise<typeof tokens>;
        },
        "issueAuthResponse",
      )
      .mockResolvedValue(tokens);
    return { service, prisma, tx, tokens };
  }

  const verify = (extra: Partial<VerifyPhoneOtpDto> = {}) =>
    ({
      challengeId: "challenge-1",
      phone: PHONE,
      code: CODE,
      name: " Customer ",
      ...extra,
    }) as VerifyPhoneOtpDto;

  it("registers by phone without governorate and saves an empty string", async () => {
    const { service, tx, tokens } = setup();
    await expect(service.verifyPhoneOtp(verify())).resolves.toBe(tokens);

    const args = tx.customerProfile.upsert.mock.calls[0][0];
    expect(args.create).toEqual({
      userId: "user-1",
      name: "Customer",
      governorate: "",
    });
    // An existing customer signing in again keeps their saved label.
    expect(args.update).toEqual({ name: "Customer" });
    expect(args.update).not.toHaveProperty("governorate");
    expect(args.create).not.toHaveProperty("governorateId");
    expect(tx.otpChallenge.update).toHaveBeenCalled();
  });

  it("still accepts a governorate from an older app", async () => {
    const { service, tx } = setup();
    await service.verifyPhoneOtp(verify({ governorate: " حلب " }));

    const args = tx.customerProfile.upsert.mock.calls[0][0];
    expect(args.create.governorate).toBe("حلب");
    expect(args.update).toEqual({ name: "Customer", governorate: "حلب" });
  });

  it("keeps OTP checks unchanged: wrong code is rejected and counted", async () => {
    const { service, prisma, tx } = setup();
    await expect(
      service.verifyPhoneOtp(verify({ code: "000000" })),
    ).rejects.toThrow("OTP code is incorrect.");
    expect(prisma.otpChallenge.update).toHaveBeenCalledWith({
      where: { id: "challenge-1" },
      data: { attempts: { increment: 1 } },
    });
    expect(tx.customerProfile.upsert).not.toHaveBeenCalled();
  });

  it("keeps OTP checks unchanged: expired, consumed and missing challenges", async () => {
    await expect(
      setup({ expiresAt: new Date(Date.now() - 1) }).service.verifyPhoneOtp(
        verify(),
      ),
    ).rejects.toThrow("OTP challenge has expired.");
    await expect(
      setup({ consumedAt: new Date() }).service.verifyPhoneOtp(verify()),
    ).rejects.toThrow("OTP challenge is invalid.");
    await expect(
      setup(null).service.verifyPhoneOtp(verify()),
    ).rejects.toThrow("OTP challenge is invalid.");
    await expect(
      setup({ attempts: 5 }).service.verifyPhoneOtp(verify()),
    ).rejects.toThrow("Too many OTP attempts.");
  });

  it("registers by OAuth without governorate", async () => {
    const { service, prisma, tokens } = setup();
    const dto = {
      provider: AuthMethod.GOOGLE,
      firebaseIdToken: "x".repeat(40),
      name: "Customer",
    } as CustomerOAuthDto;
    await expect(service.verifyCustomerOAuth(dto)).resolves.toBe(tokens);

    const args = prisma.user.upsert.mock.calls[0][0];
    expect(args.create.customer.create).toEqual({
      name: "Customer",
      governorate: "",
    });
    expect(args.update.customer.upsert.create.governorate).toBe("");
    expect(args.update.customer.upsert.update).toEqual({ name: "Customer" });
  });

  it("registers by OAuth with a governorate from an older app", async () => {
    const { service, prisma } = setup();
    await service.verifyCustomerOAuth({
      provider: AuthMethod.GOOGLE,
      firebaseIdToken: "x".repeat(40),
      name: "Customer",
      governorate: "دمشق",
    } as CustomerOAuthDto);

    const args = prisma.user.upsert.mock.calls[0][0];
    expect(args.create.customer.create.governorate).toBe("دمشق");
    expect(args.update.customer.upsert.update.governorate).toBe("دمشق");
  });
});
