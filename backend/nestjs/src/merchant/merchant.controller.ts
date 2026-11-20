import { Body, Controller, Get, Post, Query } from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { CurrentUser } from "../auth/decorators/current-user.decorator";
import type { AuthenticatedUser } from "../auth/decorators/current-user.decorator";
import { Roles } from "../auth/decorators/roles.decorator";
import { PaginationQueryDto } from "../common/pagination.dto";
import {
  MerchantPeriodQueryDto,
  RegisterInvoiceDto,
  RegisterMerchantDeviceDto,
  ResolveCustomerQrDto,
} from "./dto/merchant.dto";
import { MerchantService } from "./merchant.service";

@Roles(UserRole.MERCHANT)
@Controller("merchant")
export class MerchantController {
  constructor(private readonly merchant: MerchantService) {}

  @Get("me")
  getWorkspace(@CurrentUser() user: AuthenticatedUser) {
    return this.merchant.getWorkspace(user.id);
  }

  @Post("devices")
  registerDevice(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RegisterMerchantDeviceDto,
  ) {
    return this.merchant.registerDevice(user.id, dto);
  }

  @Post("qr/resolve")
  resolveCustomerQr(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: ResolveCustomerQrDto,
  ) {
    return this.merchant.resolveCustomerQr(user.id, dto);
  }

  @Post("invoices")
  registerInvoice(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RegisterInvoiceDto,
  ) {
    return this.merchant.registerInvoice(user.id, dto);
  }

  @Get("summary")
  getSummary(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: MerchantPeriodQueryDto,
  ) {
    return this.merchant.getSummary(user.id, query);
  }

  @Get("transactions")
  listTransactions(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: PaginationQueryDto,
  ) {
    return this.merchant.listTransactions(user.id, query);
  }
}
