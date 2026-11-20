import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { AuthMethod, Prisma, User, UserRole } from "@prisma/client";
import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  timingSafeEqual,
} from "crypto";
import { PrismaService } from "../prisma/prisma.service";
import { presentCustomer } from "../common/presenters";
import {
  CustomerOAuthDto,
  OtpStartResponseDto,
  PasswordLoginDto,
  TokenPairResponseDto,
  VerifyPhoneOtpDto,
} from "./dto/auth.dto";
import { FirebaseOAuthService } from "./firebase-oauth.service";
import { LinkSyriaOtpService } from "./linksyria/linksyria-otp.service";
import { PasswordService } from "./password.service";
import { normalizePhone } from "./phone";

/// `CustomerProfile.governorate` is a legacy free-text label. New Customer
/// apps no longer send it (the customer picks an active governorate after
/// sign-in, which sets `governorateId`); older apps still do.
///
/// On create the column is required, so an omitted value is stored as "".
export function legacyGovernorateOnCreate(governorate?: string): string {
  return governorate?.trim() ?? "";
}

/// On update (an existing customer signing in again) an omitted value leaves
/// the saved label untouched; a value from an older app replaces it as before.
export function legacyGovernorateUpdate(governorate?: string): {
  governorate?: string;
} {
  return governorate === undefined ? {} : { governorate: governorate.trim() };
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly jwt: JwtService,
    private readonly passwords: PasswordService,
    private readonly firebaseOAuth: FirebaseOAuthService,
    private readonly linkSyria: LinkSyriaOtpService,
  ) {}

  async requestPhoneOtp(dto: { phone: string }): Promise<OtpStartResponseDto> {
    const phone = this.normalizePhone(dto.phone);
    const devMode = this.isOtpDevMode();
    const smsProviderReady = devMode || this.linkSyria.isConfigured();
    if (!smsProviderReady && this.isProduction()) {
      throw new ServiceUnavailableException("SMS provider is not configured.");
    }

    const code = this.generateOtpCode();
    const expiresInSeconds = this.config.get<number>("OTP_TTL_SECONDS", 300);
    const policy = this.otpPolicy();

    // Limits are checked and the challenge is created while holding the
    // per-phone lock, so concurrent requests cannot all pass the checks.
    const outcome = await this.prisma.$transaction(
      async (tx) => {
        await this.lockPhone(tx, phone);
        const now = Date.now();

        if (
          (await this.recentFailedAttempts(tx, phone, now, policy)) >=
          policy.maxFailedAttempts
        ) {
          return {
            limited: "Too many OTP attempts. Please try again later.",
            retryAfterSeconds: policy.failureWindowSeconds,
          } as const;
        }

        const last = await tx.otpChallenge.findFirst({
          where: { phone },
          orderBy: { createdAt: "desc" },
          select: { createdAt: true },
        });
        if (last && policy.resendCooldownSeconds > 0) {
          const elapsed = (now - last.createdAt.getTime()) / 1000;
          if (elapsed < policy.resendCooldownSeconds) {
            return {
              limited: "Please wait before requesting another code.",
              retryAfterSeconds: Math.ceil(
                policy.resendCooldownSeconds - elapsed,
              ),
            } as const;
          }
        }

        const sentLastHour = await tx.otpChallenge.count({
          where: { phone, createdAt: { gte: new Date(now - 3_600_000) } },
        });
        if (sentLastHour >= policy.maxSendsPerHour) {
          return {
            limited: "Too many codes requested. Please try again later.",
            retryAfterSeconds: 3600,
          } as const;
        }
        const sentLastDay = await tx.otpChallenge.count({
          where: { phone, createdAt: { gte: new Date(now - 86_400_000) } },
        });
        if (sentLastDay >= policy.maxSendsPerDay) {
          return {
            limited: "Too many codes requested. Please try again later.",
            retryAfterSeconds: 86400,
          } as const;
        }

        const challenge = await tx.otpChallenge.create({
          data: {
            phone,
            codeHash: this.hashOtp(phone, code),
            expiresAt: new Date(now + expiresInSeconds * 1000),
          },
        });
        return { challenge } as const;
      },
      this.phoneLockTxOptions(),
    );

    if ("limited" in outcome) {
      throw new HttpException(
        {
          message: outcome.limited,
          retryAfterSeconds: outcome.retryAfterSeconds,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    // OTP_DEV_MODE keeps returning the code directly in the response and
    // never sends a real SMS. It is never honoured in production.
    if (!devMode) {
      await this.linkSyria.sendOtp(phone, code);
    }

    return {
      challengeId: outcome.challenge.id,
      expiresInSeconds,
      ...(devMode ? { devCode: code } : {}),
    };
  }

  async verifyPhoneOtp(dto: VerifyPhoneOtpDto): Promise<TokenPairResponseDto> {
    const phone = this.normalizePhone(dto.phone);
    const policy = this.otpPolicy();

    // Everything runs under the per-phone lock: the failure count, the code
    // check and the attempt increment are atomic across concurrent requests
    // and across every challenge of this phone. Outcomes are returned (not
    // thrown) so a wrong-guess increment is committed.
    const outcome = await this.prisma.$transaction(
      async (tx) => {
        await this.lockPhone(tx, phone);
        const now = Date.now();

        const challenge = await tx.otpChallenge.findUnique({
          where: { id: dto.challengeId },
        });
        if (!challenge || challenge.phone !== phone || challenge.consumedAt) {
          return { error: "OTP challenge is invalid." } as const;
        }
        if (challenge.expiresAt.getTime() < now) {
          return { error: "OTP challenge has expired." } as const;
        }
        if (
          challenge.attempts >= policy.maxAttemptsPerChallenge ||
          (await this.recentFailedAttempts(tx, phone, now, policy)) >=
            policy.maxFailedAttempts
        ) {
          return { error: "Too many OTP attempts." } as const;
        }

        if (!this.otpMatches(challenge.codeHash, phone, dto.code)) {
          await tx.otpChallenge.update({
            where: { id: challenge.id },
            data: { attempts: { increment: 1 } },
          });
          return { error: "OTP code is incorrect." } as const;
        }

        const user = await this.completePhoneLogin(tx, phone, dto, challenge.id);
        return { user } as const;
      },
      this.phoneLockTxOptions(),
    );

    if ("error" in outcome) throw new UnauthorizedException(outcome.error);
    return this.issueAuthResponse(outcome.user);
  }

  private async completePhoneLogin(
    tx: Prisma.TransactionClient,
    phone: string,
    dto: VerifyPhoneOtpDto,
    challengeId: string,
  ): Promise<User> {
    const saved = await tx.user.upsert({
      where: { phone },
      update: {
        authMethod: AuthMethod.PHONE,
        isActive: true,
      },
      create: {
        role: UserRole.CUSTOMER,
        phone,
        authMethod: AuthMethod.PHONE,
      },
    });

    await tx.customerProfile.upsert({
      where: { userId: saved.id },
      update: {
        name: dto.name.trim(),
        ...legacyGovernorateUpdate(dto.governorate),
      },
      create: {
        userId: saved.id,
        name: dto.name.trim(),
        governorate: legacyGovernorateOnCreate(dto.governorate),
      },
    });

    const consumedAt = new Date();
    await tx.otpChallenge.update({
      where: { id: challengeId },
      data: { consumedAt, userId: saved.id },
    });
    // The phone owner proved possession: close every other open challenge
    // for this phone so stale codes cannot be guessed and earlier failed
    // attempts stop counting toward the lockout.
    await tx.otpChallenge.updateMany({
      where: { phone, consumedAt: null, id: { not: challengeId } },
      data: { consumedAt },
    });

    return saved;
  }

  async verifyCustomerOAuth(
    dto: CustomerOAuthDto,
  ): Promise<TokenPairResponseDto> {
    if (
      dto.provider !== AuthMethod.GOOGLE &&
      dto.provider !== AuthMethod.FACEBOOK
    ) {
      throw new BadRequestException("Unsupported OAuth provider.");
    }

    const identity = await this.firebaseOAuth.verifyCustomerToken(
      dto.provider as Extract<AuthMethod, "GOOGLE" | "FACEBOOK">,
      dto.firebaseIdToken,
    );

    const user = await this.prisma.user.upsert({
      where: {
        oauthProvider_oauthSubject: {
          oauthProvider: dto.provider,
          oauthSubject: identity.subject,
        },
      },
      update: {
        email: identity.email,
        phone: identity.phone,
        authMethod: dto.provider,
        isActive: true,
        customer: {
          upsert: {
            update: {
              name: dto.name.trim(),
              ...legacyGovernorateUpdate(dto.governorate),
            },
            create: {
              name: dto.name.trim(),
              governorate: legacyGovernorateOnCreate(dto.governorate),
            },
          },
        },
      },
      create: {
        role: UserRole.CUSTOMER,
        email: identity.email,
        phone: identity.phone,
        authMethod: dto.provider,
        oauthProvider: dto.provider,
        oauthSubject: identity.subject,
        customer: {
          create: {
            name: dto.name.trim(),
            governorate: legacyGovernorateOnCreate(dto.governorate),
          },
        },
      },
    });

    return this.issueAuthResponse(user);
  }

  async loginMerchant(dto: PasswordLoginDto): Promise<TokenPairResponseDto> {
    return this.loginPassword(dto, UserRole.MERCHANT);
  }

  async loginAdmin(dto: PasswordLoginDto): Promise<TokenPairResponseDto> {
    return this.loginPassword(dto, UserRole.ADMIN);
  }

  async refresh(refreshToken: string): Promise<TokenPairResponseDto> {
    const tokenHash = this.hashSecret(refreshToken, "refresh");
    const saved = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { user: true },
    });

    if (!saved || saved.revokedAt || saved.expiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException("Refresh token is invalid.");
    }

    await this.prisma.refreshToken.update({
      where: { id: saved.id },
      data: { revokedAt: new Date() },
    });
    return this.issueAuthResponse(saved.user);
  }

  async logout(refreshToken: string): Promise<{ success: true }> {
    const tokenHash = this.hashSecret(refreshToken, "refresh");
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { success: true };
  }

  async createMerchantPasswordHash(password: string): Promise<string> {
    return this.passwords.hash(password);
  }

  private async loginPassword(
    dto: PasswordLoginDto,
    role: Extract<UserRole, "MERCHANT" | "ADMIN">,
  ): Promise<TokenPairResponseDto> {
    const user = await this.prisma.user.findFirst({
      where: {
        email: dto.email.trim().toLowerCase(),
        role,
        isActive: true,
      },
    });

    if (!user?.passwordHash) {
      throw new UnauthorizedException("Email or password is incorrect.");
    }

    const valid = await this.passwords.verify(dto.password, user.passwordHash);
    if (!valid) {
      throw new UnauthorizedException("Email or password is incorrect.");
    }

    return this.issueAuthResponse(user);
  }

  private async issueAuthResponse(user: User): Promise<TokenPairResponseDto> {
    if (!user.isActive)
      throw new UnauthorizedException("User account is disabled.");

    const accessTtl = this.config.get<number>("JWT_ACCESS_TTL_SECONDS", 900);
    const refreshTtl = this.config.get<number>(
      "JWT_REFRESH_TTL_SECONDS",
      2592000,
    );
    const accessToken = await this.jwt.signAsync(
      { sub: user.id, role: user.role },
      { expiresIn: accessTtl },
    );
    const refreshToken = randomBytes(48).toString("base64url");

    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: this.hashSecret(refreshToken, "refresh"),
        expiresAt: new Date(Date.now() + refreshTtl * 1000),
      },
    });

    const customer =
      user.role === UserRole.CUSTOMER
        ? await this.prisma.customerProfile.findUnique({
            where: { userId: user.id },
            include: { user: true },
          })
        : null;

    return {
      tokenType: "Bearer",
      accessToken,
      refreshToken,
      expiresInSeconds: accessTtl,
      user: {
        id: user.id,
        role: user.role.toLowerCase(),
      },
      ...(customer ? { profile: presentCustomer(customer) } : {}),
    };
  }

  private normalizePhone(phone: string): string {
    return normalizePhone(phone);
  }

  private isProduction(): boolean {
    return this.config.get<string>("NODE_ENV") === "production";
  }

  /// Defense in depth: startup validation already rejects OTP_DEV_MODE in
  /// production, and the flag is ignored here as well.
  private isOtpDevMode(): boolean {
    return (
      !this.isProduction() && this.config.get<boolean>("OTP_DEV_MODE", false)
    );
  }

  private otpPolicy() {
    return {
      maxAttemptsPerChallenge: this.config.get<number>(
        "OTP_MAX_ATTEMPTS_PER_CHALLENGE",
        5,
      ),
      maxFailedAttempts: this.config.get<number>("OTP_MAX_FAILED_ATTEMPTS", 5),
      failureWindowSeconds: this.config.get<number>(
        "OTP_FAILED_ATTEMPTS_WINDOW_SECONDS",
        900,
      ),
      resendCooldownSeconds: this.config.get<number>(
        "OTP_RESEND_COOLDOWN_SECONDS",
        60,
      ),
      maxSendsPerHour: this.config.get<number>("OTP_MAX_SENDS_PER_HOUR", 5),
      maxSendsPerDay: this.config.get<number>("OTP_MAX_SENDS_PER_DAY", 10),
    };
  }

  /// Transaction-scoped Postgres advisory lock keyed by the normalized phone.
  /// It serializes start/verify for one phone and is released at commit.
  private async lockPhone(
    tx: Prisma.TransactionClient,
    phone: string,
  ): Promise<void> {
    await tx.$queryRaw`SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtext(${`otp:${phone}`}))`;
  }

  /// Read Committed is required: each statement after the lock must see the
  /// increments committed by the previous lock holder.
  private phoneLockTxOptions() {
    return {
      isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted,
      maxWait: 10_000,
      timeout: 15_000,
    };
  }

  /// Wrong guesses for this phone across all still-open challenges created
  /// within the window. Opening a new challenge never resets this count;
  /// only a successful verification (which closes open challenges) or the
  /// window passing does.
  private async recentFailedAttempts(
    tx: Prisma.TransactionClient,
    phone: string,
    now: number,
    policy: { failureWindowSeconds: number },
  ): Promise<number> {
    const result = await tx.otpChallenge.aggregate({
      where: {
        phone,
        consumedAt: null,
        createdAt: { gte: new Date(now - policy.failureWindowSeconds * 1000) },
      },
      _sum: { attempts: true },
    });
    return result._sum.attempts ?? 0;
  }

  private otpMatches(codeHash: string, phone: string, code: string): boolean {
    const expected = Buffer.from(this.hashOtp(phone, code), "hex");
    const actual = Buffer.from(codeHash, "hex");
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  }

  private generateOtpCode(): string {
    const length = this.config.get<number>("OTP_LENGTH", 6);
    const min = 10 ** (length - 1);
    const max = 10 ** length - 1;
    return randomInt(min, max).toString();
  }

  private hashOtp(phone: string, code: string): string {
    return createHmac("sha256", this.config.getOrThrow<string>("SECRET_PEPPER"))
      .update(`${phone}:${code}`)
      .digest("hex");
  }

  private hashSecret(value: string, namespace: string): string {
    return createHash("sha256")
      .update(
        `${namespace}:${value}:${this.config.getOrThrow<string>("SECRET_PEPPER")}`,
      )
      .digest("hex");
  }
}
