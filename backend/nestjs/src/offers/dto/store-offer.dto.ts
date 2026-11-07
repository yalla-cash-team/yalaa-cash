import { Transform } from "class-transformer";
import {
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
} from "class-validator";

/**
 * Request bodies for the admin offer endpoints. The global ValidationPipe
 * runs with whitelist + forbidNonWhitelisted, so any other field (storeId,
 * city, category, isExclusive, imageVersion, ...) is rejected with 400:
 * offer endpoints can never change the parent store.
 *
 * Dates are calendar dates ("YYYY-MM-DD", Asia/Damascus), see offer-dates.ts.
 */

export const OFFER_TITLE_MIN_LENGTH = 2;
export const OFFER_TITLE_MAX_LENGTH = 120;
export const OFFER_DESCRIPTION_MAX_LENGTH = 1000;
export const OFFER_DISCOUNT_LABEL_MAX_LENGTH = 60;
export const OFFER_DISPLAY_ORDER_MIN = 0;
export const OFFER_DISPLAY_ORDER_MAX = 9999;

const CALENDAR_DATE_SHAPE = /^\d{4}-\d{2}-\d{2}$/;
const CALENDAR_DATE_MESSAGE = (field: string) =>
  `${field} must be a calendar date in YYYY-MM-DD format.`;

const trim = ({ value }: { value: unknown }) =>
  typeof value === "string" ? value.trim() : value;

/// Applies the following validators only when the field is present, so a
/// non-nullable field sent as null fails validation instead of being skipped.
const IfPresent = () => ValidateIf((_object, value) => value !== undefined);

export class CreateStoreOfferDto {
  @Transform(trim)
  @IsString()
  @MinLength(OFFER_TITLE_MIN_LENGTH)
  @MaxLength(OFFER_TITLE_MAX_LENGTH)
  title!: string;

  /// Omitted or null = empty description.
  @IsOptional()
  @Transform(trim)
  @IsString()
  @MaxLength(OFFER_DESCRIPTION_MAX_LENGTH)
  description?: string | null;

  /// Free-text display label, e.g. "خصم 20%". Omitted, null or blank = none.
  @IsOptional()
  @Transform(trim)
  @IsString()
  @MaxLength(OFFER_DISCOUNT_LABEL_MAX_LENGTH)
  discountLabel?: string | null;

  /// First available day (inclusive). Omitted or null = available immediately.
  @IsOptional()
  @IsString()
  @Matches(CALENDAR_DATE_SHAPE, { message: CALENDAR_DATE_MESSAGE("startDate") })
  startDate?: string | null;

  /// Last available day (inclusive). Omitted or null = no end.
  @IsOptional()
  @IsString()
  @Matches(CALENDAR_DATE_SHAPE, { message: CALENDAR_DATE_MESSAGE("endDate") })
  endDate?: string | null;

  /// Defaults to true.
  @IfPresent()
  @IsBoolean()
  isActive?: boolean;

  /// Lower shows first. Defaults to 0.
  @IfPresent()
  @IsInt()
  @Min(OFFER_DISPLAY_ORDER_MIN)
  @Max(OFFER_DISPLAY_ORDER_MAX)
  displayOrder?: number;
}

/**
 * Partial update. Each field is optional:
 *   absent      -> unchanged
 *   null        -> cleared (description, discountLabel, startDate, endDate only)
 *   a value     -> set
 * Date order is validated against the final combined window.
 */
export class UpdateStoreOfferDto {
  @IfPresent()
  @Transform(trim)
  @IsString()
  @MinLength(OFFER_TITLE_MIN_LENGTH)
  @MaxLength(OFFER_TITLE_MAX_LENGTH)
  title?: string;

  @IsOptional()
  @Transform(trim)
  @IsString()
  @MaxLength(OFFER_DESCRIPTION_MAX_LENGTH)
  description?: string | null;

  @IsOptional()
  @Transform(trim)
  @IsString()
  @MaxLength(OFFER_DISCOUNT_LABEL_MAX_LENGTH)
  discountLabel?: string | null;

  @IsOptional()
  @IsString()
  @Matches(CALENDAR_DATE_SHAPE, { message: CALENDAR_DATE_MESSAGE("startDate") })
  startDate?: string | null;

  @IsOptional()
  @IsString()
  @Matches(CALENDAR_DATE_SHAPE, { message: CALENDAR_DATE_MESSAGE("endDate") })
  endDate?: string | null;

  @IfPresent()
  @IsBoolean()
  isActive?: boolean;

  @IfPresent()
  @IsInt()
  @Min(OFFER_DISPLAY_ORDER_MIN)
  @Max(OFFER_DISPLAY_ORDER_MAX)
  displayOrder?: number;
}

/// Same shape as the store logo upload: a base64 image in JSON.
/// PNG, JPEG or WebP only, at most 300 KB decoded (see offer-image.ts).
export class UploadOfferImageDto {
  @IsString()
  @MaxLength(40)
  contentType!: string;

  // 300 KB of bytes is ~409,600 base64 characters; the decoded size is
  // checked exactly in decodeOfferImage.
  @IsString()
  @MaxLength(420000)
  dataBase64!: string;
}
