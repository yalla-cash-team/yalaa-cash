import Joi from "joi";

/// Environment schema validated at startup (ConfigModule.forRoot).
///
/// OTP_DEV_MODE returns the OTP code in the API response, so it must never be
/// enabled in production: the app refuses to start with that combination.
export const envValidationSchema = Joi.object({
  NODE_ENV: Joi.string()
    .valid("development", "test", "production")
    .default("development"),
  PORT: Joi.number().default(3000),
  DATABASE_URL: Joi.string()
    .uri({ scheme: ["postgresql", "postgres"] })
    .required(),
  CORS_ORIGINS: Joi.string().allow("").default(""),
  JWT_ACCESS_SECRET: Joi.string().min(32).required(),
  JWT_REFRESH_SECRET: Joi.string().min(32).required(),
  JWT_ACCESS_TTL_SECONDS: Joi.number().integer().positive().default(900),
  JWT_REFRESH_TTL_SECONDS: Joi.number().integer().positive().default(2592000),
  QR_TOKEN_SECRET: Joi.string().min(32).required(),
  QR_TOKEN_TTL_SECONDS: Joi.number().integer().positive().default(120),
  SECRET_PEPPER: Joi.string().min(16).required(),
  OTP_DEV_MODE: Joi.boolean()
    .truthy("true")
    .falsy("false")
    .default(false)
    .when("NODE_ENV", {
      is: "production",
      then: Joi.valid(false).messages({
        "any.only": "OTP_DEV_MODE must not be enabled when NODE_ENV=production.",
      }),
    }),
  OTP_TTL_SECONDS: Joi.number().integer().positive().default(300),
  OTP_LENGTH: Joi.number().integer().min(4).max(8).default(6),
  // Wrong guesses allowed on a single challenge.
  OTP_MAX_ATTEMPTS_PER_CHALLENGE: Joi.number().integer().min(1).default(5),
  // Wrong guesses allowed per phone across all of its challenges within the
  // window. A new OTP request never resets this count.
  OTP_MAX_FAILED_ATTEMPTS: Joi.number().integer().min(1).default(5),
  OTP_FAILED_ATTEMPTS_WINDOW_SECONDS: Joi.number()
    .integer()
    .positive()
    .default(900),
  // SMS send limits per phone.
  OTP_RESEND_COOLDOWN_SECONDS: Joi.number().integer().min(0).default(60),
  OTP_MAX_SENDS_PER_HOUR: Joi.number().integer().min(1).default(5),
  OTP_MAX_SENDS_PER_DAY: Joi.number().integer().min(1).default(10),
  FIREBASE_PROJECT_ID: Joi.string().allow("").optional(),
  FIREBASE_CLIENT_EMAIL: Joi.string().allow("").optional(),
  FIREBASE_PRIVATE_KEY: Joi.string().allow("").optional(),
  LINKSYRIA_API_URL: Joi.string()
    .uri({ scheme: ["http", "https"] })
    .default("https://linksyria.online"),
  LINKSYRIA_API_KEY: Joi.string().allow("").optional(),
  LINKSYRIA_TIMEOUT_MS: Joi.number().integer().positive().default(10000),
});
