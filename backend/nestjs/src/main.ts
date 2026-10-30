import { ValidationPipe } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { NestFactory } from "@nestjs/core";
import compression from "compression";
import { json, urlencoded } from "express";
import helmet from "helmet";
import { AppModule } from "./app.module";
import { ApiExceptionFilter } from "./common/api-exception.filter";

function parseCorsOrigins(value?: string): string[] {
  if (!value) return [];
  return value
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
}

async function bootstrap(): Promise<void> {
  // Nest's built-in body parser is disabled so the JSON limit can be raised:
  // store logos travel as base64 JSON (max ~300 KB decoded), above the 100 KB default.
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  app.use(json({ limit: "1mb" }));
  app.use(urlencoded({ extended: true }));
  const config = app.get(ConfigService);

  app.use(helmet());
  app.use(compression());
 app.enableCors({
origin: (
  origin: string | undefined,
  callback: (err: Error | null, allow?: boolean) => void,
) => {
    if (!origin) {
      callback(null, true);
      return;
    }

    const allowedOrigins = parseCorsOrigins(
      config.get<string>("CORS_ORIGINS"),
    );

    if (
      allowedOrigins.includes(origin) ||
      /^http:\/\/localhost:\d+$/.test(origin)
    ) {
      callback(null, true);
      return;
    }

    callback(new Error('Not allowed by CORS'), false);
  },
  credentials: true,
});
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );
  app.useGlobalFilters(new ApiExceptionFilter());

  const port = config.get<number>("PORT", 3000);
  await app.listen(port);
}

void bootstrap();
