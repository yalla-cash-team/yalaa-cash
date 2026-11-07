import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
} from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { Transform } from "class-transformer";
import { IsBoolean, IsInt, IsOptional, Max, Min } from "class-validator";
import { CurrentUser } from "../auth/decorators/current-user.decorator";
import type { AuthenticatedUser } from "../auth/decorators/current-user.decorator";
import { Roles } from "../auth/decorators/roles.decorator";
import { CustomerNotificationService } from "./customer-notification.service";

export class ListCustomerNotificationsQueryDto {
  /// true (default): unread only. false: every notification.
  @IsOptional()
  @Transform(({ value }) =>
    value === undefined ? undefined : value === true || value === "true",
  )
  @IsBoolean()
  unread?: boolean = true;

  @IsOptional()
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 50;
}

/// The signed-in customer's own notification inbox. Customer-only: other
/// roles get 403 and missing tokens 401 from the global guards.
@Roles(UserRole.CUSTOMER)
@Controller("customer/notifications")
export class CustomerNotificationsController {
  constructor(private readonly inbox: CustomerNotificationService) {}

  @Get()
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: ListCustomerNotificationsQueryDto,
  ) {
    return this.inbox.list(user.id, {
      unreadOnly: query.unread !== false,
      limit: query.limit,
    });
  }

  /// Marks exactly this one notification as read. Opening the inbox never
  /// marks anything.
  @Post(":notificationId/read")
  @HttpCode(HttpStatus.OK)
  markRead(
    @CurrentUser() user: AuthenticatedUser,
    @Param("notificationId", ParseUUIDPipe) notificationId: string,
  ) {
    return this.inbox.markRead(user.id, notificationId);
  }
}
