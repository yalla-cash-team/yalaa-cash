import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Query,
} from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { CurrentUser } from "../auth/decorators/current-user.decorator";
import type { AuthenticatedUser } from "../auth/decorators/current-user.decorator";
import { Roles } from "../auth/decorators/roles.decorator";
import { NotificationBroadcastService } from "../notifications/notification-broadcast.service";
import { AdminService } from "./admin.service";
import {
  AdjustCustomerPointsDto,
  AdminListCashRequestsDto,
  AdminListProductRedemptionsDto,
  AdminListTransactionsDto,
  CreateBannerDto,
  CreateDigitalProductDto,
  CreateGovernorateDto,
  CreateMerchantAccountDto,
  CreateStoreDto,
  ResolveCashRequestDto,
  ResolveProductRedemptionDto,
  SendNotificationDto,
  UpdateMinCashWithdrawalDto,
  UpdateShareRewardDto,
  UpdateStoreLogoDto,
  MonthlySettlementDto,
  SettleStoreDto,
  SettlementQueryDto,
  UpdateBannerDto,
  UpdateDigitalProductDto,
  UpdateGovernorateDto,
  UpdatePointSettingsDto,
  UpdateStoreDto,
} from "./dto/admin.dto";

@Roles(UserRole.ADMIN)
@Controller("admin")
export class AdminController {
  constructor(
    private readonly admin: AdminService,
    private readonly broadcasts: NotificationBroadcastService,
  ) {}

  @Get("overview")
  overview() {
    return this.admin.overview();
  }

  @Get("customers")
  listCustomers() {
    return this.admin.listCustomers();
  }

  @Get("transactions")
  listRecentTransactions(@Query() query: AdminListTransactionsDto) {
    return this.admin.listRecentTransactions(query.limit ?? 8);
  }

  @Post("customers/:customerId/points/grant")
  grantPoints(
    @CurrentUser() user: AuthenticatedUser,
    @Param("customerId") customerId: string,
    @Body() dto: AdjustCustomerPointsDto,
  ) {
    return this.admin.grantPoints(user.id, customerId, dto);
  }

  @Post("customers/:customerId/points/deduct")
  deductPoints(
    @CurrentUser() user: AuthenticatedUser,
    @Param("customerId") customerId: string,
    @Body() dto: AdjustCustomerPointsDto,
  ) {
    return this.admin.deductPoints(user.id, customerId, dto);
  }

  @Delete("customers/:customerId")
  deleteCustomer(@Param("customerId") customerId: string) {
    return this.admin.deleteCustomer(customerId);
  }

  @Get("cash-requests")
  listCashRequests(@Query() query: AdminListCashRequestsDto) {
    return this.admin.listCashRequests(query);
  }

  @Post("cash-requests/:requestId/resolve")
  resolveCashRequest(
    @CurrentUser() user: AuthenticatedUser,
    @Param("requestId") requestId: string,
    @Body() dto: ResolveCashRequestDto,
  ) {
    return this.admin.resolveCashRequest(user.id, requestId, dto.approve);
  }

  @Get("product-redemptions")
  listProductRedemptions(@Query() query: AdminListProductRedemptionsDto) {
    return this.admin.listProductRedemptions(query);
  }

  @Post("product-redemptions/:redemptionId/resolve")
  resolveProductRedemption(
    @Param("redemptionId") redemptionId: string,
    @Body() dto: ResolveProductRedemptionDto,
  ) {
    return this.admin.resolveProductRedemption(redemptionId, dto);
  }

  // Broadcasts to every customer device. Admin-only via class-level @Roles.
  @Post("notifications")
  sendNotification(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: SendNotificationDto,
  ) {
    return this.broadcasts.send(user.id, dto);
  }

  @Get("notifications")
  listNotifications() {
    return this.broadcasts.list();
  }

  @Get("stores")
  listStores() {
    return this.admin.listStores();
  }

  @Get("governorates")
  listGovernorates() {
    return this.admin.listGovernorates();
  }

  @Get("banners")
  listBanners(@Query("placement") placement?: string) {
    return this.admin.listBanners(placement);
  }

  @Post("banners")
  createBanner(@Body() dto: CreateBannerDto) {
    return this.admin.createBanner(dto);
  }

  @Patch("banners/:bannerId")
  updateBanner(
    @Param("bannerId") bannerId: string,
    @Body() dto: UpdateBannerDto,
  ) {
    return this.admin.updateBanner(bannerId, dto);
  }

  // Admin-only (class-level @Roles(ADMIN)); the file is validated in the service.
  @Put("banners/:bannerId/image")
  setBannerImage(
    @Param("bannerId") bannerId: string,
    @Body() dto: UpdateStoreLogoDto,
  ) {
    return this.admin.setBannerImage(bannerId, dto);
  }

