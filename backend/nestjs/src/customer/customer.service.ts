import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import {
  BannerPlacement,
  CashRequestStatus,
  PointsEntryType,
  Prisma,
  RedemptionStatus,
} from "@prisma/client";
import { randomUUID } from "crypto";
import {
  PaginatedResponse,
  PaginationQueryDto,
} from "../common/pagination.dto";
import { FcmService } from "../notifications/fcm.service";
import { LoyaltyCalculator } from "../loyalty/loyalty-calculator";
import { decideShareReward } from "./share-reward";
import {
  presentBanner,
  presentCashRequest,
  presentCustomer,
  presentDigitalProduct,
  presentGovernorate,
  presentProductRedemption,
  presentTransaction,
  toNumber,
} from "../common/presenters";
import { PrismaService } from "../prisma/prisma.service";
import {
  RedeemDigitalProductDto,
  RegisterDeviceTokenDto,
  RequestCashRedemptionDto,
  UpdateCustomerGovernorateDto,
  UpdateCustomerProfileDto,
} from "./dto/customer.dto";

@Injectable()
export class CustomerService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly fcm: FcmService,
  ) {}

  async getProfile(userId: string) {
    const customer = await this.prisma.customerProfile.findUnique({
      where: { userId },
      include: { user: true },
    });
    if (!customer)
      throw new NotFoundException("Customer profile was not found.");
    return presentCustomer(customer);
  }

  async updateProfile(userId: string, dto: UpdateCustomerProfileDto) {
    const updated = await this.prisma.customerProfile.update({
      where: { userId },
      data: {
        name: dto.name.trim(),
        governorate: dto.governorate.trim(),
        ...(dto.phone
          ? {
              user: {
                update: { phone: dto.phone.replace(/[^\d+]/g, "") },
              },
            }
          : {}),
      },
      include: { user: true },
    });
    return presentCustomer(updated);
  }

  async listActiveGovernorates() {
    const items = await this.prisma.governorate.findMany({
      where: { isActive: true },
      orderBy: [{ displayOrder: "asc" }, { nameAr: "asc" }],
    });
    return { items: items.map(presentGovernorate) };
  }

  async updateGovernorate(userId: string, dto: UpdateCustomerGovernorateDto) {
    const governorate = await this.prisma.governorate.findFirst({
      where: { id: dto.governorateId, isActive: true },
    });
    if (!governorate)
      throw new BadRequestException(
        "Governorate is not active or does not exist.",
      );

    const updated = await this.prisma.customerProfile.update({
      where: { userId },
      data: {
        governorateId: governorate.id,
        governorate: governorate.nameAr,
      },
      include: { user: true },
    });
    return presentCustomer(updated);
  }

  /// Grants the configured share reward once per customer account. The
  /// claim row's primary key and the Serializable transaction together stop
  /// duplicate grants, including concurrent requests.
  async claimShareReward(userId: string) {
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          const settings = await tx.platformSettings.findUniqueOrThrow({
            where: { id: 1 },
          });
          const customer = await tx.customerProfile.findUnique({
            where: { userId },
            select: { pointsBalance: true },
          });
          if (!customer) throw new NotFoundException("Customer was not found.");

          const existing = await tx.shareRewardClaim.findUnique({
            where: { customerId: userId },
          });
          const decision = decideShareReward(
            settings.shareRewardPoints,
            existing !== null,
          );
          if (decision !== "granted") {
            return {
              status: decision,
              pointsAwarded: 0,
              pointsBalance: Number(customer.pointsBalance),
            };
          }

          const rewardPoints = settings.shareRewardPoints;
          await tx.shareRewardClaim.create({
            data: { customerId: userId, pointsAwarded: rewardPoints },
          });
          const updated = await tx.customerProfile.update({
            where: { userId },
            data: { pointsBalance: { increment: rewardPoints } },
            select: { pointsBalance: true },
          });
          await tx.pointsLedgerEntry.create({
            data: {
              customerId: userId,
              entryType: PointsEntryType.SHARE_REWARD,
              pointsDelta: rewardPoints,
              balanceAfter: updated.pointsBalance,
              note: "Share app reward.",
            },
          });
          return {
            status: decision,
            pointsAwarded: Number(rewardPoints),
            pointsBalance: Number(updated.pointsBalance),
          };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError) {
        // A concurrent claim won the race and the primary key rejected this one.
        if (error.code === "P2002") {
          const customer = await this.prisma.customerProfile.findUnique({
            where: { userId },
            select: { pointsBalance: true },
          });
          return {
            status: "already_claimed" as const,
            pointsAwarded: 0,
            pointsBalance: Number(customer?.pointsBalance ?? 0),
          };
        }
        // Serialization failure: the caller can safely retry.
        if (error.code === "P2034") {
          throw new ConflictException("Please try the share reward again.");
        }
      }
      throw error;
    }
  }

  async getDigitalProductImage(productId: string) {
    const image = await this.prisma.digitalProductImage.findUnique({
      where: { productId },
    });
    if (!image) throw new NotFoundException("Product image was not found.");
    return image;
  }

  async getBannerImage(bannerId: string) {
    const image = await this.prisma.bannerImage.findUnique({
      where: { bannerId },
    });
    if (!image) throw new NotFoundException("Banner image was not found.");
    return image;
  }

  async getPoints(userId: string) {
    const customer = await this.prisma.customerProfile.findUnique({
      where: { userId },
      select: { pointsBalance: true },
    });
    if (!customer)
      throw new NotFoundException("Customer profile was not found.");
    const held = await this.pendingHeldPoints(userId);
    const balance = toNumber(customer.pointsBalance);
    return {
      pointsBalance: balance,
      heldPoints: held,
      availablePoints: balance - held,
    };
  }

  async issueQrToken(userId: string) {
    await this.ensureCustomer(userId);
    const ttl = this.config.get<number>("QR_TOKEN_TTL_SECONDS", 120);
    const token = await this.jwt.signAsync(
      { sub: userId, jti: randomUUID(), aud: "merchant-scan" },
      {
        secret: this.config.getOrThrow<string>("QR_TOKEN_SECRET"),
        expiresIn: ttl,
      },
    );

    return {
      token,
      payload: `yallacash://customer/${userId}?v=2&token=${encodeURIComponent(token)}`,
      expiresAt: new Date(Date.now() + ttl * 1000).toISOString(),
    };
  }

  async removeDeviceToken(userId: string, dto: RegisterDeviceTokenDto) {
    await this.prisma.deviceToken.deleteMany({
      where: { token: dto.token, userId },
    });
    return { success: true };
  }

  async registerDeviceToken(userId: string, dto: RegisterDeviceTokenDto) {
    await this.prisma.deviceToken.upsert({
      where: { token: dto.token },
      update: { userId },
      create: { userId, token: dto.token },
    });
    return { success: true };
  }

  async listTransactions(
    userId: string,
    query: PaginationQueryDto,
  ): Promise<PaginatedResponse<ReturnType<typeof presentTransaction>>> {
    const take = query.limit + 1;
    const transactions = await this.prisma.loyaltyTransaction.findMany({
      where: { customerId: userId },
      include: { store: { select: { name: true } } },
      orderBy: { createdAt: "desc" },
      take,
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
    });
    const hasNext = transactions.length > query.limit;
    const items = transactions.slice(0, query.limit);
    return {
      items: items.map(presentTransaction),
      nextCursor: hasNext ? (items[items.length - 1]?.id ?? null) : null,
    };
  }

  async listDigitalProducts() {
    const products = await this.prisma.digitalProduct.findMany({
      where: { isActive: true },
      orderBy: [{ costInPoints: "asc" }, { name: "asc" }],
    });
    return { items: products.map(presentDigitalProduct) };
  }

  async listActiveBanners(userId: string, placement: string = "HOME") {
    const customer = await this.prisma.customerProfile.findUnique({
      where: { userId },
      select: { governorateId: true },
    });
    if (!customer)
      throw new NotFoundException("Customer profile was not found.");

    const bannerPlacement = placement.toUpperCase() as BannerPlacement;
    const now = new Date();
    const governorateScope: Prisma.BannerWhereInput[] = [
      { governorateId: null },
    ];
    if (customer.governorateId) {
      governorateScope.push({ governorateId: customer.governorateId });
    }
    const items = await this.prisma.banner.findMany({
      where: {
        placement: bannerPlacement,
        isActive: true,
        OR: governorateScope,
        AND: [
          { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
          { OR: [{ endsAt: null }, { endsAt: { gte: now } }] },
        ],
      },
      orderBy: [{ displayOrder: "asc" }, { createdAt: "desc" }],
    });

    return { items: items.map(presentBanner) };
  }

  async listCashRequests(userId: string) {
    const requests = await this.prisma.cashRedemptionRequest.findMany({
      where: { customerId: userId },
      orderBy: { createdAt: "desc" },
    });
    return { items: requests.map(presentCashRequest) };
  }

  // Read-only history for the authenticated customer only — customerId is
  // always taken from the verified JWT (userId), never accepted from the
  // caller, so a customer can never list another customer's redemptions.
  async listProductRedemptions(userId: string) {
    const redemptions = await this.prisma.productRedemption.findMany({
      where: { customerId: userId },
      include: { product: { select: { name: true } } },
      orderBy: { createdAt: "desc" },
    });
    return { items: redemptions.map(presentProductRedemption) };
  }

  async requestCashRedemption(userId: string, dto: RequestCashRedemptionDto) {
    const points = BigInt(dto.points);
    const request = await this.prisma.$transaction(
      async (tx) => {
        const customer = await tx.customerProfile.findUnique({
          where: { userId },
          select: { pointsBalance: true },
        });
        if (!customer)
          throw new NotFoundException("Customer profile was not found.");

        const existingPending = await tx.cashRedemptionRequest.findFirst({
          where: { customerId: userId, status: CashRequestStatus.PENDING },
        });
        if (existingPending) {
          throw new ConflictException(
            "Customer already has a pending cash request.",
          );
        }

        const held = await this.pendingHeldPoints(userId, tx);
        const available = customer.pointsBalance - BigInt(held);
        if (points > available)
          throw new BadRequestException("Insufficient available points.");

        const settings = await tx.platformSettings.findUniqueOrThrow({
          where: { id: 1 },
        });
        if (!LoyaltyCalculator.isWholeCashValue(Number(points), settings.pointValueSyp))
          throw new BadRequestException(
            "Choose a point amount that converts to whole SYP.",
          );

        const saved = await tx.cashRedemptionRequest.create({
          data: {
            customerId: userId,
            pointsRequested: points,
            pointValueSypSnapshot: settings.pointValueSyp,
            cashValueSyp: BigInt(
              LoyaltyCalculator.cashValueFor(
                Number(points),
                settings.pointValueSyp,
              ),
            ),
          },
        });

        await tx.pointsLedgerEntry.create({
          data: {
            customerId: userId,
            entryType: PointsEntryType.CASH_RESERVE,
            pointsDelta: 0,
            balanceAfter: customer.pointsBalance,
            referenceId: saved.id,
            note: "Cash redemption points reserved.",
          },
        });
        return saved;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    // Fire-and-forget: FcmService.sendToUser never rejects, but this .catch
    // is a deliberate backstop so a push notification can never turn into
    // an unhandled promise rejection here, no matter what changes later.
    void this.fcm
      .sendToUser(userId, {
        title: "طلبك قيد المعالجة",
        body: "استلمنا طلب استبدال النقاط بكاش وهو الآن قيد المعالجة.",
      })
      .catch(() => undefined);

    return presentCashRequest(request);
  }

  /**
   * Creates a PENDING request only — points are not deducted here. They are
   * deducted exactly once, by the admin resolver, when the request is
   * FULFILLED (mirrors requestCashRedemption's reserve-without-deduct
   * pattern so a customer can't over-request across both request types at
   * once; see pendingHeldPoints).
   */
  async redeemDigitalProduct(userId: string, dto: RedeemDigitalProductDto) {
    const redemption = await this.prisma.$transaction(
      async (tx) => {
        const product = await tx.digitalProduct.findUnique({
          where: { id: dto.productId },
        });
        if (!product?.isActive)
          throw new NotFoundException("Digital product is not available.");
        if (
          product.requiresPhoneNumber &&
          (dto.phoneNumber?.trim().length ?? 0) < 8
        ) {
          throw new BadRequestException(
            "Phone number is required for this product.",
          );
        }

        const customer = await tx.customerProfile.findUnique({
          where: { userId },
          select: { pointsBalance: true },
        });
        if (!customer)
          throw new NotFoundException("Customer profile was not found.");

        // Same customer + same product: an existing PENDING request blocks
        // a second one (prevents a rapid double-tap or a direct duplicate
        // API call from creating two active requests for the same
        // product). A past FULFILLED or REJECTED request never blocks a
        // new one — the same product can be redeemed again over time.
        // Checked inside this SERIALIZABLE transaction so two genuinely
        // concurrent submissions can't both observe "no pending row yet"
        // and both succeed — Postgres will force one to serialize after
        // the other, at which point it sees the row the first one created.
        const existingPending = await tx.productRedemption.findFirst({
          where: {
            customerId: userId,
            productId: dto.productId,
            status: RedemptionStatus.PENDING,
          },
          select: { id: true },
        });
        if (existingPending) {
          throw new ConflictException(
            "A pending redemption request already exists for this product.",
          );
        }

        const held = await this.pendingHeldPoints(userId, tx);
        const available = customer.pointsBalance - BigInt(held);
        if (product.costInPoints > available) {
          throw new BadRequestException("Insufficient available points.");
        }

        const saved = await tx.productRedemption.create({
          data: {
            customerId: userId,
            productId: product.id,
            pointsCostSnapshot: product.costInPoints,
            phoneNumber: dto.phoneNumber?.trim() || null,
          },
        });

        await tx.pointsLedgerEntry.create({
          data: {
            customerId: userId,
            entryType: PointsEntryType.PRODUCT_RESERVE,
            pointsDelta: 0,
            balanceAfter: customer.pointsBalance,
            referenceId: saved.id,
            note: "Digital product redemption points reserved.",
          },
        });

        return saved;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    void this.fcm
      .sendToUser(userId, {
        title: "طلبك قيد المراجعة",
        body: "استلمنا طلب استبدال المنتج الرقمي وهو الآن قيد المراجعة.",
      })
      .catch(() => undefined);

    return presentProductRedemption(redemption);
  }

  private async ensureCustomer(userId: string): Promise<void> {
    const exists = await this.prisma.customerProfile.count({
      where: { userId },
    });
    if (!exists) throw new NotFoundException("Customer profile was not found.");
  }

  private async pendingHeldPoints(
    userId: string,
    prisma: Pick<
      PrismaService,
      "cashRedemptionRequest" | "productRedemption"
    > = this.prisma,
  ): Promise<number> {
    const [cash, products] = await Promise.all([
      prisma.cashRedemptionRequest.aggregate({
        where: { customerId: userId, status: CashRequestStatus.PENDING },
        _sum: { pointsRequested: true },
      }),
      prisma.productRedemption.aggregate({
        where: { customerId: userId, status: RedemptionStatus.PENDING },
        _sum: { pointsCostSnapshot: true },
      }),
    ]);
    return (
      toNumber(cash._sum.pointsRequested ?? 0n) +
      toNumber(products._sum.pointsCostSnapshot ?? 0n)
    );
  }
}
