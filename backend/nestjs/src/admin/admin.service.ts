import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import {
  CashRequestStatus,
  PointsEntryType,
  Prisma,
  RedemptionStatus,
  SettlementKind,
  SettlementStatus,
  UserRole,
} from "@prisma/client";
import { randomInt } from "crypto";
import {
  MonthBounds,
  parseCompletedMonth,
  settleEachMerchant,
  summarizeOutcomes,
} from "./monthly-settlement";
import { PasswordService } from "../auth/password.service";
import {
  presentBanner,
  presentCashRequest,
  presentCustomer,
  presentDigitalProduct,
  presentGovernorate,
  presentMerchantAccount,
  presentProductRedemption,
  presentStore,
  presentTransaction,
  toNumber,
} from "../common/presenters";
import { FcmService } from "../notifications/fcm.service";
import { PrismaService } from "../prisma/prisma.service";
import {
  AdjustCustomerPointsDto,
  AdminListCashRequestsDto,
  AdminListProductRedemptionsDto,
  CreateBannerDto,
  CreateDigitalProductDto,
  CreateGovernorateDto,
  CreateMerchantAccountDto,
  CreateStoreDto,
  ResolveProductRedemptionDto,
  SettleStoreDto,
  SettlementQueryDto,
  UpdateBannerDto,
  UpdateDigitalProductDto,
  UpdateGovernorateDto,
  UpdatePointSettingsDto,
  UpdateStoreDto,
  UpdateMinCashWithdrawalDto,
  UpdateShareRewardDto,
  UpdateStoreLogoDto,
} from "./dto/admin.dto";
import { decodeStoreLogo } from "../stores/store-logo";
import { convertPointBalance } from "../loyalty/point-conversion";

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly passwords: PasswordService,
    private readonly fcm: FcmService,
  ) {}

  async overview() {
    const [
      customerCount,
      storeCount,
      transactionAggregate,
      pendingCashRequests,
    ] = await Promise.all([
      this.prisma.customerProfile.count(),
      this.prisma.store.count({ where: { isActive: true } }),
      this.prisma.loyaltyTransaction.aggregate({
        _count: { id: true },
        _sum: {
          amountSyp: true,
          platformRevenueSyp: true,
          commissionAmountSyp: true,
        },
      }),
      this.prisma.cashRedemptionRequest.count({
        where: { status: CashRequestStatus.PENDING },
      }),
    ]);

    return {
      customers: customerCount,
      activeStores: storeCount,
      transactions: transactionAggregate._count.id,
      totalSalesSyp: toNumber(transactionAggregate._sum.amountSyp ?? 0n),
      platformRevenueSyp: toNumber(
        transactionAggregate._sum.platformRevenueSyp ?? 0n,
      ),
      commissionDueSyp: toNumber(
        transactionAggregate._sum.commissionAmountSyp ?? 0n,
      ),
      pendingCashRequests,
    };
  }

  async listCustomers() {
    const customers = await this.prisma.customerProfile.findMany({
      include: { user: true },
      orderBy: { createdAt: "desc" },
    });
    return { items: customers.map(presentCustomer) };
  }

  async listRecentTransactions(limit: number) {
    const safeLimit = Math.min(Math.max(Math.trunc(limit) || 8, 1), 50);
    const transactions = await this.prisma.loyaltyTransaction.findMany({
      include: { store: { select: { name: true } } },
      orderBy: { createdAt: "desc" },
      take: safeLimit,
    });
    return { items: transactions.map(presentTransaction) };
  }

  async grantPoints(
    adminUserId: string,
    customerId: string,
    dto: AdjustCustomerPointsDto,
  ) {
    return this.adjustPoints(adminUserId, customerId, dto, dto.points);
  }

  async deductPoints(
    adminUserId: string,
    customerId: string,
    dto: AdjustCustomerPointsDto,
  ) {
    return this.adjustPoints(adminUserId, customerId, dto, -dto.points);
  }

  async deleteCustomer(customerId: string) {
    await this.prisma.user.delete({ where: { id: customerId } });
    return { success: true };
  }

  async listCashRequests(query: AdminListCashRequestsDto) {
    const status = query.status?.toUpperCase() as CashRequestStatus | undefined;
    const requests = await this.prisma.cashRedemptionRequest.findMany({
      where: status ? { status } : undefined,
      include: { customer: { select: { name: true } } },
      orderBy: { createdAt: "desc" },
    });
    return { items: requests.map(presentCashRequest) };
  }

  async resolveCashRequest(
    adminUserId: string,
    requestId: string,
    approve: boolean,
  ) {
    const updated = await this.prisma.$transaction(
      async (tx) => {
        const request = await tx.cashRedemptionRequest.findUnique({
          where: { id: requestId },
        });
        if (!request || request.status !== CashRequestStatus.PENDING) {
          throw new NotFoundException("Pending cash request was not found.");
        }

        if (!approve) {
          const customer = await tx.customerProfile.findUniqueOrThrow({
            where: { userId: request.customerId },
            select: { pointsBalance: true },
          });
          const rejected = await tx.cashRedemptionRequest.update({
            where: { id: request.id },
            data: {
              status: CashRequestStatus.REJECTED,
              settledByUserId: adminUserId,
              settledAt: new Date(),
            },
          });
          await tx.pointsLedgerEntry.create({
            data: {
              customerId: request.customerId,
              entryType: PointsEntryType.CASH_RELEASE,
              pointsDelta: 0,
              balanceAfter: customer.pointsBalance,
              referenceId: request.id,
              note: "Cash redemption request rejected.",
            },
          });
          return rejected;
        }

        const customer = await tx.customerProfile.findUnique({
          where: { userId: request.customerId },
          select: { pointsBalance: true },
        });
        if (!customer) throw new NotFoundException("Customer was not found.");
        if (customer.pointsBalance < request.pointsRequested) {
          throw new BadRequestException(
            "Customer does not have enough points.",
          );
        }

        const savedCustomer = await tx.customerProfile.update({
          where: { userId: request.customerId },
          data: { pointsBalance: { decrement: request.pointsRequested } },
          select: { pointsBalance: true },
        });
        const settled = await tx.cashRedemptionRequest.update({
          where: { id: request.id },
          data: {
            status: CashRequestStatus.SETTLED,
            settledByUserId: adminUserId,
            settledAt: new Date(),
          },
        });
        await tx.pointsLedgerEntry.create({
          data: {
            customerId: request.customerId,
            entryType: PointsEntryType.CASH_SETTLE,
            pointsDelta: -request.pointsRequested,
            balanceAfter: savedCustomer.pointsBalance,
            referenceId: request.id,
            note: "Cash redemption request settled.",
          },
        });
        return settled;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    if (approve) {
      void this.fcm
        .sendToUser(updated.customerId, {
          title: "تمت العملية",
          body: "تم تحويل مبلغ استبدال النقاط بنجاح.",
        })
        .catch(() => undefined);
    }

    return presentCashRequest(updated);
  }

  async listProductRedemptions(query: AdminListProductRedemptionsDto) {
    const status = query.status?.toUpperCase() as
      | RedemptionStatus
      | undefined;
    const items = await this.prisma.productRedemption.findMany({
      where: status ? { status } : undefined,
      include: {
        customer: { select: { name: true, user: { select: { phone: true } } } },
        product: { select: { name: true } },
      },
      orderBy: { createdAt: "desc" },
    });
    return { items: items.map(presentProductRedemption) };
  }

  /**
   * Deducts points exactly once, only here, only on approve — mirrors
   * resolveCashRequest: the status is re-checked inside a Serializable
   * transaction, so a request that already left PENDING (settled or
   * rejected by an earlier call) is rejected as NotFound rather than
   * processed a second time.
   */
  async resolveProductRedemption(
    redemptionId: string,
    dto: ResolveProductRedemptionDto,
  ) {
    const updated = await this.prisma.$transaction(
      async (tx) => {
        const redemption = await tx.productRedemption.findUnique({
          where: { id: redemptionId },
        });
        if (!redemption || redemption.status !== RedemptionStatus.PENDING) {
          throw new NotFoundException(
            "Pending product redemption was not found.",
          );
        }

        if (!dto.approve) {
          const customer = await tx.customerProfile.findUniqueOrThrow({
            where: { userId: redemption.customerId },
            select: { pointsBalance: true },
          });
          const rejected = await tx.productRedemption.update({
            where: { id: redemption.id },
            data: { status: RedemptionStatus.REJECTED },
          });
          await tx.pointsLedgerEntry.create({
            data: {
              customerId: redemption.customerId,
              entryType: PointsEntryType.PRODUCT_RELEASE,
              pointsDelta: 0,
              balanceAfter: customer.pointsBalance,
              referenceId: redemption.id,
              note: "Digital product redemption rejected.",
            },
          });
          return rejected;
        }

        const customer = await tx.customerProfile.findUnique({
          where: { userId: redemption.customerId },
          select: { pointsBalance: true },
        });
        if (!customer) throw new NotFoundException("Customer was not found.");
        if (customer.pointsBalance < redemption.pointsCostSnapshot) {
          throw new BadRequestException(
            "Customer does not have enough points.",
          );
        }

        const savedCustomer = await tx.customerProfile.update({
          where: { userId: redemption.customerId },
          data: { pointsBalance: { decrement: redemption.pointsCostSnapshot } },
          select: { pointsBalance: true },
        });
        const fulfilled = await tx.productRedemption.update({
          where: { id: redemption.id },
          data: { status: RedemptionStatus.FULFILLED, fulfilledAt: new Date() },
        });
        await tx.pointsLedgerEntry.create({
          data: {
            customerId: redemption.customerId,
            entryType: PointsEntryType.PRODUCT_REDEEM,
            pointsDelta: -redemption.pointsCostSnapshot,
            balanceAfter: savedCustomer.pointsBalance,
            referenceId: redemption.id,
            note: "Digital product redemption fulfilled.",
          },
        });
        return fulfilled;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    if (dto.approve) {
      void this.fcm
        .sendToUser(updated.customerId, {
          title: "تم الاستبدال",
          body: "تم استبدال طلبك بنجاح.",
        })
        .catch(() => undefined);
    }

    return presentProductRedemption(updated);
  }

  async listStores() {
    const stores = await this.prisma.store.findMany({
      orderBy: [{ city: "asc" }, { category: "asc" }, { name: "asc" }],
    });
    return { items: stores.map(presentStore) };
  }

  async listGovernorates() {
    const items = await this.prisma.governorate.findMany({
      orderBy: [{ displayOrder: "asc" }, { nameAr: "asc" }],
    });
    return { items: items.map(presentGovernorate) };
  }

  async listBanners(placement?: string) {
    const items = await this.prisma.banner.findMany({
      where: placement
        ? { placement: placement.toUpperCase() as any }
        : undefined,
      orderBy: [{ displayOrder: "asc" }, { createdAt: "desc" }],
    });
    return { items: items.map(presentBanner) };
  }

  async createBanner(dto: CreateBannerDto) {
    const item = await this.prisma.banner.create({
      data: {
        title: dto.title.trim(),
        subtitle: dto.subtitle?.trim() || null,
        imageUrl: dto.imageUrl.trim(),
        targetUrl: dto.targetUrl?.trim() || null,
        placement: dto.placement ?? "HOME",
        style: dto.style ?? "PROMO",
        isActive: dto.isActive ?? true,
        displayOrder: dto.displayOrder,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : null,
        governorateId: dto.governorateId || null,
      },
    });
    return presentBanner(item);
  }

  async updateBanner(bannerId: string, dto: UpdateBannerDto) {
    const current = await this.prisma.banner.findUnique({
      where: { id: bannerId },
    });
    if (!current) throw new NotFoundException("Banner was not found.");

    const item = await this.prisma.banner.update({
      where: { id: bannerId },
      data: {
        ...(dto.title !== undefined ? { title: dto.title.trim() } : {}),
        ...(dto.subtitle !== undefined
          ? { subtitle: dto.subtitle.trim() || null }
          : {}),
        ...(dto.imageUrl !== undefined
          ? { imageUrl: dto.imageUrl.trim() }
          : {}),
        ...(dto.targetUrl !== undefined
          ? { targetUrl: dto.targetUrl.trim() || null }
          : {}),
        ...(dto.placement !== undefined ? { placement: dto.placement } : {}),
        ...(dto.style !== undefined ? { style: dto.style } : {}),
        ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
        ...(dto.displayOrder !== undefined
          ? { displayOrder: dto.displayOrder }
          : {}),
        ...(dto.startsAt !== undefined
          ? { startsAt: dto.startsAt ? new Date(dto.startsAt) : null }
          : {}),
        ...(dto.endsAt !== undefined
          ? { endsAt: dto.endsAt ? new Date(dto.endsAt) : null }
          : {}),
        ...(dto.governorateId !== undefined
          ? { governorateId: dto.governorateId || null }
          : {}),
      },
    });
    return presentBanner(item);
  }

  async deleteBanner(bannerId: string) {
    const current = await this.prisma.banner.findUnique({
      where: { id: bannerId },
    });
    if (!current) throw new NotFoundException("Banner was not found.");
    await this.prisma.banner.delete({ where: { id: bannerId } });
    return { success: true };
  }

  async createGovernorate(dto: CreateGovernorateDto) {
    const item = await this.prisma.governorate.create({
      data: {
        nameAr: dto.nameAr.trim(),
        isActive: dto.isActive ?? false,
        displayOrder: dto.displayOrder,
      },
    });
    return presentGovernorate(item);
  }

  async updateGovernorate(governorateId: string, dto: UpdateGovernorateDto) {
    const current = await this.prisma.governorate.findUnique({
      where: { id: governorateId },
    });
    if (!current) throw new NotFoundException("Governorate was not found.");
    const item = await this.prisma.governorate.update({
      where: { id: governorateId },
      data: {
        ...(dto.nameAr !== undefined ? { nameAr: dto.nameAr.trim() } : {}),
        ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
        ...(dto.displayOrder !== undefined
          ? { displayOrder: dto.displayOrder }
          : {}),
      },
    });
    return presentGovernorate(item);
  }

  async createStore(dto: CreateStoreDto) {
    await this.assertExclusiveStoreSlot(dto.city, dto.category);
    const store = await this.prisma.store.create({
      data: {
        name: dto.name.trim(),
        category: dto.category.trim(),
        city: dto.city.trim(),
        commissionRate: new Prisma.Decimal(dto.commissionRate),
        description: dto.description?.trim() ?? "",
        location: dto.location?.trim() ?? "",
        imageUrl: dto.imageUrl?.trim() || null,
        iconSeed: dto.iconSeed ?? 0,
        isActive: dto.isActive ?? true,
        governorateId: dto.governorateId,
      },
    });
    return presentStore(store);
  }

  async updateStore(storeId: string, dto: UpdateStoreDto) {
    const current = await this.prisma.store.findUnique({
      where: { id: storeId },
    });
    if (!current) throw new NotFoundException("Store was not found.");
    const nextCity = dto.city?.trim() ?? current.city;
    const nextCategory = dto.category?.trim() ?? current.category;
    const nextActive = dto.isActive ?? current.isActive;
    if (nextActive)
      await this.assertExclusiveStoreSlot(nextCity, nextCategory, storeId);

    const store = await this.prisma.store.update({
      where: { id: storeId },
      data: {
        ...(dto.name ? { name: dto.name.trim() } : {}),
        ...(dto.category ? { category: nextCategory } : {}),
        ...(dto.city ? { city: nextCity } : {}),
        ...(dto.commissionRate !== undefined
          ? { commissionRate: new Prisma.Decimal(dto.commissionRate) }
          : {}),
        ...(dto.description !== undefined
          ? { description: dto.description.trim() }
          : {}),
        ...(dto.location !== undefined
          ? { location: dto.location.trim() }
          : {}),
        ...(dto.imageUrl !== undefined
          ? { imageUrl: dto.imageUrl.trim() || null }
          : {}),
        ...(dto.iconSeed !== undefined ? { iconSeed: dto.iconSeed } : {}),
        ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
        ...(dto.governorateId !== undefined
          ? { governorateId: dto.governorateId }
          : {}),
      },
    });
    return presentStore(store);
  }

  /// Soft delete only. A Store is never physically deleted — it, and every
  /// LoyaltyTransaction/MerchantSettlement row that references it, must
  /// remain intact forever for financial/audit history. "Delete" here means:
  /// mark the store inactive (so it immediately disappears from Customer's
  /// active-store listing, which already filters `isActive: true`) and mark
  /// its merchant account(s) inactive too (so the merchant can no longer
  /// perform new operations for a store that's no longer customer-visible —
  /// every merchant.service.ts operation already re-checks
  /// `MerchantAccount.isActive` on every call, so this alone is sufficient).
  /// Both writes happen in one transaction so they can never partially
  /// apply. Calling this again on an already-inactive store is a safe no-op.
  // Validates the image first (type, size and magic bytes) so nothing is
  // written for an invalid file.
  async setStoreLogo(storeId: string, dto: UpdateStoreLogoDto) {
    const logo = decodeStoreLogo(dto.contentType, dto.dataBase64);
    await this.assertStoreExists(storeId);

    const updated = await this.prisma.store.update({
      where: { id: storeId },
      data: {
        logoVersion: { increment: 1 },
        logo: {
          upsert: {
            create: { contentType: logo.contentType, data: logo.data },
            update: { contentType: logo.contentType, data: logo.data },
          },
        },
      },
    });
    return presentStore(updated);
  }

  async removeStoreLogo(storeId: string) {
    await this.assertStoreExists(storeId);

    const [, updated] = await this.prisma.$transaction([
      this.prisma.storeLogo.deleteMany({ where: { storeId } }),
      this.prisma.store.update({
        where: { id: storeId },
        data: { logoVersion: { increment: 1 } },
      }),
    ]);
    return presentStore(updated);
  }

  private async assertStoreExists(storeId: string): Promise<void> {
    const store = await this.prisma.store.findUnique({
      where: { id: storeId },
      select: { id: true },
    });
    if (!store) throw new NotFoundException("Store was not found.");
  }

  // Same validation as store logos (PNG/JPEG/WebP, size cap, magic bytes).
  async setProductImage(productId: string, dto: UpdateStoreLogoDto) {
    const image = decodeStoreLogo(dto.contentType, dto.dataBase64);
    await this.assertProductExists(productId);

    const updated = await this.prisma.digitalProduct.update({
      where: { id: productId },
      data: {
        imageVersion: { increment: 1 },
        image: {
          upsert: {
            create: { contentType: image.contentType, data: image.data },
            update: { contentType: image.contentType, data: image.data },
          },
        },
      },
    });
    return presentDigitalProduct(updated);
  }

  async removeProductImage(productId: string) {
    await this.assertProductExists(productId);

    const [, updated] = await this.prisma.$transaction([
      this.prisma.digitalProductImage.deleteMany({ where: { productId } }),
      this.prisma.digitalProduct.update({
        where: { id: productId },
        data: { imageVersion: { increment: 1 } },
      }),
    ]);
    return presentDigitalProduct(updated);
  }

  private async assertProductExists(productId: string): Promise<void> {
    const product = await this.prisma.digitalProduct.findUnique({
      where: { id: productId },
      select: { id: true },
    });
    if (!product) throw new NotFoundException("Product was not found.");
  }

  // Same image validation as store logos and product images.
  async setBannerImage(bannerId: string, dto: UpdateStoreLogoDto) {
    const image = decodeStoreLogo(dto.contentType, dto.dataBase64);
    await this.assertBannerExists(bannerId);

    const updated = await this.prisma.banner.update({
      where: { id: bannerId },
      data: {
        imageVersion: { increment: 1 },
        image: {
          upsert: {
            create: { contentType: image.contentType, data: image.data },
            update: { contentType: image.contentType, data: image.data },
          },
        },
      },
    });
    return presentBanner(updated);
  }

  async removeBannerImage(bannerId: string) {
    await this.assertBannerExists(bannerId);

    const [, updated] = await this.prisma.$transaction([
      this.prisma.bannerImage.deleteMany({ where: { bannerId } }),
      this.prisma.banner.update({
        where: { id: bannerId },
        data: { imageVersion: { increment: 1 } },
      }),
    ]);
    return presentBanner(updated);
  }

  private async assertBannerExists(bannerId: string): Promise<void> {
    const banner = await this.prisma.banner.findUnique({
      where: { id: bannerId },
      select: { id: true },
    });
    if (!banner) throw new NotFoundException("Banner was not found.");
  }

  async deleteStore(storeId: string) {
    const current = await this.prisma.store.findUnique({
      where: { id: storeId },
    });
    if (!current) throw new NotFoundException("Store was not found.");

    await this.prisma.$transaction([
      this.prisma.store.update({
        where: { id: storeId },
        data: { isActive: false },
      }),
      this.prisma.merchantAccount.updateMany({
        where: { storeId },
        data: { isActive: false },
      }),
    ]);

    return { success: true };
  }

  async listProducts() {
    const products = await this.prisma.digitalProduct.findMany({
      orderBy: [{ isActive: "desc" }, { costInPoints: "asc" }, { name: "asc" }],
    });
    return { items: products.map(presentDigitalProduct) };
  }

  async createProduct(dto: CreateDigitalProductDto) {
    const product = await this.prisma.digitalProduct.create({
      data: {
        name: dto.name.trim(),
        costInPoints: BigInt(dto.costInPoints),
        imageUrl: dto.imageUrl?.trim() || null,
        iconSeed: dto.iconSeed ?? 0,
        requiresPhoneNumber: dto.requiresPhoneNumber ?? false,
        isActive: dto.isActive ?? true,
      },
    });
    return presentDigitalProduct(product);
  }

  async updateProduct(productId: string, dto: UpdateDigitalProductDto) {
    const product = await this.prisma.digitalProduct.update({
      where: { id: productId },
      data: {
        ...(dto.name ? { name: dto.name.trim() } : {}),
        ...(dto.costInPoints !== undefined
          ? { costInPoints: BigInt(dto.costInPoints) }
          : {}),
        ...(dto.imageUrl !== undefined
          ? { imageUrl: dto.imageUrl.trim() || null }
          : {}),
        ...(dto.iconSeed !== undefined ? { iconSeed: dto.iconSeed } : {}),
        ...(dto.requiresPhoneNumber !== undefined
          ? { requiresPhoneNumber: dto.requiresPhoneNumber }
          : {}),
        ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
      },
    });
    return presentDigitalProduct(product);
  }

  async listMerchantAccounts() {
    const accounts = await this.prisma.merchantAccount.findMany({
      include: {
        user: { select: { email: true } },
        store: { select: { name: true } },
        _count: { select: { devices: true } },
      },
      orderBy: { createdAt: "desc" },
    });
    return { items: accounts.map(presentMerchantAccount) };
  }

  async createMerchantAccount(dto: CreateMerchantAccountDto) {
    const password = dto.password ?? this.generatePassword();
    const passwordHash = await this.passwords.hash(password);
    const account = await this.prisma.merchantAccount.create({
      data: {
        displayLabel: dto.displayLabel?.trim() || "Primary account",
        store: { connect: { id: dto.storeId } },
        user: {
          create: {
            role: UserRole.MERCHANT,
            email: dto.email.trim().toLowerCase(),
            passwordHash,
          },
        },
      },
      include: {
        user: { select: { email: true } },
        store: { select: { name: true } },
        _count: { select: { devices: true } },
      },
    });
    return {
      account: presentMerchantAccount(account),
      temporaryPassword: password,
    };
  }

  async getSettings() {
    const settings = await this.prisma.platformSettings.upsert({
      where: { id: 1 },
      update: {},
      create: { id: 1, pointValueSyp: 5 },
    });
    return {
      pointValueSyp: settings.pointValueSyp.toNumber(),
      minCashWithdrawalSyp: Number(settings.minCashWithdrawalSyp),
      shareRewardPoints: Number(settings.shareRewardPoints),
      updatedAt: settings.updatedAt.toISOString(),
    };
  }

  /// Changes the SYP value of one point and converts every balance so each
  /// customer keeps the same monetary amount. One Serializable transaction:
  /// concurrent earnings or redemptions either finish first or retry.
  /// Requests pending at the old value block the change, because their
  /// held points and fixed cash amounts would no longer match.
  async updateSettings(dto: UpdatePointSettingsDto) {
    const newValue = new Prisma.Decimal(dto.pointValueSyp);

    const settings = await this.prisma.$transaction(
      async (tx) => {
        const current = await tx.platformSettings.upsert({
          where: { id: 1 },
          update: {},
          create: { id: 1, pointValueSyp: 5 },
        });
        if (current.pointValueSyp.equals(newValue)) return current;

        const [pendingCash, pendingProducts] = await Promise.all([
          tx.cashRedemptionRequest.count({
            where: { status: CashRequestStatus.PENDING },
          }),
          tx.productRedemption.count({
            where: { status: RedemptionStatus.PENDING },
          }),
        ]);
        if (pendingCash + pendingProducts > 0) {
          throw new ConflictException(
            "Resolve pending cash and product requests before changing the point value.",
          );
        }

        const customers = await tx.customerProfile.findMany({
          where: {
            OR: [
              { pointsBalance: { gt: 0 } },
              { pointRemainderSyp: { gt: 0 } },
            ],
          },
          select: {
            userId: true,
            pointsBalance: true,
            pointRemainderSyp: true,
          },
        });

        for (const customer of customers) {
          const next = convertPointBalance(
            {
              points: customer.pointsBalance,
              remainderSyp: customer.pointRemainderSyp,
            },
            current.pointValueSyp,
            newValue,
          );
          const delta = next.points - customer.pointsBalance;
          await tx.customerProfile.update({
            where: { userId: customer.userId },
            data: {
              pointsBalance: next.points,
              pointRemainderSyp: next.remainderSyp,
            },
          });
          if (delta !== BigInt(0)) {
            await tx.pointsLedgerEntry.create({
              data: {
                customerId: customer.userId,
                entryType: PointsEntryType.POINT_CONVERSION,
                pointsDelta: delta,
                balanceAfter: next.points,
                note: `Point value changed from ${current.pointValueSyp.toString()} to ${newValue.toString()} SYP.`,
              },
            });
          }
        }

        return tx.platformSettings.update({
          where: { id: 1 },
          data: { pointValueSyp: newValue },
        });
      },
      {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        timeout: 60_000,
      },
    );

    return {
      pointValueSyp: settings.pointValueSyp.toNumber(),
      minCashWithdrawalSyp: Number(settings.minCashWithdrawalSyp),
      shareRewardPoints: Number(settings.shareRewardPoints),
      updatedAt: settings.updatedAt.toISOString(),
    };
  }

  async updateMinCashWithdrawal(dto: UpdateMinCashWithdrawalDto) {
    const settings = await this.prisma.platformSettings.upsert({
      where: { id: 1 },
      update: { minCashWithdrawalSyp: BigInt(dto.minCashWithdrawalSyp) },
      create: {
        id: 1,
        pointValueSyp: 5,
        minCashWithdrawalSyp: BigInt(dto.minCashWithdrawalSyp),
      },
    });
    return {
      minCashWithdrawalSyp: Number(settings.minCashWithdrawalSyp),
      shareRewardPoints: Number(settings.shareRewardPoints),
      updatedAt: settings.updatedAt.toISOString(),
    };
  }

  async updateShareRewardPoints(dto: UpdateShareRewardDto) {
    const settings = await this.prisma.platformSettings.upsert({
      where: { id: 1 },
      update: { shareRewardPoints: BigInt(dto.shareRewardPoints) },
      create: {
        id: 1,
        pointValueSyp: 5,
        shareRewardPoints: BigInt(dto.shareRewardPoints),
      },
    });
    return {
      shareRewardPoints: Number(settings.shareRewardPoints),
      updatedAt: settings.updatedAt.toISOString(),
    };
  }

  /// The store's most recent SETTLED settlement row, or `undefined` if the
  /// store has never been settled. This is the single source of truth for
  /// where the CURRENT accounting cycle begins — `settledAt` (not any
  /// calendar boundary) is what separates already-settled transactions from
  /// pending ones, so a store can be settled as many times as needed, even
  /// repeatedly on the same calendar day, the moment new transactions exist.
  private async latestSettlement(storeId: string) {
    return this.prisma.merchantSettlement.findFirst({
      where: {
        storeId,
        kind: SettlementKind.CYCLE,
        status: SettlementStatus.SETTLED,
      },
      orderBy: { settledAt: "desc" },
    });
  }

  /// Cycle totals must leave out invoices that a monthly settlement already
  /// covered, so no invoice is counted in two settlements.
  private async monthlyExclusions(
    storeId: string,
  ): Promise<Prisma.LoyaltyTransactionWhereInput[] | undefined> {
    const monthly = await this.prisma.merchantSettlement.findMany({
      where: {
        storeId,
        kind: SettlementKind.MONTHLY,
        status: SettlementStatus.SETTLED,
      },
      select: { periodStart: true, periodEnd: true },
    });
    // Undefined keeps the original query shape when no monthly rows exist.
    if (monthly.length === 0) return undefined;
    return monthly.map((row) => ({
      NOT: { createdAt: { gte: row.periodStart, lt: row.periodEnd } },
    }));
  }

  /// Unpaid invoices of one merchant in one calendar month: created after the
  /// last cycle settlement, and not already covered by a monthly settlement.
  private async unpaidForMonth(
    db: Prisma.TransactionClient,
    storeId: string,
    bounds: MonthBounds,
  ) {
    const monthlyRow = await db.merchantSettlement.findFirst({
      where: {
        storeId,
        kind: SettlementKind.MONTHLY,
        periodStart: bounds.periodStart,
        periodEnd: bounds.periodEnd,
      },
      select: { id: true },
    });
    const latestCycle = await db.merchantSettlement.findFirst({
      where: {
        storeId,
        kind: SettlementKind.CYCLE,
        status: SettlementStatus.SETTLED,
      },
      orderBy: { settledAt: "desc" },
    });
    const cycleBoundary = latestCycle?.settledAt ?? null;
    const from =
      cycleBoundary && cycleBoundary > bounds.periodStart
        ? cycleBoundary
        : bounds.periodStart;
    const aggregate = monthlyRow
      ? null
      : await db.loyaltyTransaction.aggregate({
          where: { storeId, createdAt: { gte: from, lt: bounds.periodEnd } },
          _count: { id: true },
          _sum: { amountSyp: true, commissionAmountSyp: true },
        });
    return {
      alreadySettled: monthlyRow !== null,
      transactionCount: aggregate?._count.id ?? 0,
      totalSalesSyp: toNumber(aggregate?._sum.amountSyp ?? BigInt(0)),
      commissionDueSyp: toNumber(
        aggregate?._sum.commissionAmountSyp ?? BigInt(0),
      ),
    };
  }

  /// Per-merchant status for a completed calendar month. Settling is a separate
  /// step, so this never changes any data.
  async previewMonthlySettlement(query: { month: string }) {
    const bounds = parseCompletedMonth(query.month, new Date());
    const stores = await this.prisma.store.findMany({
      orderBy: { name: "asc" },
      select: { id: true, name: true },
    });
    const merchants = await Promise.all(
      stores.map(async (store) => {
        const unpaid = await this.unpaidForMonth(this.prisma, store.id, bounds);
        const status = unpaid.alreadySettled
          ? "settled"
          : unpaid.transactionCount > 0
            ? "open"
            : "none";
        return {
          storeId: store.id,
          storeName: store.name,
          status,
          transactionCount: unpaid.transactionCount,
          totalSalesSyp: unpaid.totalSalesSyp,
          commissionDueSyp: unpaid.commissionDueSyp,
        };
      }),
    );
    const open = merchants.filter((merchant) => merchant.status === "open");
    return {
      month: bounds.monthKey,
      merchants,
      openMerchantCount: open.length,
      totalSalesSyp: open.reduce((sum, m) => sum + m.totalSalesSyp, 0),
      totalCommissionSyp: open.reduce((sum, m) => sum + m.commissionDueSyp, 0),
    };
  }

  /// Settles every open merchant for one completed month. Each merchant runs
  /// in its own Serializable transaction, so one failure never undoes others.
  async runMonthlySettlement(adminUserId: string, dto: { month: string }) {
    const preview = await this.previewMonthlySettlement(dto);
    const bounds = parseCompletedMonth(dto.month, new Date());
    const candidates = preview.merchants.filter(
      (merchant) => merchant.status === "open",
    );
    const outcomes = await settleEachMerchant(candidates, (merchant) =>
      this.settleMonthForMerchant(merchant.storeId, bounds, adminUserId),
    );
    return { month: bounds.monthKey, ...summarizeOutcomes(outcomes), merchants: outcomes };
  }

  private async settleMonthForMerchant(
    storeId: string,
    bounds: MonthBounds,
    adminUserId: string,
  ): Promise<"settled" | "skipped"> {
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          const unpaid = await this.unpaidForMonth(tx, storeId, bounds);
          if (unpaid.alreadySettled || unpaid.transactionCount === 0) {
            return "skipped";
          }
          await tx.merchantSettlement.create({
            data: {
              storeId,
              kind: SettlementKind.MONTHLY,
              periodStart: bounds.periodStart,
              periodEnd: bounds.periodEnd,
              transactionCount: unpaid.transactionCount,
              totalSalesSyp: BigInt(unpaid.totalSalesSyp),
              commissionDueSyp: BigInt(unpaid.commissionDueSyp),
              status: SettlementStatus.SETTLED,
              settledAt: new Date(),
              settledByUserId: adminUserId,
            },
          });
          return "settled";
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      // A concurrent run already created this month's row (unique key).
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === "P2002"
      ) {
        return "skipped";
      }
      throw error;
    }
  }

  async listMonthlySettlementHistory() {
    const rows = await this.prisma.merchantSettlement.findMany({
      where: { kind: SettlementKind.MONTHLY },
      orderBy: { periodStart: "desc" },
      take: 120,
      include: { store: { select: { name: true } } },
    });
    return {
      items: rows.map((row) => ({
        id: row.id,
        storeId: row.storeId,
        storeName: row.store.name,
        month: row.periodStart.toISOString().slice(0, 7),
        transactionCount: row.transactionCount,
        totalSalesSyp: toNumber(row.totalSalesSyp),
        commissionDueSyp: toNumber(row.commissionDueSyp),
        settledAt: row.settledAt?.toISOString() ?? null,
      })),
    };
  }

  async listSettlements(query: SettlementQueryDto) {
    const { periodStart, periodEnd } = this.periodBounds(query);
    const hasExplicitPeriod = Boolean(query.periodStart || query.periodEnd);
    const stores = await this.prisma.store.findMany({
      orderBy: { name: "asc" },
    });
    // Explicit-period (historical) queries keep the original calendar-bounded
    // lookup — entirely unaffected by the cycle-based status fix below.
    const explicitSettlements = hasExplicitPeriod
      ? await this.prisma.merchantSettlement.findMany({
          where: { periodStart, periodEnd },
        })
      : [];
    const explicitSettlementByStore = new Map(
      explicitSettlements.map((item) => [item.storeId, item]),
    );

    const items = await Promise.all(
      stores.map(async (store) => {
        if (hasExplicitPeriod) {
          const existing = explicitSettlementByStore.get(store.id);
          const aggregate = await this.prisma.loyaltyTransaction.aggregate({
            where: {
              storeId: store.id,
              createdAt: { gte: periodStart, lt: periodEnd },
            },
            _count: { id: true },
            _sum: { amountSyp: true, commissionAmountSyp: true },
          });
          return {
            id: existing?.id ?? null,
            storeId: store.id,
            storeName: store.name,
            periodStart: periodStart.toISOString(),
            periodEnd: periodEnd.toISOString(),
            transactionCount: aggregate._count.id,
            totalSalesSyp: toNumber(aggregate._sum.amountSyp ?? 0n),
            commissionDueSyp: toNumber(
              aggregate._sum.commissionAmountSyp ?? 0n,
            ),
            status: (existing?.status ?? SettlementStatus.OPEN).toLowerCase(),
            settledAt: existing?.settledAt?.toISOString() ?? null,
          };
        }

        // Default ("current") view: the cycle boundary is the store's real
        // accounting history — the latest SETTLED row's settledAt instant —
        // never a calendar month. A store reports SETTLED only when nothing
        // new has happened since that instant; any new transaction, even
        // seconds later on the same calendar day, reopens it (OPEN)
        // immediately — there is no "once per day" restriction anywhere.
        const latest = await this.latestSettlement(store.id);
        const cycleStart = latest?.settledAt;
        const aggregate = await this.prisma.loyaltyTransaction.aggregate({
          where: {
            storeId: store.id,
            createdAt: cycleStart ? { gte: cycleStart } : undefined,
            AND: await this.monthlyExclusions(store.id),
          },
          _count: { id: true },
          _sum: { amountSyp: true, commissionAmountSyp: true },
        });
        const hasPending = aggregate._count.id > 0;

        return {
          id: hasPending ? null : (latest?.id ?? null),
          storeId: store.id,
          storeName: store.name,
          periodStart: periodStart.toISOString(),
          periodEnd: periodEnd.toISOString(),
          transactionCount: aggregate._count.id,
          totalSalesSyp: toNumber(aggregate._sum.amountSyp ?? 0n),
          commissionDueSyp: toNumber(aggregate._sum.commissionAmountSyp ?? 0n),
          status: (
            hasPending || !latest
              ? SettlementStatus.OPEN
              : SettlementStatus.SETTLED
          ).toLowerCase(),
          settledAt: hasPending
            ? null
            : (latest?.settledAt?.toISOString() ?? null),
        };
      }),
    );

    return { items };
  }

  async settleStore(adminUserId: string, dto: SettleStoreDto) {
    const store = await this.prisma.store.findUnique({
      where: { id: dto.storeId },
      select: { name: true, createdAt: true },
    });
    if (!store) throw new NotFoundException("Store was not found.");

    // Cycle boundaries are derived entirely server-side. The calendar
    // periodStart/periodEnd supplied by the Admin client are accepted for
    // API-shape compatibility but are never used as settlement history
    // identity — two genuinely distinct cycles can fall on the same
    // calendar day, and the client's value must not decide that.
    const latest = await this.latestSettlement(dto.storeId);
    const cycleStart = latest?.settledAt;
    // `now` is captured once and used as this settlement's periodEnd,
    // settledAt, AND the exclusive upper bound of the aggregate below — so a
    // transaction created at/after this instant can never be counted in
    // this settlement, and is guaranteed to be picked up by the NEXT cycle
    // instead (whose lower bound is this same instant). Every transaction
    // therefore belongs to exactly one cycle, with no overlap and no gap at
    // the T1/T2 boundary.
    const now = new Date();
    const aggregate = await this.prisma.loyaltyTransaction.aggregate({
      where: {
        storeId: dto.storeId,
        createdAt: cycleStart ? { gte: cycleStart, lt: now } : { lt: now },
        AND: await this.monthlyExclusions(dto.storeId),
      },
      _count: { id: true },
      _sum: {
        amountSyp: true,
        commissionAmountSyp: true,
      },
    });

    if (aggregate._count.id === 0) {
      // Nothing new to settle. Never create a zero-value row: if the store
      // has already been settled and nothing has happened since, hand back
      // that last real settlement unchanged; if it has never had anything
      // to settle at all, fail cleanly instead of fabricating a row.
      if (!latest) {
        throw new BadRequestException(
          "There are no transactions to settle for this store.",
        );
      }
      return {
        id: latest.id,
        storeId: latest.storeId,
        storeName: store.name,
        periodStart: latest.periodStart.toISOString(),
        periodEnd: latest.periodEnd.toISOString(),
        transactionCount: latest.transactionCount,
        totalSalesSyp: toNumber(latest.totalSalesSyp),
        commissionDueSyp: toNumber(latest.commissionDueSyp),
        status: latest.status.toLowerCase(),
        settledAt: latest.settledAt?.toISOString() ?? null,
      };
    }

    // A real, new cycle: always CREATE a new row. Every settlement is an
    // immutable, permanent record — a later settlement must never
    // update/overwrite an earlier one.
    const settlement = await this.prisma.merchantSettlement.create({
      data: {
        storeId: dto.storeId,
        periodStart: cycleStart ?? store.createdAt,
        periodEnd: now,
        transactionCount: aggregate._count.id,
        totalSalesSyp: aggregate._sum.amountSyp ?? 0n,
        commissionDueSyp: aggregate._sum.commissionAmountSyp ?? 0n,
        status: SettlementStatus.SETTLED,
        settledByUserId: adminUserId,
        settledAt: now,
      },
    });

    return {
      id: settlement.id,
      storeId: settlement.storeId,
      storeName: store.name,
      periodStart: settlement.periodStart.toISOString(),
      periodEnd: settlement.periodEnd.toISOString(),
      transactionCount: settlement.transactionCount,
      totalSalesSyp: toNumber(settlement.totalSalesSyp),
      commissionDueSyp: toNumber(settlement.commissionDueSyp),
      status: settlement.status.toLowerCase(),
      settledAt: settlement.settledAt?.toISOString() ?? null,
    };
  }

  private async adjustPoints(
    _adminUserId: string,
    customerId: string,
    dto: AdjustCustomerPointsDto,
    signedPoints: number,
  ) {
    const updated = await this.prisma.$transaction(
      async (tx) => {
        const customer = await tx.customerProfile.findUnique({
          where: { userId: customerId },
          select: { pointsBalance: true },
        });
        if (!customer) throw new NotFoundException("Customer was not found.");
        if (
          signedPoints < 0 &&
          customer.pointsBalance < BigInt(Math.abs(signedPoints))
        ) {
          throw new BadRequestException(
            "Customer does not have enough points.",
          );
        }

        const savedCustomer = await tx.customerProfile.update({
          where: { userId: customerId },
          data: { pointsBalance: { increment: BigInt(signedPoints) } },
          include: { user: true },
        });
        await tx.pointsLedgerEntry.create({
          data: {
            customerId,
            entryType:
              signedPoints >= 0
                ? PointsEntryType.ADMIN_GRANT
                : PointsEntryType.ADMIN_DEDUCT,
            pointsDelta: BigInt(signedPoints),
            balanceAfter: savedCustomer.pointsBalance,
            note: dto.note.trim(),
          },
        });
        return savedCustomer;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    return presentCustomer(updated);
  }

  private async assertExclusiveStoreSlot(
    city: string,
    category: string,
    exceptStoreId?: string,
  ): Promise<void> {
    const existing = await this.prisma.store.findFirst({
      where: {
        city: { equals: city.trim(), mode: "insensitive" },
        category: { equals: category.trim(), mode: "insensitive" },
        isActive: true,
        ...(exceptStoreId ? { id: { not: exceptStoreId } } : {}),
      },
    });
    if (existing) {
      throw new ConflictException(
        "An active exclusive store already exists for this city/category.",
      );
    }
  }

  private periodBounds(query: SettlementQueryDto): {
    periodStart: Date;
    periodEnd: Date;
  } {
    const now = new Date();
    const defaultStart = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
    );
    const defaultEnd = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1),
    );
    const periodStart = query.periodStart
      ? new Date(query.periodStart)
      : defaultStart;
    const periodEnd = query.periodEnd ? new Date(query.periodEnd) : defaultEnd;
    if (
      Number.isNaN(periodStart.getTime()) ||
      Number.isNaN(periodEnd.getTime()) ||
      periodEnd <= periodStart
    ) {
      throw new BadRequestException("Invalid settlement period.");
    }
    return { periodStart, periodEnd };
  }

  private generatePassword(): string {
    return randomInt(10000000, 99999999).toString();
  }
}
