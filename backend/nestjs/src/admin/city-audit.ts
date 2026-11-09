import { cityNameKey, normalizeCityName } from "./city-names";

/**
 * Read-only consistency audit of stores against the City hierarchy. Works
 * before the City migration (cityId absent, `cities` empty: uses the free-text
 * Store.city) and after it. It only reports; it never merges, renames or
 * writes anything.
 */
export type AuditStore = {
  id: string;
  name: string;
  category: string;
  city: string;
  cityId?: string | null;
  governorateId: string;
  isActive: boolean;
  displayOrder?: number | null;
};
export type AuditCity = {
  id: string;
  governorateId: string;
  nameAr: string;
  isActive: boolean;
};

export type AuditSeverity = "blocker" | "manual" | "warning";
export type AuditFinding = {
  code: string;
  severity: AuditSeverity;
  message: string;
  storeIds: string[];
  details?: Record<string, unknown>;
};
export type AuditReport = {
  mode: "pre-migration" | "post-migration";
  totals: { stores: number; activeStores: number; cities: number };
  findings: AuditFinding[];
  /** True when nothing blocks the release (manual items may still exist). */
  releaseSafe: boolean;
};

export function auditStores(
  stores: AuditStore[],
  cities: AuditCity[],
  hasCityTable: boolean,
): AuditReport {
  const findings: AuditFinding[] = [];
  const cityById = new Map(cities.map((c) => [c.id, c]));
  const add = (f: AuditFinding) => findings.push(f);

  // Stores that no city-filtered customer would ever see.
  for (const s of stores) {
    const blank = normalizeCityName(s.city ?? "") === "";
    const missing = hasCityTable ? !s.cityId : blank;
    if (!missing) continue;
    add({
      code: "STORE_WITHOUT_CITY",
      severity: s.isActive ? "blocker" : "warning",
      message: `${s.isActive ? "Active" : "Inactive"} store "${s.name}" has no ${
        hasCityTable ? "cityId" : "city name"
      }; it would be hidden from city-filtered customers until an admin assigns a city.`,
      storeIds: [s.id],
    });
  }

  // Spelling variants of one city inside a governorate (never auto-merged).
  const spellings = new Map<string, Map<string, string[]>>(); // gov|key -> name -> ids
  const record = (gov: string, name: string, id: string) => {
    const n = normalizeCityName(name);
    if (!n) return;
    const k = `${gov}|${cityNameKey(n)}`;
    const byName = spellings.get(k) ?? new Map<string, string[]>();
    byName.set(n, [...(byName.get(n) ?? []), id]);
    spellings.set(k, byName);
  };
  if (hasCityTable) {
    for (const c of cities) record(c.governorateId, c.nameAr, c.id);
  } else {
    for (const s of stores) record(s.governorateId, s.city ?? "", s.id);
  }
  for (const [k, byName] of spellings) {
    if (byName.size < 2) continue;
    const names = [...byName.keys()];
    const ids = [...byName.values()].flat();
    add({
      code: "CITY_SPELLING_VARIANTS",
      severity: "manual",
      message: `Governorate ${k.split("|")[0]} has spelling variants of one city: ${names
        .map((n) => `"${n}"`)
        .join(", ")}. Decide manually which to keep, then move the stores.`,
      storeIds: hasCityTable
        ? stores.filter((s) => s.cityId && ids.includes(s.cityId)).map((s) => s.id)
        : ids,
      details: { names },
    });
  }

  if (hasCityTable) {
    for (const s of stores) {
      if (!s.cityId) continue;
      const city = cityById.get(s.cityId);
      if (!city) {
        add({
          code: "STORE_CITY_NOT_FOUND",
          severity: "blocker",
          message: `Store "${s.name}" points to a missing city.`,
          storeIds: [s.id],
        });
        continue;
      }
      if (city.governorateId !== s.governorateId) {
        add({
          code: "CITY_GOVERNORATE_MISMATCH",
          severity: "blocker",
          message: `Store "${s.name}" is in a different governorate than its city "${city.nameAr}".`,
          storeIds: [s.id],
        });
      }
      if (s.isActive && !city.isActive) {
        add({
          code: "ACTIVE_STORE_IN_INACTIVE_CITY",
          severity: "blocker",
          message: `Active store "${s.name}" is in the inactive city "${city.nameAr}".`,
          storeIds: [s.id],
        });
      }
      if (normalizeCityName(s.city ?? "") !== city.nameAr) {
        add({
          code: "STORE_CITY_TEXT_MISMATCH",
          severity: "warning",
          message: `Store "${s.name}" city text "${s.city}" differs from its city "${city.nameAr}".`,
          storeIds: [s.id],
        });
      }
    }
  }

  // One active store per city and category.
  const slots = new Map<string, AuditStore[]>();
  for (const s of stores.filter((x) => x.isActive)) {
    if (hasCityTable && !s.cityId) continue; // reported as STORE_WITHOUT_CITY
    const scope = hasCityTable
      ? s.cityId
      : `${s.governorateId}|${cityNameKey(s.city ?? "")}`;
    const k = `${scope}|${s.category.trim().toLowerCase()}`;
    slots.set(k, [...(slots.get(k) ?? []), s]);
  }
  for (const group of slots.values()) {
    if (group.length < 2) continue;
    add({
      code: "EXCLUSIVITY_CONFLICT",
      severity: "blocker",
      message: `${group.length} active stores share city and category "${group[0].category}": ${group
        .map((s) => `"${s.name}"`)
        .join(", ")}.`,
      storeIds: group.map((s) => s.id),
    });
  }

  // Display order must be exactly 1..n among a city's active stores.
  if (hasCityTable) {
    const byCity = new Map<string, AuditStore[]>();
    for (const s of stores.filter((x) => x.isActive && x.cityId)) {
      byCity.set(s.cityId!, [...(byCity.get(s.cityId!) ?? []), s]);
    }
    for (const [cityId, group] of byCity) {
      const positions = group.map((s) => s.displayOrder ?? 0).sort((a, b) => a - b);
      if (!positions.every((p, i) => p === i + 1)) {
        add({
          code: "DISPLAY_ORDER_INVALID",
          severity: "warning",
          message: `City "${cityById.get(cityId)?.nameAr ?? cityId}" has positions [${positions.join(
            ", ",
          )}] instead of 1..${group.length}; saving any store in it renumbers them.`,
          storeIds: group.map((s) => s.id),
        });
      }
    }
  }

  return {
    mode: hasCityTable ? "post-migration" : "pre-migration",
    totals: {
      stores: stores.length,
      activeStores: stores.filter((s) => s.isActive).length,
      cities: cities.length,
    },
    findings,
    releaseSafe: !findings.some((f) => f.severity === "blocker"),
  };
}

export function formatAuditReport(report: AuditReport): string {
  const lines = [
    `City audit (${report.mode}): ${report.totals.stores} stores ` +
      `(${report.totals.activeStores} active), ${report.totals.cities} cities`,
  ];
  for (const sev of ["blocker", "manual", "warning"] as const) {
    const items = report.findings.filter((f) => f.severity === sev);
    if (!items.length) continue;
    lines.push("", `${sev.toUpperCase()} (${items.length})`);
    for (const f of items) {
      lines.push(`  [${f.code}] ${f.message}`);
      if (f.storeIds.length) lines.push(`      stores: ${f.storeIds.join(", ")}`);
    }
  }
  lines.push(
    "",
    report.releaseSafe
      ? "No blockers. Manual/warning items above still need a human decision."
      : "BLOCKERS found: fix these before releasing the city-filtered customer app.",
  );
  return lines.join("\n");
}
