import { Prisma } from "@prisma/client";

export interface PointBalanceState {
  points: bigint;
  remainderSyp: Prisma.Decimal;
}

/// Exact SYP value held by a customer: whole points at the old value plus the
/// fractional remainder. All arithmetic is Decimal, so nothing drifts.
export function monetaryBalanceSyp(
  state: PointBalanceState,
  pointValueSyp: Prisma.Decimal,
): Prisma.Decimal {
  return new Prisma.Decimal(state.points.toString())
    .mul(pointValueSyp)
    .plus(state.remainderSyp);
}

/// Re-expresses the same monetary balance in whole points at the new value.
/// Points round down, and the leftover stays in remainderSyp, so
/// points * newValue + remainder always equals the original balance.
export function convertPointBalance(
  state: PointBalanceState,
  oldValue: Prisma.Decimal,
  newValue: Prisma.Decimal,
): PointBalanceState {
  const total = monetaryBalanceSyp(state, oldValue);
  const points = total
    .div(newValue)
    .toDecimalPlaces(0, Prisma.Decimal.ROUND_DOWN);
  return {
    points: BigInt(points.toFixed(0)),
    remainderSyp: total.minus(points.mul(newValue)),
  };
}
