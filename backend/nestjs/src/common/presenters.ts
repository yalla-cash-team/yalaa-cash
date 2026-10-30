import {
  AuthMethod,
  Banner,
  BannerPlacement,
  CashRequestStatus,
  DigitalProduct,
  Governorate,
  LoyaltyTransaction,
  MerchantAccount,
  ProductRedemption,
  Store,
  User,
} from "@prisma/client";

type CustomerWithUser = {
  userId: string;
  name: string;
  governorate: string;
  governorateId: string | null;
  pointsBalance: bigint;
  createdAt: Date;
  user: Pick<User, "phone" | "authMethod">;
};

type TransactionWithStore = LoyaltyTransaction & {
  store?: Pick<Store, "name"> | null;
  customer?: { name: string } | null;
};

type ProductRedemptionWithDetails = ProductRedemption & {
  customer?: { name: string; user?: Pick<User, "phone"> | null } | null;
  product?: Pick<DigitalProduct, "name"> | null;
};

type CashRequestWithCustomer = {
  id: string;
  customerId: string;
  pointsRequested: bigint;
  cashValueSyp: bigint;
  status: CashRequestStatus;
  createdAt: Date;
  settledAt: Date | null;
  customer?: { name: string } | null;
};

type MerchantAccountWithStore = MerchantAccount & {
  user?: Pick<User, "email"> | null;
  store?: Pick<Store, "name"> | null;
  _count?: { devices: number };
};

export function toNumber(value: bigint | number): number {
  return typeof value === "bigint" ? Number(value) : value;
}

export function presentAuthMethod(value?: AuthMethod | null): string {
  return value?.toLowerCase() ?? "phone";
}

export function presentCustomer(customer: CustomerWithUser) {
  return {
    id: customer.userId,
    name: customer.name,
    phone: customer.user.phone,
    authMethod: presentAuthMethod(customer.user.authMethod),
    governorate: customer.governorate,
    governorateId: customer.governorateId,
    pointsBalance: toNumber(customer.pointsBalance),
    createdAt: customer.createdAt.toISOString(),
  };
}

export function presentGovernorate(governorate: Governorate) {
  return {
    id: governorate.id,
    nameAr: governorate.nameAr,
    isActive: governorate.isActive,
    displayOrder: governorate.displayOrder,
    createdAt: governorate.createdAt.toISOString(),
    updatedAt: governorate.updatedAt.toISOString(),
  };
}

export function presentBanner(banner: Banner) {
  return {
    id: banner.id,
    title: banner.title,
    subtitle: banner.subtitle,
    // An uploaded image takes precedence over the URL the admin entered.
    imageUrl:
      banner.imageVersion > 0
        ? `/banners/${banner.id}/image?v=${banner.imageVersion}`
        : banner.imageUrl,
    targetUrl: banner.targetUrl,
    placement: banner.placement.toLowerCase(),
    style: banner.style.toLowerCase(),
    isActive: banner.isActive,
    displayOrder: banner.displayOrder,
    startsAt: banner.startsAt?.toISOString() ?? null,
    endsAt: banner.endsAt?.toISOString() ?? null,
    governorateId: banner.governorateId,
    createdAt: banner.createdAt.toISOString(),
    updatedAt: banner.updatedAt.toISOString(),
  };
}

export function presentStore(store: Store) {
  return {
    id: store.id,
    name: store.name,
    category: store.category,
    city: store.city,
    commissionRate: Number(store.commissionRate),
    description: store.description,
    location: store.location,
    imageUrl: store.imageUrl,
    // Relative to the API base URL; null until an admin uploads a logo.
    logoUrl:
      store.logoVersion > 0
        ? `/stores/${store.id}/logo?v=${store.logoVersion}`
        : null,
    iconSeed: store.iconSeed,
    isActive: store.isActive,
    governorateId: store.governorateId,
    createdAt: store.createdAt.toISOString(),
  };
}

export function presentTransaction(transaction: TransactionWithStore) {
  return {
    id: transaction.id,
    storeId: transaction.storeId,
    storeName: transaction.store?.name ?? "",
    customerId: transaction.customerId,
    customerName: transaction.customer?.name ?? "",
    amountSyp: toNumber(transaction.amountSyp),
    commissionRateSnapshot: Number(transaction.commissionRateSnapshot),
    commissionAmountSyp: toNumber(transaction.commissionAmountSyp),
    platformRevenueSyp: toNumber(transaction.platformRevenueSyp),
    customerShareSyp: toNumber(transaction.customerShareSyp),
    pointValueSypSnapshot: Number(transaction.pointValueSypSnapshot),
    customerPointsEarned: toNumber(transaction.customerPointsEarned),
    createdAt: transaction.createdAt.toISOString(),
  };
}

export function presentDigitalProduct(product: DigitalProduct) {
  return {
    id: product.id,
    name: product.name,
    costInPoints: toNumber(product.costInPoints),
    // An uploaded image takes precedence over the legacy imageUrl text.
    imageUrl:
      product.imageVersion > 0
        ? `/digital-products/${product.id}/image?v=${product.imageVersion}`
        : product.imageUrl,
    iconSeed: product.iconSeed,
    requiresPhoneNumber: product.requiresPhoneNumber,
    isActive: product.isActive,
    createdAt: product.createdAt.toISOString(),
  };
}

export function presentCashRequest(request: CashRequestWithCustomer) {
  return {
    id: request.id,
    customerId: request.customerId,
    customerName: request.customer?.name,
    pointsRequested: toNumber(request.pointsRequested),
    cashValueSyp: toNumber(request.cashValueSyp),
    status: request.status.toLowerCase(),
    createdAt: request.createdAt.toISOString(),
    settledAt: request.settledAt?.toISOString() ?? null,
  };
}

export function presentProductRedemption(
  redemption: ProductRedemptionWithDetails,
) {
  return {
    id: redemption.id,
    customerId: redemption.customerId,
    customerName: redemption.customer?.name,
    customerPhone: redemption.customer?.user?.phone,
    productId: redemption.productId,
    productName: redemption.product?.name,
    pointsCostSnapshot: toNumber(redemption.pointsCostSnapshot),
    phoneNumber: redemption.phoneNumber,
    status: redemption.status.toLowerCase(),
    fulfilledAt: redemption.fulfilledAt?.toISOString() ?? null,
    createdAt: redemption.createdAt.toISOString(),
  };
}

export function presentMerchantAccount(account: MerchantAccountWithStore) {
  return {
    id: account.id,
    storeId: account.storeId,
    storeName: account.store?.name,
    email: account.user?.email,
    displayLabel: account.displayLabel,
    isActive: account.isActive,
    deviceCount: account._count?.devices ?? 0,
    createdAt: account.createdAt.toISOString(),
  };
}
