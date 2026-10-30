import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { FcmService } from "./fcm.service";
import { NotificationBroadcastService } from "./notification-broadcast.service";

@Module({
  imports: [AuthModule],
  providers: [FcmService, NotificationBroadcastService],
  exports: [FcmService, NotificationBroadcastService],
})
export class NotificationsModule {}
