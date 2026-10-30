import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { PointsEntryType, Prisma, SettlementStatus } from "@prisma/client";
import { createHmac } from "crypto";
import { PaginationQueryDto } from "../common/pagination.dto";
import {
  presentCustomer,
  presentMerchantAccount,
  presentStore,
  presentTransaction,
  toNumber,
} from "../common/presenters";
import { LoyaltyCalculator } from "../loyalty/loyalty-calculator";
import { PrismaService } from "../prisma/prisma.service";
import {
  MerchantPeriodQueryDto,
  RegisterInvoiceDto,
  RegisterMerchantDeviceDto,
  ResolveCustomerQrDto,
} from "./dto/merchant.dto";

interface QrPayload {
  sub: string;
  aud?: string;
}

@Injectable()
export class MerchantService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async getWorkspace(userId: string) {
    const account = await this.getMerchantAccount(userId);
    const [transactions, summary] = await Promise.all([
      this.listTransactions(userId, { limit: 8 }),
      this.getSummary(userId, {}),
    ]);

    return {
      account: presentMerchantAccount(account),
      store: presentStore(account.store),
      summary,
      recentTransactions: transactions.items,
    };
  }

  async registerDevice(userId: string, dto: RegisterMerchantDeviceDto) {
    const account = await this.getMerchantAccount(userId);
    const fingerprintHash = this.hashDeviceFingerprint(dto.fingerprint);
    const device = await this.prisma.merchantDevice.upsert({
      where: {
        merchantAccountId_deviceFingerprintHash: {
          merchantAccountId: account.id,
          deviceFingerprintHash: fingerprintHash,
        },
      },
      update: {
        deviceLabel: dto.label.trim(),
        lastLoginAt: new Date(),
      },
      create: {
        merchantAccountId: account.id,
        deviceLabel: dto.label.trim(),
        deviceFingerprintHash: fingerprintHash,
      },
    });

    return {
      id: device.id,
      label: device.deviceLabel,
      lastLoginAt: device.lastLoginAt.toISOString(),
    };
  }

  async resolveCustomerQr(dto: ResolveCustomerQrDto) {
    const customerId = await this.customerIdFromQr(dto.payload);
    const customer = await this.prisma.customerProfile.findUnique({
      where: { userId: customerId },
      include: { user: true },
    });
    if (!customer) throw new NotFoundException("Customer was not found.");
    return presentCustomer(customer);
  }

  async registerInvoice(userId: string, dto: RegisterInvoiceDto) {
    const customerId = await this.customerIdFromQr(dto.customerQrPayload);

    const transaction = await this.prisma.$transaction(
      async (tx) => {
        const existing = await tx.loyaltyTransaction.findUnique({
          where: { idempotencyKey: dto.idempotencyKey },
          include: { store: { select: { name: true } } },
        });
        if (existing) return existing;

        const account = await tx.merchantAccount.findFirst({
          where: { userId, isActive: true },
          include: { store: true },
        });
        if (!account)
          throw new ForbiddenException("Merchant account is not active.");
        if (!account.store.isActive)
          throw new ConflictException("Store is not active.");

        const customer = await tx.customerProfile.findUnique({
          where: { userId: customerId },
          select: { pointsBalance: true, pointRemainderSyp: true },
        });
        if (!customer) throw new NotFoundException("Customer was not found.");

        const settings = await tx.platformSettings.findUniqueOrThrow({
          where: { id: 1 },
        });
        const calculation = LoyaltyCalculator.calculate({
          invoiceAmountSyp: dto.amountSyp,
          commissionRate: Number(account.store.commissionRate),
          pointValueSyp: settings.pointValueSyp,
          carriedRemainderSyp: customer.pointRemainderSyp,
        });

        const saved = await tx.loyaltyTransaction.create({
          data: {
            storeId: account.storeId,
            customerId,
            merchantAccountId: account.id,
            amountSyp: BigInt(calculation.invoiceAmountSyp),
            commissionRateSnapshot: account.store.commissionRate,
            commissionAmountSyp: BigInt(calculation.commissionAmountSyp),
            platformRevenueSyp: BigInt(calculation.platformRevenueSyp),
            customerShareSyp: BigInt(calculation.customerShareSyp),
            pointValueSypSnapshot: calculation.pointValueSyp,
            customerPointsEarned: BigInt(calculation.customerPoints),
            idempotencyKey: dto.idempotencyKey,
          },
          include: { store: { select: { name: true } } },
        });

        const updatedCustomer = await tx.customerProfile.update({
          where: { userId: customerId },
          data: {
            pointsBalance: { increment: BigInt(calculation.customerPoints) },
            pointRemainderSyp: calculation.customerRemainderSyp,
          },
          select: { pointsBalance: true },
        });

        await tx.pointsLedgerEntry.create({
          data: {
            customerId,
            entryType: PointsEntryType.INVOICE_EARN,
            pointsDelta: BigInt(calculation.customerPoints),
            balanceAfter: updatedCustomer.pointsBalance,
            transactionId: saved.id,
            note: "Invoice cashback points earned.",
          },
        });

        return saved;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    return presentTransaction(transaction);
  }

  /// The start of this store's current unpaid accounting cycle: the
  /// `settledAt` instant of its most recent SETTLED settlement, or
  /// `undefined` if never settled (current cycle = its entire history).
  ///
  /// `settledAt` (not `periodEnd`) is used deliberately: `periodEnd` is a
  /// calendar-month boundary that can be in the future relative to the
  /// moment "تم التسديد" is actually clicked, so using it as the new cycle's
  /// start would wrongly exclude legitimate transactions made after
  /// settlement but before the calendar month ends. `settledAt` is the exact
  /// instant the settlement action occurred. Mirrors
  /// AdminService.currentCycleStart() so Admin and Merchant agree exactly.
  private async currentCycleStart(storeId: string): Promise<Date | undefined> {
    const last = await this.prisma.merchantSettlement.findFirst({
      where: { storeId, status: SettlementStatus.SETTLED },
      orderBy: { settledAt: "desc" },
    });
    return last?.settledAt ?? undefined;
  }

  async getSummary(userId: string, query: MerchantPeriodQueryDto) {
    const account = await this.getMerchantAccount(userId);
    const hasExplicitPeriod = Boolean(query.from || query.to);
    const { from, to } = this.periodBounds(query);

    // Explicit period query (historical browsing) keeps the original
    // calendar-bounded behavior. The default "current" view instead
    // aggregates from this store's own current-cycle start, so it resets to
    // 0/0/0 immediately after settlement and accumulates only new activity.
    const cycleStart = hasExplicitPeriod
      ? from
      : await this.currentCycleStart(account.storeId);
    const createdAt: Prisma.DateTimeFilter | undefined = hasExplicitPeriod
      ? { gte: from, lt: to }
      : cycleStart
        ? { gte: cycleStart }
        : undefined;

    const aggregate = await this.prisma.loyaltyTransaction.aggregate({
      where: { storeId: account.storeId, createdAt },
      _count: { id: true },
      _sum: {
        amountSyp: true,
        commissionAmountSyp: true,
      },
    });

    return {
      storeId: account.storeId,
      from: (cycleStart ?? from).toISOString(),
      to: to.toISOString(),
      transactionCount: aggregate._count.id,
      totalSalesSyp: toNumber(aggregate._sum.amountSyp ?? 0n),
      commissionDueSyp: toNumber(aggregate._sum.commissionAmountSyp ?? 0n),
    };
  }

  async listTransactions(userId: string, query: PaginationQueryDto) {
    const account = await this.getMerchantAccount(userId);
    const take = query.limit + 1;
    const transactions = await this.prisma.loyaltyTransaction.findMany({
      where: { storeId: account.storeId },
      include: {
        store: { select: { name: true } },
        customer: { select: { name: true } },
      },
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

  private async getMerchantAccount(userId: string) {
    const account = await this.prisma.merchantAccount.findFirst({
      where: { userId, isActive: true },
      include: {
        user: { select: { email: true } },
        store: true,
        _count: { select: { devices: true } },
      },
    });
    if (!account)
      throw new ForbiddenException("Merchant account is not active.");
    return account;
  }

  private async customerIdFromQr(payload: string): Promise<string> {
    let token: string | null = null;
    try {
      const parsed = new URL(payload);
      if (parsed.protocol !== "yallacash:" || parsed.hostname !== "customer") {
        throw new Error("Invalid QR scheme.");
      }
      token = parsed.searchParams.get("token");
    } catch {
      throw new BadRequestException("QR payload is invalid.");
    }

    if (!token) throw new BadRequestException("QR token is missing.");

    try {
      const decoded = await this.jwt.verifyAsync<QrPayload>(token, {
        secret: this.config.getOrThrow<string>("QR_TOKEN_SECRET"),
        audience: "merchant-scan",
      });
      return decoded.sub;
    } catch {
      throw new UnauthorizedException("QR token is invalid or expired.");
    }
  }

  private hashDeviceFingerprint(value: string): string {
    return createHmac("sha256", this.config.getOrThrow<string>("SECRET_PEPPER"))
      .update(value)
      .digest("hex");
  }

  private periodBounds(query: MerchantPeriodQueryDto): {
    from: Date;
    to: Date;
  } {
    const now = new Date();
    const defaultFrom = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
    );
    const defaultTo = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1),
    );
    const from = query.from ? new Date(query.from) : defaultFrom;
    const to = query.to ? new Date(query.to) : defaultTo;
    if (
      Number.isNaN(from.getTime()) ||
      Number.isNaN(to.getTime()) ||
      to <= from
    ) {
      throw new BadRequestException("Invalid reporting period.");
    }
    return { from, to };
  }
}
