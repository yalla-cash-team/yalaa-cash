import { BadRequestException } from "@nestjs/common";
import {
  parseCompletedMonth,
  settleEachMerchant,
  summarizeOutcomes,
} from "../src/admin/monthly-settlement";

const NOW = new Date("2026-10-15T12:00:00.000Z");

describe("parseCompletedMonth", () => {
  it("returns the calendar bounds of a completed month", () => {
    const bounds = parseCompletedMonth("2026-09", NOW);
    expect(bounds.periodStart.toISOString()).toBe("2026-09-01T00:00:00.000Z");
    expect(bounds.periodEnd.toISOString()).toBe("2026-10-01T00:00:00.000Z");
  });

  it("handles leap-year February", () => {
    const bounds = parseCompletedMonth("2028-02", new Date("2028-03-02Z"));
    expect(bounds.periodEnd.toISOString()).toBe("2028-03-01T00:00:00.000Z");
  });

  it("rejects the current month and future months", () => {
    expect(() => parseCompletedMonth("2026-10", NOW)).toThrow(
      BadRequestException,
    );
    expect(() => parseCompletedMonth("2026-11", NOW)).toThrow(
      BadRequestException,
    );
  });

  it.each(["2026-9", "2026-13", "26-09", "2026/09", "", "2026-00"])(
    "rejects malformed month %s",
    (month) => {
      expect(() => parseCompletedMonth(month, NOW)).toThrow(
        BadRequestException,
      );
    },
  );
});

describe("settleEachMerchant", () => {
  const merchants = [
    { storeId: "a", storeName: "A", commissionDueSyp: 100 },
    { storeId: "b", storeName: "B", commissionDueSyp: 200 },
    { storeId: "c", storeName: "C", commissionDueSyp: 300 },
  ];

  it("keeps successful results when one merchant fails", async () => {
    const outcomes = await settleEachMerchant(merchants, async (m) => {
      if (m.storeId === "b") throw new Error("db timeout with secret detail");
      return "settled";
    });

    expect(outcomes.map((o) => o.status)).toEqual([
      "settled",
      "failed",
      "settled",
    ]);
    expect(outcomes[1].error).toBe("Settlement failed for this merchant.");
    expect(JSON.stringify(outcomes)).not.toContain("secret");
  });

  it("reports already-settled merchants as skipped, not failed", async () => {
    const outcomes = await settleEachMerchant(merchants, async (m) =>
      m.storeId === "a" ? "skipped" : "settled",
    );
    expect(summarizeOutcomes(outcomes)).toEqual({
      settledCount: 2,
      skippedCount: 1,
      failedCount: 0,
      totalCommissionSyp: 500,
    });
  });

  it("totals only the commission that was actually settled", async () => {
    const outcomes = await settleEachMerchant(merchants, async (m) => {
      if (m.storeId === "c") throw new Error("boom");
      return "settled";
    });
    const summary = summarizeOutcomes(outcomes);
    expect(summary.totalCommissionSyp).toBe(300);
    expect(summary.failedCount).toBe(1);
  });
});
