import { BadRequestException } from "@nestjs/common";

/**
 * Offer validity dates: the ONE place that turns admin calendar dates into
 * stored instants and back. Everything else (service, presenters, tests)
 * goes through these helpers.
 *
 * Contract
 * --------
 * - The business time zone is Asia/Damascus. Its UTC offset is NOT assumed
 *   to be fixed: Syria used daylight saving time (switching at local
 *   midnight) until 2022, and the zone rules may change again. Offsets are
 *   resolved with the runtime's built-in time zone database (Intl/ICU).
 * - Admins send calendar dates as "YYYY-MM-DD" strings (never browser-local
 *   timestamps):
 *     startDate = first day the offer is available (inclusive)
 *     endDate   = last day the offer is available (inclusive)
 *   Either may be omitted/null for an open-ended window.
 * - The database stores UTC instants:
 *     startsAt   = start of startDate in Damascus (normally 00:00 local)
 *     endsBefore = start of the day AFTER endDate in Damascus (EXCLUSIVE)
 *   so the whole last day is included without end-of-day precision issues.
 * - An offer window is open at `now` when
 *     (startsAt == null || startsAt <= now) && (endsBefore == null || now < endsBefore)
 * - endDate == startDate (a one-day offer) is allowed; endDate < startDate is
 *   rejected. The database's StoreOffer_window_check (endsBefore > startsAt)
 *   enforces the same rule as a last line of defence.
 */

export const BUSINESS_TIME_ZONE = "Asia/Damascus";

/// Calendar dates outside this range are rejected as unreasonable input.
export const MIN_OFFER_YEAR = 2000;
export const MAX_OFFER_YEAR = 2100;

const CALENDAR_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const DAY_MS = 24 * 60 * 60 * 1000;

export interface CalendarDate {
  year: number;
  month: number; // 1-12
  day: number; // 1-31
}

interface ZonedDateTime extends CalendarDate {
  hour: number;
  minute: number;
  second: number;
}

const businessFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: BUSINESS_TIME_ZONE,
  year: "numeric",
  month: "numeric",
  day: "numeric",
  hour: "numeric",
  minute: "numeric",
  second: "numeric",
  hourCycle: "h23",
});

/// Parses a strict "YYYY-MM-DD" calendar date; null if malformed or if the
/// day does not exist (e.g. 2026-02-30, 2026-13-01, 2025-02-29).
export function parseCalendarDate(value: string): CalendarDate | null {
  const match = CALENDAR_DATE_PATTERN.exec(value);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < MIN_OFFER_YEAR || year > MAX_OFFER_YEAR) return null;
  if (month < 1 || month > 12 || day < 1) return null;
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  if (day > daysInMonth) return null;
  return { year, month, day };
}

export function formatCalendarDate(date: CalendarDate): string {
  const pad = (n: number, width: number) => String(n).padStart(width, "0");
  return `${pad(date.year, 4)}-${pad(date.month, 2)}-${pad(date.day, 2)}`;
}

