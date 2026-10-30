import { Prisma } from "@prisma/client";
import {
  convertPointBalance,
  monetaryBalanceSyp,
} from "../src/loyalty/point-conversion";

const D = (value: string) => new Prisma.Decimal(value);

describe("convertPointBalance", () => {
  it("converts 5 -> 0.10 SYP per point and multiplies the points", () => {
    const next = convertPointBalance(
      { points: BigInt(1000), remainderSyp: D("0") },
      D("5"),
      D("0.1"),
    );
    expect(next.points).toBe(BigInt(50000));
    expect(next.remainderSyp.toString()).toBe("0");
  });

  it("converts 0.10 -> 5 SYP per point and divides the points", () => {
    const next = convertPointBalance(
      { points: BigInt(50000), remainderSyp: D("0") },
      D("0.1"),
      D("5"),
    );
    expect(next.points).toBe(BigInt(1000));
    expect(next.remainderSyp.toString()).toBe("0");
  });

  it("regression: 16 points + 0.2 SYP at 0.30 becomes 1 point at 5 SYP", () => {
    const next = convertPointBalance(
      { points: BigInt(16), remainderSyp: D("0.2") },
      D("0.3"),
      D("5"),
    );
    expect(next.points).toBe(BigInt(1));
    expect(next.remainderSyp.toString()).toBe("0");
  });

  it("keeps the exact monetary balance when the division leaves a remainder", () => {
    const before = { points: BigInt(1000), remainderSyp: D("0") };
    const next = convertPointBalance(before, D("5"), D("0.3"));

    expect(next.points).toBe(BigInt(16666));
    expect(next.remainderSyp.toString()).toBe("0.2");
    expect(
      monetaryBalanceSyp(next, D("0.3")).equals(
        monetaryBalanceSyp(before, D("5")),
      ),
    ).toBe(true);
  });

  it("keeps the balance exact through repeated changes", () => {
    let state = { points: BigInt(1000), remainderSyp: D("0") };
    const original = monetaryBalanceSyp(state, D("5"));
    const values = ["0.3", "0.25", "0.1", "7", "0.3", "5"];
    let current = D("5");

    for (const value of values) {
      const target = D(value);
      state = convertPointBalance(state, current, target);
      current = target;
      expect(monetaryBalanceSyp(state, current).equals(original)).toBe(true);
      expect(state.remainderSyp.lt(current)).toBe(true);
    }

    expect(state.points).toBe(BigInt(1000));
    expect(state.remainderSyp.toString()).toBe("0");
  });

  it("handles zero balances", () => {
    const next = convertPointBalance(
      { points: BigInt(0), remainderSyp: D("0") },
      D("5"),
      D("0.1"),
    );
    expect(next.points).toBe(BigInt(0));
    expect(next.remainderSyp.toString()).toBe("0");
  });

  it("keeps a fractional-only remainder when no whole point fits", () => {
    const next = convertPointBalance(
      { points: BigInt(0), remainderSyp: D("0.25") },
      D("0.5"),
      D("5"),
    );
    expect(next.points).toBe(BigInt(0));
    expect(next.remainderSyp.toString()).toBe("0.25");
  });

  it("is a no-op when the value does not change", () => {
    // The remainder is always below one point's value (0.1 here).
    const state = { points: BigInt(77), remainderSyp: D("0.04") };
    const next = convertPointBalance(state, D("0.1"), D("0.1"));
    expect(next.points).toBe(BigInt(77));
    expect(next.remainderSyp.toString()).toBe("0.04");
  });
});
