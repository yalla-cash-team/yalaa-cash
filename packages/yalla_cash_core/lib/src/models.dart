enum AuthMethod { facebook, gmail, phone }

enum CashRequestStatus { pending, settled, rejected }

enum RedemptionStatus { pending, fulfilled, rejected }

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.governorate,
    required this.pointsBalance,
    required this.createdAt,
    this.phone,
    this.governorateId,
    this.authMethod = AuthMethod.phone,
  });

  final String id;
  final String name;
  final String? phone;
  final String? governorateId;
  final AuthMethod authMethod;
  final String governorate;
  final int pointsBalance;
  final DateTime createdAt;

  Customer copyWith(
          {int? pointsBalance, String? governorateId, String? governorate}) =>
      Customer(
        id: id,
        name: name,
        phone: phone,
        authMethod: authMethod,
        governorate: governorate ?? this.governorate,
        governorateId: governorateId ?? this.governorateId,
        pointsBalance: pointsBalance ?? this.pointsBalance,
        createdAt: createdAt,
      );
}

class Governorate {
  const Governorate({
    required this.id,
    required this.nameAr,
    required this.isActive,
    required this.displayOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String nameAr;
  final bool isActive;
  final int displayOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  Governorate copyWith({String? nameAr, bool? isActive, int? displayOrder}) =>
      Governorate(
        id: id,
        nameAr: nameAr ?? this.nameAr,
        isActive: isActive ?? this.isActive,
        displayOrder: displayOrder ?? this.displayOrder,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class Banner {
  const Banner({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.subtitle,
    this.targetUrl,
    this.placement = 'home',
    this.style = 'promo',
    this.isActive = true,
    this.displayOrder = 0,
    this.governorateId,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String imageUrl;
  final String? targetUrl;
  final String placement;
  final String style;
  final bool isActive;
  final int displayOrder;
  final String? governorateId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Banner copyWith({
    String? title,
    String? subtitle,
    String? imageUrl,
    String? targetUrl,
    String? placement,
    String? style,
    bool? isActive,
    int? displayOrder,
    String? governorateId,
    DateTime? startsAt,
    DateTime? endsAt,
  }) =>
      Banner(
        id: id,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        imageUrl: imageUrl ?? this.imageUrl,
        targetUrl: targetUrl ?? this.targetUrl,
        placement: placement ?? this.placement,
        style: style ?? this.style,
        isActive: isActive ?? this.isActive,
        displayOrder: displayOrder ?? this.displayOrder,
        governorateId: governorateId ?? this.governorateId,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// One admin push broadcast and its delivery result, as recorded by the server.
class NotificationBroadcast {
  const NotificationBroadcast({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.recipientCount,
    required this.sentCount,
    required this.failedCount,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;

  /// One of PENDING, SENT, PARTIAL or FAILED.
  final String status;
  final int recipientCount;
  final int sentCount;
  final int failedCount;
  final DateTime? createdAt;
}

/// Outcome of a share-reward claim as decided by the server.
class ShareRewardResult {
  const ShareRewardResult({
    required this.status,
    required this.pointsAwarded,
    required this.pointsBalance,
  });

  /// One of 'granted', 'already_claimed' or 'disabled'.
  final String status;
  final int pointsAwarded;
  final int pointsBalance;

  bool get granted => status == 'granted';
}

/// One merchant's status for a calendar month: settled, open or none.
class MonthlyMerchantStatus {
  const MonthlyMerchantStatus({
    required this.storeId,
    required this.storeName,
    required this.status,
    required this.transactionCount,
    required this.totalSalesSyp,
    required this.commissionDueSyp,
  });

  final String storeId;
  final String storeName;
  final String status;
  final int transactionCount;
  final int totalSalesSyp;
  final int commissionDueSyp;
}

/// Preview of a monthly settlement; nothing is changed until it is confirmed.
class MonthlySettlementPreview {
  const MonthlySettlementPreview({
    required this.month,
    required this.merchants,
    required this.openMerchantCount,
    required this.totalSalesSyp,
    required this.totalCommissionSyp,
  });

  final String month;
  final List<MonthlyMerchantStatus> merchants;
  final int openMerchantCount;
  final int totalSalesSyp;
  final int totalCommissionSyp;
}

/// Result for one merchant after a monthly run.
class MonthlyMerchantOutcome {
  const MonthlyMerchantOutcome({
    required this.storeName,
    required this.status,
    required this.commissionDueSyp,
    this.error,
  });

  final String storeName;

  /// settled, skipped or failed.
  final String status;
  final int commissionDueSyp;
  final String? error;
}

class MonthlySettlementRunResult {
  const MonthlySettlementRunResult({
    required this.month,
    required this.settledCount,
    required this.skippedCount,
    required this.failedCount,
    required this.totalCommissionSyp,
    required this.merchants,
  });

  final String month;
  final int settledCount;
  final int skippedCount;
  final int failedCount;
  final int totalCommissionSyp;
  final List<MonthlyMerchantOutcome> merchants;
}

/// A stored monthly settlement, shown in the history.
class MonthlySettlementRecord {
  const MonthlySettlementRecord({
    required this.storeName,
    required this.month,
    required this.transactionCount,
    required this.totalSalesSyp,
    required this.commissionDueSyp,
    this.settledAt,
  });

  final String storeName;
  final String month;
  final int transactionCount;
  final int totalSalesSyp;
  final int commissionDueSyp;
  final DateTime? settledAt;
}

/// A logo image picked by an admin, validated server-side as well.
class StoreLogoUpload {
  const StoreLogoUpload({required this.bytes, required this.contentType});

  final List<int> bytes;

  /// One of image/png, image/jpeg or image/webp.
  final String contentType;
}

class PartnerStore {
  const PartnerStore({
    required this.id,
    required this.name,
    required this.category,
    required this.commissionRate,
    required this.description,
    required this.location,
    required this.iconSeed,
    required this.governorateId,
    this.isActive = true,
    this.logoUrl,
  });

  final String id;
  final String name;
  final String category;
  final double commissionRate;
  final String description;
  final String location;
  final int iconSeed;
  final String governorateId;
  final bool isActive;

  /// Absolute URL of the uploaded logo, or null when the store has none.
  final String? logoUrl;

  PartnerStore copyWith({
    String? name,
    String? category,
    double? commissionRate,
    String? description,
    String? location,
    int? iconSeed,
    String? governorateId,
    bool? isActive,
  }) =>
      PartnerStore(
        id: id,
        logoUrl: logoUrl,
        name: name ?? this.name,
        category: category ?? this.category,
        commissionRate: commissionRate ?? this.commissionRate,
        description: description ?? this.description,
        location: location ?? this.location,
        iconSeed: iconSeed ?? this.iconSeed,
        governorateId: governorateId ?? this.governorateId,
        isActive: isActive ?? this.isActive,
      );
}

class LoyaltyTransaction {
  const LoyaltyTransaction({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.customerId,
    required this.amountSyp,
    required this.commissionRateSnapshot,
    required this.commissionAmountSyp,
    required this.platformRevenueSyp,
    required this.customerShareSyp,
    required this.customerPointsEarned,
    required this.createdAt,
    this.customerName,
  });

  final String id;
  final String storeId;
  final String storeName;
  final String customerId;
  final String? customerName;
  final int amountSyp;
  final double commissionRateSnapshot;
  final int commissionAmountSyp;
  final int platformRevenueSyp;
  final int customerShareSyp;
  final int customerPointsEarned;
  final DateTime createdAt;
}

class DigitalProduct {
  const DigitalProduct({
    required this.id,
    required this.name,
    required this.costInPoints,
    required this.iconSeed,
    this.requiresPhoneNumber = false,
    this.isActive = true,
    this.imageUrl,
  });

  final String id;
  final String name;
  final int costInPoints;
  final int iconSeed;
  final bool requiresPhoneNumber;
  final bool isActive;

  /// Absolute image URL, or null when the product has no image.
  final String? imageUrl;

  DigitalProduct copyWith({
    String? name,
    int? costInPoints,
    int? iconSeed,
    bool? requiresPhoneNumber,
    bool? isActive,
  }) =>
      DigitalProduct(
        id: id,
        imageUrl: imageUrl,
        name: name ?? this.name,
        costInPoints: costInPoints ?? this.costInPoints,
        iconSeed: iconSeed ?? this.iconSeed,
        requiresPhoneNumber: requiresPhoneNumber ?? this.requiresPhoneNumber,
        isActive: isActive ?? this.isActive,
      );
}

class CashRedemptionRequest {
  const CashRedemptionRequest({
    required this.id,
    required this.customerId,
    required this.pointsRequested,
    required this.cashValueSyp,
    required this.status,
    required this.createdAt,
    this.settledAt,
  });

  final String id;
  final String customerId;
  final int pointsRequested;
  final int cashValueSyp;
  final CashRequestStatus status;
  final DateTime createdAt;
  final DateTime? settledAt;
}

class ProductRedemption {
  const ProductRedemption({
    required this.id,
    required this.customerId,
    required this.productId,
    required this.pointsCostSnapshot,
    required this.status,
    required this.createdAt,
    this.customerName,
    this.customerPhone,
    this.productName,
    this.phoneNumber,
    this.fulfilledAt,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final String? customerPhone;
  final String productId;
  final String? productName;
  final int pointsCostSnapshot;
  final String? phoneNumber;
  final RedemptionStatus status;
  final DateTime createdAt;
  final DateTime? fulfilledAt;
}

class MerchantAccount {
  const MerchantAccount({
    required this.id,
    required this.storeId,
    required this.email,
    required this.demoPassword,
    this.deviceCount = 0,
  });

  final String id;
  final String storeId;
  final String email;

  /// Demo-only. Production credentials must never be stored in the client.
  final String demoPassword;
  final int deviceCount;
}
