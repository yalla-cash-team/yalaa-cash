import { AuthMethod } from "@prisma/client";
import {
  IsEmail,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Length,
  MaxLength,
  MinLength,
} from "class-validator";

export class RequestPhoneOtpDto {
  @IsString()
  @MinLength(8)
  @MaxLength(20)
  phone!: string;
}

export class VerifyPhoneOtpDto {
  @IsString()
  challengeId!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(20)
  phone!: string;

  @IsString()
  @Length(4, 8)
  code!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name!: string;

  /// Legacy free-text governorate sent by older Customer apps. Newer apps
  /// omit it: the customer picks an active governorate after sign-in.
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(40)
  governorate?: string;
}

export class CustomerOAuthDto {
  @IsEnum(AuthMethod)
  provider!: AuthMethod;

  @IsString()
  @MinLength(20)
  firebaseIdToken!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name!: string;

  /// Legacy free-text governorate; optional (see VerifyPhoneOtpDto).
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(40)
  governorate?: string;
}

export class PasswordLoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(6)
  @MaxLength(128)
  password!: string;
}

export class RefreshTokenDto {
  @IsString()
  @MinLength(32)
  refreshToken!: string;
}

export class LogoutDto {
  @IsString()
  @MinLength(32)
  refreshToken!: string;
}

export class OtpStartResponseDto {
  challengeId!: string;
  expiresInSeconds!: number;
  devCode?: string;
}

export class TokenPairResponseDto {
  tokenType!: "Bearer";
  accessToken!: string;
  refreshToken!: string;
  expiresInSeconds!: number;
  user!: {
    id: string;
    role: string;
  };
  profile?: unknown;
}

export class RegisterMerchantDeviceDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  fingerprint!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(80)
  label!: string;
}

export class DevOtpConfigDto {
  @IsOptional()
  @IsInt()
  length?: number;
}
