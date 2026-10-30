import { BadRequestException } from "@nestjs/common";
import { LoyaltyCalculator } from "../src/loyalty/loyalty-calculator";

describe("LoyaltyCalculator", () => {
  it("splits commission and converts the customer share into points", () => {
    const result = LoyaltyCalculator.calculate({
      invoiceAmountSyp: 100000,
      commissionRate: 10,
      pointValueSyp: 5,
    });

    expect(result.commissionAmountSyp).toBe(10000);
    expect(result.customerShareSyp).toBe(5000);
    expect(result.platformRevenueSyp).toBe(5000);
    expect(result.customerPoints).toBe(1000);
  });

  it("rejects invalid invoice amounts", () => {
    expect(() =>
      LoyaltyCalculator.calculate({
        invoiceAmountSyp: 0,
        commissionRate: 6.7,
        pointValueSyp: 5,
      }),
    ).toThrow(BadRequestException);
  });

  it.each([
    ["0.10", 50000],
    ["0.25", 20000],
    ["0.50", 10000],
  ])("awards more points for fractional point value %s", (value, points) => {
    const result = LoyaltyCalculator.calculate({
      invoiceAmountSyp: 100000,
      commissionRate: 10,
      pointValueSyp: value,
    });

    expect(result.customerShareSyp).toBe(5000);
    expect(result.customerPoints).toBe(points);
    expect(result.pointValueSyp.toFixed(2)).toBe(value);
  });

  it("keeps integer point values working", () => {
    const result = LoyaltyCalculator.calculate({
      invoiceAmountSyp: 100000,
      commissionRate: 10,
      pointValueSyp: 5,
    });

    expect(result.customerPoints).toBe(1000);
  });

  it("rounds customer points down to whole points", () => {
    // Customer share is 5 SYP.
    const base = {
      invoiceAmountSyp: 100,
      commissionRate: 10,
    };

    expect(
      LoyaltyCalculator.calculate({ ...base, pointValueSyp: "0.4" })
        .customerPoints,
    ).toBe(12); // 12.5 -> 12
    expect(
      LoyaltyCalculator.calculate({ ...base, pointValueSyp: "0.3" })
        .customerPoints,
    ).toBe(16); // 16.67 -> 16
    expect(
      LoyaltyCalculator.calculate({ ...base, pointValueSyp: "0.25" })
        .customerPoints,
    ).toBe(20);
  });

  it("reports the non-divisible remainder for 0.30 SYP per point", () => {
    // 5 SYP share at 0.30 SYP/point: 16 points cover 4.8 SYP, 0.2 SYP remains.
    const result = LoyaltyCalculator.calculate({
      invoiceAmountSyp: 100,
      commissionRate: 10,
      pointValueSyp: "0.3",
    });

    expect(result.customerPoints).toBe(16);
    expect(result.customerRemainderSyp.toNumber()).toBeCloseTo(0.2, 4);
  });

  it("carries remainders forward so repeated rewards lose no value", () => {
    // Five 1-SYP rewards at 0.30 SYP/point: 5 SYP is worth 16 points, not 15.
    let carried = "0";
    let totalPoints = 0;
    for (let i = 0; i < 5; i++) {
      const result = LoyaltyCalculator.calculate({
        invoiceAmountSyp: 20,
        commissionRate: 10,
        pointValueSyp: "0.3",
        carriedRemainderSyp: carried,
      });
      totalPoints += result.customerPoints;
      carried = result.customerRemainderSyp.toString();
    }

    expect(totalPoints).toBe(16);
    expect(Number(carried)).toBeCloseTo(0.2, 4);
  });

  it("rejects an invalid carried remainder", () => {
    expect(() =>
      LoyaltyCalculator.calculate({
        invoiceAmountSyp: 100,
        commissionRate: 10,
        pointValueSyp: "0.3",
        carriedRemainderSyp: "0.3",
      }),
    ).toThrow(BadRequestException);
  });

  it("identifies point amounts that convert to whole SYP", () => {
    expect(LoyaltyCalculator.isWholeCashValue(10, "0.1")).toBe(true);
    expect(LoyaltyCalculator.isWholeCashValue(16, "0.3")).toBe(false);
    expect(LoyaltyCalculator.isWholeCashValue(20, "0.25")).toBe(true);
  });

  it("never awards points worth more than the customer share", () => {
    const values = ["0.1", "0.25", "0.3", "0.4", "0.5", "0.7", "3", "5"];
    const invoices = [1, 7, 13, 99, 101, 1000, 12345];

    for (const value of values) {
      for (const invoiceAmountSyp of invoices) {
        const result = LoyaltyCalculator.calculate({
          invoiceAmountSyp,
          commissionRate: 10,
          pointValueSyp: value,
        });

        const remainder = result.customerRemainderSyp.toNumber();
        expect(remainder).toBeGreaterThanOrEqual(0);
        expect(remainder).toBeLessThan(Number(value));
      }
    }
  });

  it("computes exact decimal division without float drift", () => {
    // Share 3 SYP at 0.1 SYP/point must be exactly 30 points.
    const result = LoyaltyCalculator.calculate({
      invoiceAmountSyp: 60,
      commissionRate: 10,
      pointValueSyp: "0.1",
    });

    expect(result.customerShareSyp).toBe(3);
    expect(result.customerPoints).toBe(30);
  });

  it("converts points back to whole SYP rounding down", () => {
    expect(LoyaltyCalculator.cashValueFor(17, "0.3")).toBe(5); // 5.1 -> 5
    expect(LoyaltyCalculator.cashValueFor(16, "0.3")).toBe(4); // 4.8 -> 4
    expect(LoyaltyCalculator.cashValueFor(1, "0.5")).toBe(0); // 0.5 -> 0
    expect(LoyaltyCalculator.cashValueFor(20, "0.25")).toBe(5);
    expect(LoyaltyCalculator.cashValueFor(1000, 5)).toBe(5000);
  });

  it.each([
    ["zero", "0"],
    ["negative", "-0.5"],
    ["more than four decimals", "0.00001"],
    ["not a number", "abc"],
    ["infinite", Number.POSITIVE_INFINITY],
  ])("rejects point value that is %s", (_label, value) => {
    expect(() =>
      LoyaltyCalculator.calculate({
        invoiceAmountSyp: 100000,
        commissionRate: 10,
        pointValueSyp: value,
      }),
    ).toThrow(BadRequestException);
  });
});
