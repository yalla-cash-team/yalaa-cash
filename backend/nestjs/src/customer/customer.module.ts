import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { NotificationsModule } from "../notifications/notifications.module";
import { CustomerController } from "./customer.controller";
import { CustomerService } from "./customer.service";
import { ProductImageController } from "./product-image.controller";
import { BannerImageController } from "./banner-image.controller";

@Module({
  imports: [AuthModule, NotificationsModule],
  controllers: [CustomerController, ProductImageController, BannerImageController],
  providers: [CustomerService],
  exports: [CustomerService],
})
export class CustomerModule {}