function addDays(date: CalendarDate, days: number): CalendarDate {
  const shifted = new Date(Date.UTC(date.year, date.month - 1, date.day + days));
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

function zonedDateTime(instantMs: number): ZonedDateTime {
  const parts: Record<string, number> = {};
  for (const part of businessFormatter.formatToParts(new Date(instantMs))) {
    if (part.type !== "literal") parts[part.type] = Number(part.value);
  }
  return {
    year: parts.year,
    month: parts.month,
    day: parts.day,
    hour: parts.hour,
    minute: parts.minute,
    second: parts.second,
  };
}

/// The business zone's UTC offset (ms) in effect at [instantMs].
function offsetAt(instantMs: number): number {
  const wholeSecond = Math.floor(instantMs / 1000) * 1000;
  const local = zonedDateTime(wholeSecond);
  const localAsUtc = Date.UTC(
    local.year,
    local.month - 1,
    local.day,
    local.hour,
    local.minute,
    local.second,
  );
  return localAsUtc - wholeSecond;
}

function sameDate(a: CalendarDate, b: CalendarDate): boolean {
  return a.year === b.year && a.month === b.month && a.day === b.day;
}

/// The first instant of [date] in Asia/Damascus. Normally 00:00 local; on a
/// day whose midnight is skipped by a clock change it is the transition
/// instant (the first moment the local calendar shows [date]).
export function startOfBusinessDay(date: CalendarDate): Date {
  const wallClockMidnight = Date.UTC(date.year, date.month - 1, date.day);
  // Any offset that could apply around that midnight: the one before, at and
  // after it. Each gives a candidate instant; the earliest one that falls on
  // [date] locally is the start of the day.
  const candidates = new Set(
    [-DAY_MS, 0, DAY_MS].map(
      (probe) => wallClockMidnight - offsetAt(wallClockMidnight + probe),
    ),
  );
  let start: number | undefined;
  for (const candidate of candidates) {
    if (!sameDate(zonedDateTime(candidate), date)) continue;
    if (start === undefined || candidate < start) start = candidate;
  }
  if (start === undefined) {
    throw new Error(
      `Could not resolve the start of ${formatCalendarDate(date)} in ${BUSINESS_TIME_ZONE}.`,
    );
  }
  return new Date(start);
}

/// The Asia/Damascus calendar date that contains [instant].
export function businessDateOf(instant: Date): string {
  return formatCalendarDate(zonedDateTime(instant.getTime()));
}

/// Stored startsAt for an inclusive first day.
export function offerStartsAt(firstDay: CalendarDate): Date {
  return startOfBusinessDay(firstDay);
}

/// Stored (exclusive) endsBefore for an inclusive last day.
export function offerEndsBefore(lastDay: CalendarDate): Date {
  return startOfBusinessDay(addDays(lastDay, 1));
}

/// Inverse of offerStartsAt: the inclusive first day, for API responses.
export function startDateOf(startsAt: Date | null): string | null {
  return startsAt ? businessDateOf(startsAt) : null;
}

/// Inverse of offerEndsBefore: the inclusive last day, for API responses.
export function endDateOf(endsBefore: Date | null): string | null {
  return endsBefore ? businessDateOf(new Date(endsBefore.getTime() - 1)) : null;
}

export interface OfferWindow {
  startsAt: Date | null;
  endsBefore: Date | null;
}

/// Calendar-date input from a create/update request:
///   undefined = keep the current value, null = clear it, string = set it.
export interface OfferDateInput {
  startDate?: string | null;
  endDate?: string | null;
}

function parseOrReject(value: string, field: string): CalendarDate {
  const date = parseCalendarDate(value);
  if (!date) {
    throw new BadRequestException(
      `${field} must be a real calendar date in YYYY-MM-DD format between ${MIN_OFFER_YEAR} and ${MAX_OFFER_YEAR}.`,
    );
  }
  return date;
}

/// Combines [input] with the [current] stored window (all-null for a new
/// offer) and validates the FINAL window, so a partial update that changes
/// only one boundary is still checked against the other stored boundary.
export function resolveOfferWindow(
  current: OfferWindow,
  input: OfferDateInput,
): OfferWindow {
  const startsAt =
    input.startDate === undefined
      ? current.startsAt
      : input.startDate === null
        ? null
        : offerStartsAt(parseOrReject(input.startDate, "startDate"));
  const endsBefore =
    input.endDate === undefined
      ? current.endsBefore
      : input.endDate === null
        ? null
        : offerEndsBefore(parseOrReject(input.endDate, "endDate"));

  if (startsAt && endsBefore && endsBefore.getTime() <= startsAt.getTime()) {
    throw new BadRequestException(
      "The offer's end date must be on or after its start date.",
    );
  }
  return { startsAt, endsBefore };
}

/// startsAt <= now < endsBefore, with null meaning "unbounded".
export function isWithinOfferWindow(window: OfferWindow, now: Date): boolean {
  const t = now.getTime();
  if (window.startsAt && window.startsAt.getTime() > t) return false;
  if (window.endsBefore && t >= window.endsBefore.getTime()) return false;
  return true;
}

export type OfferStatus = "inactive" | "scheduled" | "active" | "expired";

/// Admin-facing status. "inactive" (switched off) wins over the date window.
export function offerStatus(
  offer: OfferWindow & { isActive: boolean },
  now: Date,
): OfferStatus {
  if (!offer.isActive) return "inactive";
  if (offer.startsAt && offer.startsAt.getTime() > now.getTime()) {
    return "scheduled";
  }
  if (offer.endsBefore && now.getTime() >= offer.endsBefore.getTime()) {
    return "expired";
  }
  return "active";
}
