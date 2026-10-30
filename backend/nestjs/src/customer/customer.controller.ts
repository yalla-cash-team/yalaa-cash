import { Body, Controller, Get, Patch, Post, Query } from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { CurrentUser } from "../auth/decorators/current-user.decorator";
import type { AuthenticatedUser } from "../auth/decorators/current-user.decorator";
import { Roles } from "../auth/decorators/roles.decorator";
import { PaginationQueryDto } from "../common/pagination.dto";
import { CustomerService } from "./customer.service";
import {
  RedeemDigitalProductDto,
  RegisterDeviceTokenDto,
  RequestCashRedemptionDto,
  UpdateCustomerGovernorateDto,
  UpdateCustomerProfileDto,
} from "./dto/customer.dto";

@Roles(UserRole.CUSTOMER)
@Controller("customer")
export class CustomerController {
  constructor(private readonly customer: CustomerService) {}

  @Get("profile")
  getProfile(@CurrentUser() user: AuthenticatedUser) {
    return this.customer.getProfile(user.id);
  }

  @Patch("profile")
  updateProfile(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UpdateCustomerProfileDto,
  ) {
    return this.customer.updateProfile(user.id, dto);
  }

  @Get("governorates")
  listActiveGovernorates() {
    return this.customer.listActiveGovernorates();
  }

  @Patch("governorate")
  updateGovernorate(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UpdateCustomerGovernorateDto,
  ) {
    return this.customer.updateGovernorate(user.id, dto);
  }

  @Get("points")
  getPoints(@CurrentUser() user: AuthenticatedUser) {
    return this.customer.getPoints(user.id);
  }

  // The reward is granted server-side once per account. Opening the share
  // sheet cannot prove delivery, so the app calls this after the share action.
  @Post("share-reward/claim")
  claimShareReward(@CurrentUser() user: AuthenticatedUser) {
    return this.customer.claimShareReward(user.id);
  }

  @Post("qr-token")
  issueQrToken(@CurrentUser() user: AuthenticatedUser) {
    return this.customer.issueQrToken(user.id);
  }

  @Post("device-token")
  registerDeviceToken(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RegisterDeviceTokenDto,
  ) {
    return this.customer.registerDeviceToken(user.id, dto);
  }

  // Called on sign-out. Only this account's own token row is removed, so one
  // customer can never detach another customer's device.
  @Post("device-token/remove")
  removeDeviceToken(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RegisterDeviceTokenDto,
  ) {
    return this.customer.removeDeviceToken(user.id, dto);
  }

  @Get("transactions")
  listTransactions(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: PaginationQueryDto,
  ) {
    return this.customer.listTransactions(user.id, query);
  }

  @Get("digital-products")
  listDigitalProducts() {
    return this.customer.listDigitalProducts();
  }

  @Get("banners")
  listBanners(
    @CurrentUser() user: AuthenticatedUser,
    @Query("placement") placement?: string,
  ) {
    return this.customer.listActiveBanners(user.id, placement ?? "HOME");
  }

  @Get("redemptions/cash")
  listCashRequests(@CurrentUser() user: AuthenticatedUser) {
    return this.customer.listCashRequests(user.id);
  }

  @Post("redemptions/cash")
  requestCashRedemption(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RequestCashRedemptionDto,
  ) {
    return this.customer.requestCashRedemption(user.id, dto);
  }

  @Post("redemptions/products")
  redeemDigitalProduct(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RedeemDigitalProductDto,
  ) {
    return this.customer.redeemDigitalProduct(user.id, dto);
  }

  @Get("redemptions/products")
  listProductRedemptions(@CurrentUser() user: AuthenticatedUser) {
    return this.customer.listProductRedemptions(user.id);
  }
}
