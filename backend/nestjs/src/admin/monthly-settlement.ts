import { BadRequestException } from "@nestjs/common";

export const MONTH_PATTERN = /^(\d{4})-(0[1-9]|1[0-2])$/;

export interface MonthBounds {
  monthKey: string;
  periodStart: Date;
  periodEnd: Date;
}

/// Calendar month (UTC, 1st to last day) that must already be complete.
/// The current or a future month is never settled.
export function parseCompletedMonth(month: string, now: Date): MonthBounds {
  const match = MONTH_PATTERN.exec(month);
  if (!match) {
    throw new BadRequestException("Month must be in YYYY-MM format.");
  }
  const year = Number(match[1]);
  const monthIndex = Number(match[2]) - 1;
  const periodStart = new Date(Date.UTC(year, monthIndex, 1));
  const periodEnd = new Date(Date.UTC(year, monthIndex + 1, 1));
  if (periodEnd.getTime() > now.getTime()) {
    throw new BadRequestException("Only completed months can be settled.");
  }
  return { monthKey: month, periodStart, periodEnd };
}

export type MerchantOutcomeStatus = "settled" | "skipped" | "failed";

export interface MerchantOutcome {
  storeId: string;
  storeName: string;
  status: MerchantOutcomeStatus;
  commissionDueSyp: number;
  error?: string;
}

export interface MerchantCandidate {
  storeId: string;
  storeName: string;
  commissionDueSyp: number;
}

/// Settles each merchant on its own. A failure is recorded for that merchant
/// only: results already committed for other merchants are kept.
export async function settleEachMerchant<T extends MerchantCandidate>(
  merchants: T[],
  settleOne: (merchant: T) => Promise<"settled" | "skipped">,
): Promise<MerchantOutcome[]> {
  const outcomes: MerchantOutcome[] = [];
  for (const merchant of merchants) {
    const base = {
      storeId: merchant.storeId,
      storeName: merchant.storeName,
      commissionDueSyp: merchant.commissionDueSyp,
    };
    try {
      outcomes.push({ ...base, status: await settleOne(merchant) });
    } catch {
      // Only a generic message: the underlying error may contain data.
      outcomes.push({
        ...base,
        status: "failed",
        error: "Settlement failed for this merchant.",
      });
    }
  }
  return outcomes;
}

export function summarizeOutcomes(outcomes: MerchantOutcome[]) {
  return {
    settledCount: outcomes.filter((o) => o.status === "settled").length,
    skippedCount: outcomes.filter((o) => o.status === "skipped").length,
    failedCount: outcomes.filter((o) => o.status === "failed").length,
    totalCommissionSyp: outcomes
      .filter((o) => o.status === "settled")
      .reduce((sum, o) => sum + o.commissionDueSyp, 0),
  };
}
