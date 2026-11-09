import {
  BadRequestException,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { AuthMethod, User, UserRole } from "@prisma/client";
import { createHash, createHmac, randomBytes, randomInt } from "crypto";
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
    const devMode = this.config.get<boolean>("OTP_DEV_MODE", false);
    const smsProviderReady = devMode || this.linkSyria.isConfigured();
    if (!smsProviderReady && this.config.get<string>("NODE_ENV") === "production") {
      throw new ServiceUnavailableException("SMS provider is not configured.");
    }

    const code = this.generateOtpCode();
    const expiresInSeconds = this.config.get<number>("OTP_TTL_SECONDS", 300);
    const challenge = await this.prisma.otpChallenge.create({
      data: {
        phone,
        codeHash: this.hashOtp(phone, code),
        expiresAt: new Date(Date.now() + expiresInSeconds * 1000),
      },
    });

    // OTP_DEV_MODE keeps returning the code directly in the response and
    // never sends a real SMS, exactly as before LinkSyria was integrated.
    if (!devMode) {
      await this.linkSyria.sendOtp(phone, code);
    }

    return {
      challengeId: challenge.id,
      expiresInSeconds,
      ...(devMode ? { devCode: code } : {}),
    };
  }

  async verifyPhoneOtp(dto: VerifyPhoneOtpDto): Promise<TokenPairResponseDto> {
    const phone = this.normalizePhone(dto.phone);
    const challenge = await this.prisma.otpChallenge.findUnique({
      where: { id: dto.challengeId },
    });

    if (!challenge || challenge.phone !== phone || challenge.consumedAt) {
      throw new UnauthorizedException("OTP challenge is invalid.");
    }
    if (challenge.expiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException("OTP challenge has expired.");
    }
    if (challenge.attempts >= 5) {
      throw new UnauthorizedException("Too many OTP attempts.");
    }

    const expected = this.hashOtp(phone, dto.code);
    if (challenge.codeHash !== expected) {
      await this.prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });
      throw new UnauthorizedException("OTP code is incorrect.");
    }

    const user = await this.prisma.$transaction(async (tx) => {
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

      await tx.otpChallenge.update({
        where: { id: challenge.id },
        data: { consumedAt: new Date(), userId: saved.id },
      });

      return saved;
    });

    return this.issueAuthResponse(user);
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
    const normalized = phone.replace(/[^\d+]/g, "");
    if (normalized.length < 8) {
      throw new BadRequestException("Phone number is invalid.");
    }
    return normalized;
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