  @Delete("banners/:bannerId/image")
  removeBannerImage(@Param("bannerId") bannerId: string) {
    return this.admin.removeBannerImage(bannerId);
  }

  @Delete("banners/:bannerId")
  deleteBanner(@Param("bannerId") bannerId: string) {
    return this.admin.deleteBanner(bannerId);
  }

  @Post("governorates")
  createGovernorate(@Body() dto: CreateGovernorateDto) {
    return this.admin.createGovernorate(dto);
  }

  @Patch("governorates/:governorateId")
  updateGovernorate(
    @Param("governorateId") governorateId: string,
    @Body() dto: UpdateGovernorateDto,
  ) {
    return this.admin.updateGovernorate(governorateId, dto);
  }

  @Post("stores")
  createStore(@Body() dto: CreateStoreDto) {
    return this.admin.createStore(dto);
  }

  @Patch("stores/:storeId")
  updateStore(@Param("storeId") storeId: string, @Body() dto: UpdateStoreDto) {
    return this.admin.updateStore(storeId, dto);
  }

  // Admin-only (class-level @Roles(ADMIN)); the file is validated in the service.
  @Put("stores/:storeId/logo")
  setStoreLogo(
    @Param("storeId") storeId: string,
    @Body() dto: UpdateStoreLogoDto,
  ) {
    return this.admin.setStoreLogo(storeId, dto);
  }

  @Delete("stores/:storeId/logo")
  removeStoreLogo(@Param("storeId") storeId: string) {
    return this.admin.removeStoreLogo(storeId);
  }

  // Soft delete only: deactivates the store (and its merchant accounts),
  // never physically deletes the row or any historical data. See
  // AdminService.deleteStore().
  @Delete("stores/:storeId")
  deleteStore(@Param("storeId") storeId: string) {
    return this.admin.deleteStore(storeId);
  }

  @Get("products")
  listProducts() {
    return this.admin.listProducts();
  }

  @Post("products")
  createProduct(@Body() dto: CreateDigitalProductDto) {
    return this.admin.createProduct(dto);
  }

  // Admin-only (class-level @Roles(ADMIN)); the file is validated in the service.
  @Put("products/:productId/image")
  setProductImage(
    @Param("productId") productId: string,
    @Body() dto: UpdateStoreLogoDto,
  ) {
    return this.admin.setProductImage(productId, dto);
  }

  @Delete("products/:productId/image")
  removeProductImage(@Param("productId") productId: string) {
    return this.admin.removeProductImage(productId);
  }

  @Patch("products/:productId")
  updateProduct(
    @Param("productId") productId: string,
    @Body() dto: UpdateDigitalProductDto,
  ) {
    return this.admin.updateProduct(productId, dto);
  }

  @Get("merchant-accounts")
  listMerchantAccounts() {
    return this.admin.listMerchantAccounts();
  }

  @Post("merchant-accounts")
  createMerchantAccount(@Body() dto: CreateMerchantAccountDto) {
    return this.admin.createMerchantAccount(dto);
  }

  // Stores the minimum payout only; no withdrawal flow reads it yet.
  @Patch("settings/min-cash-withdrawal")
  updateMinCashWithdrawal(@Body() dto: UpdateMinCashWithdrawalDto) {
    return this.admin.updateMinCashWithdrawal(dto);
  }

  @Patch("settings/share-reward")
  updateShareReward(@Body() dto: UpdateShareRewardDto) {
    return this.admin.updateShareRewardPoints(dto);
  }

  @Get("settings")
  getSettings() {
    return this.admin.getSettings();
  }

  @Patch("settings")
  updateSettings(@Body() dto: UpdatePointSettingsDto) {
    return this.admin.updateSettings(dto);
  }

  @Get("settlements")
  listSettlements(@Query() query: SettlementQueryDto) {
    return this.admin.listSettlements(query);
  }

  // Monthly settlement: preview, bulk run (admin-only), and history.
  @Get("settlements/monthly")
  previewMonthlySettlement(@Query() query: MonthlySettlementDto) {
    return this.admin.previewMonthlySettlement(query);
  }

  @Post("settlements/monthly")
  runMonthlySettlement(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: MonthlySettlementDto,
  ) {
    return this.admin.runMonthlySettlement(user.id, dto);
  }

  @Get("settlements/monthly/history")
  listMonthlySettlementHistory() {
    return this.admin.listMonthlySettlementHistory();
  }

  @Post("settlements/settle")
  settleStore(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: SettleStoreDto,
  ) {
    return this.admin.settleStore(user.id, dto);
  }
}
