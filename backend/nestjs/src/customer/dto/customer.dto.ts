import {
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
} from "class-validator";

export class UpdateCustomerProfileDto {
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(40)
  governorate!: string;

  @IsOptional()
  @IsString()
  @MinLength(8)
  @MaxLength(20)
  phone?: string;
}

export class UpdateCustomerGovernorateDto {
  @IsString()
  governorateId!: string;
}

export class UpdateCustomerCityDto {
  @IsUUID()
  cityId!: string;
}

export class RequestCashRedemptionDto {
  @IsInt()
  @Min(1)
  @Max(1000000000)
  points!: number;
}

export class RedeemDigitalProductDto {
  @IsString()
  productId!: string;

  @IsOptional()
  @IsString()
  @MinLength(8)
  @MaxLength(20)
  phoneNumber?: string;
}

export class RegisterDeviceTokenDto {
  @IsString()
  @MinLength(16)
  @MaxLength(4096)
  token!: string;
}
