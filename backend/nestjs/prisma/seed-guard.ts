/// Safeguard against seeding a real database by accident.
///
/// The seed upserts demo stores and RESETS the admin and merchant passwords,
/// so it must only run against a local development database unless the
/// operator opts in explicitly:
///   - NODE_ENV=production is refused unless ALLOW_PRODUCTION_SEED=true.
///   - A non-local DATABASE_URL host is refused unless ALLOW_REMOTE_SEED=true.
///   - Outside a local database, SEED_ADMIN_PASSWORD and
///     SEED_MERCHANT_PASSWORD are mandatory (no built-in demo passwords).

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);

export class SeedRefusedError extends Error {}

export function isLocalDatabaseUrl(databaseUrl: string | undefined): boolean {
  if (!databaseUrl) return false;
  try {
    return LOCAL_HOSTS.has(new URL(databaseUrl).hostname.toLowerCase());
  } catch {
    return false;
  }
}

export function assertSeedAllowed(env: NodeJS.ProcessEnv): void {
  if (!env.DATABASE_URL) {
    throw new SeedRefusedError("DATABASE_URL is not set. Nothing was seeded.");
  }
  if (
    env.NODE_ENV === "production" &&
    env.ALLOW_PRODUCTION_SEED !== "true"
  ) {
    throw new SeedRefusedError(
      "Refusing to seed with NODE_ENV=production. Set ALLOW_PRODUCTION_SEED=true only if this is truly intended.",
    );
  }
  const local = isLocalDatabaseUrl(env.DATABASE_URL);
  if (!local && env.ALLOW_REMOTE_SEED !== "true") {
    throw new SeedRefusedError(
      "Refusing to seed a non-local database. Set ALLOW_REMOTE_SEED=true only if this is truly intended.",
    );
  }
  if (!local && (!env.SEED_ADMIN_PASSWORD || !env.SEED_MERCHANT_PASSWORD)) {
    throw new SeedRefusedError(
      "SEED_ADMIN_PASSWORD and SEED_MERCHANT_PASSWORD must be set when seeding a non-local database.",
    );
  }
}
