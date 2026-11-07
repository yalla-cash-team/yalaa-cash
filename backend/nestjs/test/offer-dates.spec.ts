import { BadRequestException } from "@nestjs/common";
import {
  businessDateOf,
  endDateOf,
  isWithinOfferWindow,
  offerEndsBefore,
  offerStartsAt,
  offerStatus,
  parseCalendarDate,
  resolveOfferWindow,
  startDateOf,
} from "../src/offers/offer-dates";

/**
 * Offer validity dates are Asia/Damascus calendar days:
 *   startsAt   = start of the first day (inclusive)
 *   endsBefore = start of the day after the last day (exclusive)
 * The offset is resolved from the time zone database, never assumed.
 */

const day = (value: string) => {
  const parsed = parseCalendarDate(value);
  if (!parsed) throw new Error(`bad test date ${value}`);
  return parsed;
};
const iso = (d: Date) => d.toISOString();
const HOUR = 60 * 60 * 1000;

describe("parseCalendarDate", () => {
  it.each(["2026-11-05", "2024-02-29", "2028-02-29", "2026-12-31", "2026-01-01"])(
    "accepts the real date %s",
    (value) => {
      expect(parseCalendarDate(value)).not.toBeNull();
    },
  );

  it.each([
    ["2026-02-30", "February 30th"],
    ["2026-02-29", "Feb 29th in a non-leap year"],
    ["2100-02-29", "Feb 29th in a century non-leap year"],
    ["2026-04-31", "April 31st"],
    ["2026-13-01", "month 13"],
    ["2026-00-10", "month 0"],
    ["2026-01-00", "day 0"],
    ["2026-1-05", "unpadded month"],
    ["26-01-05", "two-digit year"],
    ["2026-01-05T00:00:00Z", "a timestamp"],
    ["2026-01-05 ", "trailing space"],
    ["2026/01/05", "slashes"],
    ["", "empty"],
    ["1999-12-31", "before 2000"],
    ["2101-01-01", "after 2100"],
  ])("rejects %s (%s)", (value) => {
    expect(parseCalendarDate(value)).toBeNull();
  });
});

describe("Damascus day boundaries (current rules, UTC+3 all year)", () => {
  it("starts a day at 00:00 Damascus and ends it at 00:00 of the next day", () => {
    expect(iso(offerStartsAt(day("2026-11-05")))).toBe("2026-11-04T21:00:00.000Z");
    expect(iso(offerEndsBefore(day("2026-11-05")))).toBe("2026-11-05T21:00:00.000Z");
  });

  it("rolls over months, years and leap days", () => {
    expect(iso(offerEndsBefore(day("2026-01-31")))).toBe("2026-01-31T21:00:00.000Z");
    expect(iso(offerEndsBefore(day("2026-12-31")))).toBe("2026-12-31T21:00:00.000Z");
    expect(businessDateOf(offerEndsBefore(day("2026-12-31")))).toBe("2027-01-01");
    expect(businessDateOf(offerEndsBefore(day("2028-02-28")))).toBe("2028-02-29");
    expect(businessDateOf(offerEndsBefore(day("2026-02-28")))).toBe("2026-03-01");
    expect(businessDateOf(offerStartsAt(day("2028-02-29")))).toBe("2028-02-29");
  });

  it("does not depend on the server's local time zone", () => {
    // Pure UTC arithmetic plus an explicit Asia/Damascus formatter.
    const before = iso(offerStartsAt(day("2026-06-15")));
    expect(before).toBe("2026-06-14T21:00:00.000Z");
  });
});

