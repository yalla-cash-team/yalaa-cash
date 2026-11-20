import {
  assertSeedAllowed,
  isLocalDatabaseUrl,
  SeedRefusedError,
} from "../prisma/seed-guard";

/**
 * Regression tests for the audit lead auth-seed-default-credentials: the
 * seed (which resets staff passwords) must not run against a production or
 * remote database by accident, and never with built-in demo passwords there.
 */

const LOCAL = "postgresql://u:p@localhost:5432/yalla_cash";
const REMOTE = "postgresql://u:p@db.example-host.net:5432/yalla_cash";

describe("seed guard", () => {
  it("allows a local development database with demo defaults", () => {
    expect(() => assertSeedAllowed({ DATABASE_URL: LOCAL })).not.toThrow();
    expect(() =>
      assertSeedAllowed({ DATABASE_URL: "postgresql://u:p@127.0.0.1/db" }),
    ).not.toThrow();
  });

  it("refuses when DATABASE_URL is missing", () => {
    expect(() => assertSeedAllowed({})).toThrow(SeedRefusedError);
  });

  it("refuses NODE_ENV=production without explicit opt-in, even on localhost", () => {
    expect(() =>
      assertSeedAllowed({ DATABASE_URL: LOCAL, NODE_ENV: "production" }),
    ).toThrow(/NODE_ENV=production/);
  });

  it("refuses a remote database without explicit opt-in", () => {
    expect(() => assertSeedAllowed({ DATABASE_URL: REMOTE })).toThrow(/non-local/);
  });

  it("requires explicit passwords for a remote database even when opted in", () => {
    expect(() =>
      assertSeedAllowed({ DATABASE_URL: REMOTE, ALLOW_REMOTE_SEED: "true" }),
    ).toThrow(/SEED_ADMIN_PASSWORD/);
    expect(() =>
      assertSeedAllowed({
        DATABASE_URL: REMOTE,
        ALLOW_REMOTE_SEED: "true",
        SEED_ADMIN_PASSWORD: "x".repeat(20),
        SEED_MERCHANT_PASSWORD: "y".repeat(20),
      }),
    ).not.toThrow();
  });

  it("requires both opt-ins for a production remote database", () => {
    const env = {
      DATABASE_URL: REMOTE,
      NODE_ENV: "production",
      ALLOW_REMOTE_SEED: "true",
      SEED_ADMIN_PASSWORD: "x".repeat(20),
      SEED_MERCHANT_PASSWORD: "y".repeat(20),
    };
    expect(() => assertSeedAllowed(env)).toThrow(/NODE_ENV=production/);
    expect(() =>
      assertSeedAllowed({ ...env, ALLOW_PRODUCTION_SEED: "true" }),
    ).not.toThrow();
  });

  it("treats malformed URLs as non-local", () => {
    expect(isLocalDatabaseUrl("not a url")).toBe(false);
    expect(isLocalDatabaseUrl(undefined)).toBe(false);
  });
});
