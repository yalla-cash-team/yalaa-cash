import { Module } from "@nestjs/common";
import { AdminOffersController } from "./admin-offers.controller";
import { OffersService } from "./offers.service";
import { PublicOffersController } from "./public-offers.controller";

@Module({
  controllers: [AdminOffersController, PublicOffersController],
  providers: [OffersService],
})
export class OffersModule {}