describe("Damascus day boundaries (historical DST: offset is not fixed)", () => {
  // Until 2022 Syria used UTC+2 in winter and UTC+3 in summer, switching at
  // local midnight.
  it("uses UTC+2 in a winter and UTC+3 in a summer of the DST era", () => {
    expect(iso(offerStartsAt(day("2021-01-15")))).toBe("2021-01-14T22:00:00.000Z");
    expect(iso(offerStartsAt(day("2021-07-01")))).toBe("2021-06-30T21:00:00.000Z");
  });

  it("starts a day whose midnight was skipped at the first instant of that day", () => {
    // 2021-03-26: clocks jumped from 00:00 (+2) to 01:00 (+3).
    expect(iso(offerStartsAt(day("2021-03-26")))).toBe("2021-03-25T22:00:00.000Z");
    expect(businessDateOf(new Date("2021-03-25T22:00:00.000Z"))).toBe("2021-03-26");
    expect(businessDateOf(new Date("2021-03-25T21:59:59.999Z"))).toBe("2021-03-25");
    // That day was 23 hours long.
    const length =
      offerEndsBefore(day("2021-03-26")).getTime() -
      offerStartsAt(day("2021-03-26")).getTime();
    expect(length).toBe(23 * HOUR);
  });

  it("handles the autumn change (a 25-hour day)", () => {
    // 2021-10-29 00:00 (+3) fell back to 2021-10-28 23:00 (+2).
    expect(iso(offerStartsAt(day("2021-10-28")))).toBe("2021-10-27T21:00:00.000Z");
    expect(iso(offerStartsAt(day("2021-10-29")))).toBe("2021-10-28T22:00:00.000Z");
    const length =
      offerEndsBefore(day("2021-10-28")).getTime() -
      offerStartsAt(day("2021-10-28")).getTime();
    expect(length).toBe(25 * HOUR);
  });

  it("round-trips every day of a DST year and of the current rules", () => {
    for (const year of [2021, 2026, 2028]) {
      for (let t = Date.UTC(year, 0, 1); t < Date.UTC(year + 1, 0, 1); t += 24 * HOUR) {
        const value = new Date(t).toISOString().slice(0, 10);
        const date = day(value);
        expect(startDateOf(offerStartsAt(date))).toBe(value);
        expect(endDateOf(offerEndsBefore(date))).toBe(value);
        // Consecutive days tile time with no gap or overlap.
        expect(offerEndsBefore(date).getTime()).toBe(
          offerStartsAt(day(new Date(t + 24 * HOUR).toISOString().slice(0, 10))).getTime(),
        );
      }
    }
  });
});

describe("startDateOf / endDateOf", () => {
  it("returns null for open-ended boundaries", () => {
    expect(startDateOf(null)).toBeNull();
    expect(endDateOf(null)).toBeNull();
  });

  it("reports the inclusive last day for the exclusive endsBefore", () => {
    expect(endDateOf(new Date("2026-11-05T21:00:00.000Z"))).toBe("2026-11-05");
  });
});

