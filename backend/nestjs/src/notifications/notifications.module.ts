import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { CustomerNotificationService } from "./customer-notification.service";
import { CustomerNotificationsController } from "./customer-notifications.controller";
import { FcmService } from "./fcm.service";
import { NotificationBroadcastService } from "./notification-broadcast.service";

@Module({
  imports: [AuthModule],
  controllers: [CustomerNotificationsController],
  providers: [
    FcmService,
    NotificationBroadcastService,
    CustomerNotificationService,
  ],
  exports: [
    FcmService,
    NotificationBroadcastService,
    CustomerNotificationService,
  ],
})
export class NotificationsModule {}
