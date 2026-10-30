import { BadRequestException } from "@nestjs/common";
import { Prisma } from "@prisma/client";

const MAX_POINT_VALUE_DECIMALS = 4;

export interface LoyaltyCalculationInput {
  invoiceAmountSyp: number;
  commissionRate: number;
  pointValueSyp: Prisma.Decimal | number | string;
  /// Remainder left over from earlier rewards for the same customer.
  carriedRemainderSyp?: Prisma.Decimal | number | string;
}

export interface LoyaltyCalculationResult {
  invoiceAmountSyp: number;
  commissionRate: number;
  commissionAmountSyp: number;
  platformRevenueSyp: number;
  customerShareSyp: number;
  customerPoints: number;
  pointValueSyp: Prisma.Decimal;
  /// Earned SYP still not covered by whole points; stored for the next reward.
  customerRemainderSyp: Prisma.Decimal;
}

export class LoyaltyCalculator {
  static calculate(input: LoyaltyCalculationInput): LoyaltyCalculationResult {
    if (
      !Number.isInteger(input.invoiceAmountSyp) ||
      input.invoiceAmountSyp <= 0
    ) {
      throw new BadRequestException(
        "Invoice amount must be a positive integer.",
      );
    }
    if (input.commissionRate < 0 || input.commissionRate > 100) {
      throw new BadRequestException(
        "Commission rate must be between 0 and 100.",
      );
    }
    const pointValueSyp = LoyaltyCalculator.parsePointValue(input.pointValueSyp);

    const commissionAmountSyp = Math.round(
      (input.invoiceAmountSyp * input.commissionRate) / 100,
    );
    const customerShareSyp = Math.round(commissionAmountSyp / 2);
    const platformRevenueSyp = commissionAmountSyp - customerShareSyp;
    const carriedRemainderSyp = new Prisma.Decimal(
      input.carriedRemainderSyp ?? 0,
    );
    if (carriedRemainderSyp.isNegative() || carriedRemainderSyp.gte(pointValueSyp)) {
      throw new BadRequestException("Carried point remainder is invalid.");
    }

    // Points are rounded down so awarded points never exceed the reward.
    // The leftover fraction is carried forward instead of being discarded.
    const earnedSyp = new Prisma.Decimal(customerShareSyp).plus(
      carriedRemainderSyp,
    );
    const customerPoints = LoyaltyCalculator.roundDown(
      earnedSyp.div(pointValueSyp),
    );
    const customerRemainderSyp = earnedSyp.minus(
      pointValueSyp.mul(customerPoints),
    );

    return {
      invoiceAmountSyp: input.invoiceAmountSyp,
      commissionRate: input.commissionRate,
      commissionAmountSyp,
      platformRevenueSyp,
      customerShareSyp,
      customerPoints,
      pointValueSyp,
      customerRemainderSyp,
    };
  }

  /// True when `points` convert to an exact whole-SYP amount, so a cash
  /// redemption never has to discard a fraction.
  static isWholeCashValue(
    points: number,
    pointValueSyp: Prisma.Decimal | number | string,
  ): boolean {
    const value = LoyaltyCalculator.parsePointValue(pointValueSyp);
    return value.mul(points).isInteger();
  }

  /// SYP value of `points`, rounded down to a whole SYP amount.
  static cashValueFor(
    points: number,
    pointValueSyp: Prisma.Decimal | number | string,
  ): number {
    const value = LoyaltyCalculator.parsePointValue(pointValueSyp);
    return LoyaltyCalculator.roundDown(value.mul(points));
  }

  static parsePointValue(
    input: Prisma.Decimal | number | string,
  ): Prisma.Decimal {
    if (typeof input === "number" && !Number.isFinite(input)) {
      throw new BadRequestException("Point value must be a positive number.");
    }
    let value: Prisma.Decimal;
    try {
      value = new Prisma.Decimal(input);
    } catch {
      throw new BadRequestException("Point value must be a positive number.");
    }
    if (
      !value.isFinite() ||
      value.lte(0) ||
      value.decimalPlaces() > MAX_POINT_VALUE_DECIMALS
    ) {
      throw new BadRequestException(
        `Point value must be positive with at most ${MAX_POINT_VALUE_DECIMALS} decimal places.`,
      );
    }
    return value;
  }

  private static roundDown(value: Prisma.Decimal): number {
    return value.toDecimalPlaces(0, Prisma.Decimal.ROUND_DOWN).toNumber();
  }
}