describe("resolveOfferWindow", () => {
  const none = { startsAt: null, endsBefore: null };

  it("stores both boundaries for a new range", () => {
    const window = resolveOfferWindow(none, {
      startDate: "2026-11-01",
      endDate: "2026-11-30",
    });
    expect(iso(window.startsAt!)).toBe("2026-10-31T21:00:00.000Z");
    expect(iso(window.endsBefore!)).toBe("2026-11-30T21:00:00.000Z");
  });

  it("allows a one-day offer (start date == end date)", () => {
    const window = resolveOfferWindow(none, {
      startDate: "2026-11-05",
      endDate: "2026-11-05",
    });
    expect(window.endsBefore!.getTime() - window.startsAt!.getTime()).toBe(24 * HOUR);
  });

  it("rejects a reversed range", () => {
    expect(() =>
      resolveOfferWindow(none, { startDate: "2026-11-06", endDate: "2026-11-05" }),
    ).toThrow(BadRequestException);
  });

  it.each(["2026-02-30", "2026-13-01", "1999-01-01"])(
    "rejects the impossible date %s",
    (value) => {
      expect(() => resolveOfferWindow(none, { startDate: value })).toThrow(
        BadRequestException,
      );
      expect(() => resolveOfferWindow(none, { endDate: value })).toThrow(
        BadRequestException,
      );
    },
  );

  it("allows open-ended windows", () => {
    expect(resolveOfferWindow(none, {})).toEqual(none);
    expect(resolveOfferWindow(none, { startDate: null, endDate: null })).toEqual(none);
    expect(resolveOfferWindow(none, { endDate: "2026-11-05" }).startsAt).toBeNull();
  });

  describe("partial updates against the stored window", () => {
    const stored = resolveOfferWindow(none, {
      startDate: "2026-11-10",
      endDate: "2026-11-20",
    });

    it("keeps the untouched boundary (undefined = unchanged)", () => {
      const window = resolveOfferWindow(stored, { endDate: "2026-11-25" });
      expect(window.startsAt).toBe(stored.startsAt);
      expect(endDateOf(window.endsBefore)).toBe("2026-11-25");
    });

    it("rejects a new end date before the stored start date", () => {
      expect(() => resolveOfferWindow(stored, { endDate: "2026-11-09" })).toThrow(
        "The offer's end date must be on or after its start date.",
      );
    });

    it("rejects a new start date after the stored end date", () => {
      expect(() => resolveOfferWindow(stored, { startDate: "2026-11-21" })).toThrow(
        BadRequestException,
      );
    });

    it("accepts moving both boundaries together even if each alone would be invalid", () => {
      const window = resolveOfferWindow(stored, {
        startDate: "2026-12-01",
        endDate: "2026-12-05",
      });
      expect(startDateOf(window.startsAt)).toBe("2026-12-01");
      expect(endDateOf(window.endsBefore)).toBe("2026-12-05");
    });

    it("clears a boundary with explicit null", () => {
      const window = resolveOfferWindow(stored, { endDate: null });
      expect(window.startsAt).toBe(stored.startsAt);
      expect(window.endsBefore).toBeNull();
      expect(resolveOfferWindow(stored, { startDate: null }).startsAt).toBeNull();
    });
  });
});

describe("isWithinOfferWindow / offerStatus", () => {
  const window = resolveOfferWindow(
    { startsAt: null, endsBefore: null },
    { startDate: "2026-11-05", endDate: "2026-11-05" },
  );
  const at = (s: string) => new Date(s);

  it("is inclusive at startsAt and exclusive at endsBefore", () => {
    expect(isWithinOfferWindow(window, at("2026-11-04T20:59:59.999Z"))).toBe(false);
    expect(isWithinOfferWindow(window, at("2026-11-04T21:00:00.000Z"))).toBe(true);
    // 23:59:59.999 Damascus on the last day is still inside.
    expect(isWithinOfferWindow(window, at("2026-11-05T20:59:59.999Z"))).toBe(true);
    // 00:00 Damascus on the next day is outside.
    expect(isWithinOfferWindow(window, at("2026-11-05T21:00:00.000Z"))).toBe(false);
  });

  it("treats null boundaries as unbounded", () => {
    const always = { startsAt: null, endsBefore: null };
    expect(isWithinOfferWindow(always, at("1990-01-01T00:00:00Z"))).toBe(true);
    expect(isWithinOfferWindow(always, at("2090-01-01T00:00:00Z"))).toBe(true);
  });

  it("reports inactive, scheduled, active and expired", () => {
    const now = at("2026-11-05T12:00:00Z");
    expect(offerStatus({ ...window, isActive: false }, now)).toBe("inactive");
    expect(offerStatus({ ...window, isActive: true }, now)).toBe("active");
    expect(
      offerStatus({ ...window, isActive: true }, at("2026-11-04T20:00:00Z")),
    ).toBe("scheduled");
    expect(
      offerStatus({ ...window, isActive: true }, at("2026-11-05T21:00:00Z")),
    ).toBe("expired");
  });
});
