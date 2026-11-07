import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { APP_GUARD } from "@nestjs/core";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import Joi from "joi";
import { AdminModule } from "./admin/admin.module";
import { AuthModule } from "./auth/auth.module";
import { JwtAuthGuard } from "./auth/guards/jwt-auth.guard";
import { RolesGuard } from "./auth/guards/roles.guard";
import { CustomerModule } from "./customer/customer.module";
import { MerchantModule } from "./merchant/merchant.module";
import { OffersModule } from "./offers/offers.module";
import { PrismaModule } from "./prisma/prisma.module";
import { StoresModule } from "./stores/stores.module";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validationSchema: Joi.object({
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
        JWT_REFRESH_TTL_SECONDS: Joi.number()
          .integer()
          .positive()
          .default(2592000),
        QR_TOKEN_SECRET: Joi.string().min(32).required(),
        QR_TOKEN_TTL_SECONDS: Joi.number().integer().positive().default(120),
        SECRET_PEPPER: Joi.string().min(16).required(),
        OTP_DEV_MODE: Joi.boolean()
          .truthy("true")
          .falsy("false")
          .default(false),
        OTP_TTL_SECONDS: Joi.number().integer().positive().default(300),
        OTP_LENGTH: Joi.number().integer().min(4).max(8).default(6),
        FIREBASE_PROJECT_ID: Joi.string().allow("").optional(),
        FIREBASE_CLIENT_EMAIL: Joi.string().allow("").optional(),
        FIREBASE_PRIVATE_KEY: Joi.string().allow("").optional(),
        LINKSYRIA_API_URL: Joi.string()
          .uri({ scheme: ["http", "https"] })
          .default("https://linksyria.online"),
        LINKSYRIA_API_KEY: Joi.string().allow("").optional(),
        LINKSYRIA_TIMEOUT_MS: Joi.number().integer().positive().default(10000),
      }),
    }),
    PrismaModule,
    ThrottlerModule.forRoot([
      {
        name: "default",
        ttl: 60000,
        limit: 120,
      },
    ]),
    AuthModule,
    StoresModule,
    CustomerModule,
    MerchantModule,
    AdminModule,
    OffersModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
  ],
})
export class AppModule {}
