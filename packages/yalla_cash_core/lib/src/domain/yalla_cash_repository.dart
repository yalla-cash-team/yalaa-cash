import 'package:yalla_cash_core/src/customer_notifications.dart';
import 'package:yalla_cash_core/src/data/auth_token_store.dart';
import 'package:yalla_cash_core/src/models.dart';
import 'package:yalla_cash_core/src/store_offers.dart';

enum YallaUserRole { customer, merchant, admin }

enum LoadStatus { initial, loading, success, empty, failure }

class PhoneOtpChallenge {
  const PhoneOtpChallenge({
    required this.challengeId,
    required this.expiresInSeconds,
    this.devCode,
  });

  final String challengeId;
  final int expiresInSeconds;
  final String? devCode;
}

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.role,
    required this.tokens,
    this.customer,
  });

  final String userId;
  final YallaUserRole role;
  final AuthTokens tokens;
  final Customer? customer;
}

class PointsSummary {
  const PointsSummary({
    required this.pointsBalance,
    required this.heldPoints,
    required this.availablePoints,
  });

  final int pointsBalance;
  final int heldPoints;
  final int availablePoints;
}

class CustomerQrToken {
  const CustomerQrToken({
    required this.token,
    required this.payload,
    required this.expiresAt,
  });

  final String token;
  final String payload;
  final DateTime expiresAt;
}

class MerchantSummary {
  const MerchantSummary({
    required this.storeId,
    required this.from,
    required this.to,
    required this.transactionCount,
    required this.totalSalesSyp,
    required this.commissionDueSyp,
  });

  final String storeId;
  final DateTime from;
  final DateTime to;
  final int transactionCount;
  final int totalSalesSyp;
  final int commissionDueSyp;
}

class MerchantWorkspaceSnapshot {
  const MerchantWorkspaceSnapshot({
    required this.account,
    required this.store,
    required this.summary,
    required this.recentTransactions,
  });

  final MerchantAccount account;
  final PartnerStore store;
  final MerchantSummary summary;
  final List<LoyaltyTransaction> recentTransactions;
}

class AdminOverviewSnapshot {
  const AdminOverviewSnapshot({
    required this.customers,
    required this.activeStores,
    required this.transactions,
    required this.totalSalesSyp,
    required this.platformRevenueSyp,
    required this.commissionDueSyp,
    required this.pendingCashRequests,
  });

  final int customers;
  final int activeStores;
  final int transactions;
  final int totalSalesSyp;
  final int platformRevenueSyp;
  final int commissionDueSyp;
  final int pendingCashRequests;
}

class MerchantSettlementSummary {
  const MerchantSettlementSummary({
    required this.storeId,
    required this.storeName,
    required this.periodStart,
    required this.periodEnd,
    required this.transactionCount,
    required this.totalSalesSyp,
    required this.commissionDueSyp,
    required this.status,
    this.id,
    this.settledAt,
  });

  final String? id;
  final String storeId;
  final String storeName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int transactionCount;
  final int totalSalesSyp;
  final int commissionDueSyp;
  final String status;
  final DateTime? settledAt;
}

class IssuedMerchantAccount {
  const IssuedMerchantAccount({
    required this.account,
    required this.temporaryPassword,
  });

  final MerchantAccount account;
  final String temporaryPassword;
}

abstract class YallaCashRepository {
  Future<bool> hasSavedSession();

  Future<PhoneOtpChallenge> startCustomerPhoneOtp(String phone);

  Future<AuthSession> verifyCustomerPhoneOtp({
    required String challengeId,
    required String phone,
    required String code,
    required String name,
    required String governorate,
  });

  Future<AuthSession> signInCustomerWithOAuth({
    required AuthMethod provider,
    required String firebaseIdToken,
    required String name,
    required String governorate,
  });

  Future<AuthSession> signInMerchant({
    required String email,
    required String password,
  });

  Future<AuthSession> signInAdmin({
    required String email,
    required String password,
  });

  Future<void> logout();

  Future<void> registerDeviceToken(String token);
  Future<void> unregisterDeviceToken(String token);

  Future<Customer> getCustomerProfile();
  Future<Customer> updateCustomerProfile({
    required String name,
    required String governorate,
    String? phone,
  });
  Future<List<Governorate>> listActiveGovernorates();
  Future<Customer> updateCustomerGovernorate(String governorateId);
  Future<List<Banner>> listActiveBanners(
      {String? placement, String? governorateId});
  Future<PointsSummary> getCustomerPoints();
  Future<CustomerQrToken> issueCustomerQrToken();
  Future<List<PartnerStore>> listActiveStores(
      {String? city, String? category, String? governorateId});
  Future<List<LoyaltyTransaction>> listCustomerTransactions({String? cursor});
  Future<List<DigitalProduct>> listDigitalProducts();
  Future<List<CashRedemptionRequest>> listCustomerCashRequests();
  Future<CashRedemptionRequest> requestCashRedemption(int points);
  Future<void> redeemDigitalProduct({
    required DigitalProduct product,
    String? phoneNumber,
  });
  Future<List<ProductRedemption>> listCustomerProductRedemptions();

  Future<MerchantWorkspaceSnapshot> getMerchantWorkspace();
  Future<void> registerMerchantDevice({
    required String fingerprint,
    required String label,
  });
  Future<Customer> resolveCustomerQr(String payload);
  Future<LoyaltyTransaction> registerInvoice({
    required String customerQrPayload,
    required int amountSyp,
    required String idempotencyKey,
  });
  Future<MerchantSummary> getMerchantSummary({DateTime? from, DateTime? to});
  Future<List<LoyaltyTransaction>> listMerchantTransactions({String? cursor});

  Future<AdminOverviewSnapshot> getAdminOverview();
  Future<List<Customer>> listAdminCustomers();

  /// Latest loyalty transactions for the admin overview "recent activity"
  /// table.
  Future<List<LoyaltyTransaction>> listAdminRecentTransactions({int limit});
  Future<Customer> grantCustomerPoints({
    required String customerId,
    required int points,
    required String note,
  });
  Future<Customer> deductCustomerPoints({
    required String customerId,
    required int points,
    required String note,
  });
  Future<void> deleteCustomer(String customerId);
  Future<List<Governorate>> listAdminGovernorates();
  Future<List<Banner>> listAdminBanners({String? placement});
  Future<Banner> createBanner(Banner banner);
  Future<Banner> updateBanner(Banner banner);
  Future<Banner> setBannerImage(String bannerId, StoreLogoUpload image);
  Future<Banner> removeBannerImage(String bannerId);
  Future<void> deleteBanner(String bannerId);
  Future<Governorate> createGovernorate(Governorate governorate);
  Future<Governorate> updateGovernorate(Governorate governorate);
  Future<List<CashRedemptionRequest>> listAdminCashRequests({String? status});
  Future<CashRedemptionRequest> resolveCashRequest({
    required String requestId,
    required bool approve,
  });
  Future<List<ProductRedemption>> listAdminProductRedemptions(
      {String? status});
  Future<ProductRedemption> resolveProductRedemption({
    required String redemptionId,
    required bool approve,
  });
  Future<NotificationBroadcast> sendGeneralNotification({
    required String title,
    required String body,
    required String idempotencyKey,
  });
  Future<List<NotificationBroadcast>> listNotificationBroadcasts();
  Future<List<PartnerStore>> listAdminStores();
  Future<PartnerStore> createStore(PartnerStore store);
  Future<PartnerStore> updateStore(PartnerStore store);
  /// Soft delete: deactivates the store (and its merchant account(s)) so it
  /// disappears from Customer listings, without touching any historical
  /// transaction/settlement data.
  Future<void> deleteStore(String storeId);
  Future<PartnerStore> setStoreLogo(String storeId, StoreLogoUpload logo);
  Future<PartnerStore> removeStoreLogo(String storeId);
  Future<List<DigitalProduct>> listAdminProducts();
  Future<DigitalProduct> createProduct(DigitalProduct product);
  Future<DigitalProduct> updateProduct(DigitalProduct product);
  Future<DigitalProduct> setProductImage(String productId, StoreLogoUpload image);
  Future<DigitalProduct> removeProductImage(String productId);
  Future<List<MerchantAccount>> listMerchantAccounts();
  Future<IssuedMerchantAccount> createMerchantAccount({
    required String storeId,
    required String email,
    String? password,
    String? displayLabel,
  });
  Future<double> getPointValue();
  Future<double> updatePointValue(double pointValueSyp);
  Future<int> getMinCashWithdrawal();
  Future<int> updateMinCashWithdrawal(int amountSyp);
  Future<ShareRewardResult> claimShareReward();
  Future<int> getShareRewardPoints();
  Future<int> updateShareRewardPoints(int points);
  Future<List<MerchantSettlementSummary>> listSettlements({
    DateTime? periodStart,
    DateTime? periodEnd,
  });
  Future<MerchantSettlementSummary> settleStore({
    required String storeId,
    required DateTime periodStart,
    required DateTime periodEnd,
  });
  Future<MonthlySettlementPreview> previewMonthlySettlement(String month);
  Future<MonthlySettlementRunResult> runMonthlySettlement(String month);
  Future<List<MonthlySettlementRecord>> listMonthlySettlementHistory();

  // ---- Customer notification inbox (signed-in customer's own only) ----

  /// Newest first. [unreadOnly] (default) lists only unread entries; the
  /// unread count always covers the whole inbox. Listing never marks read.
  Future<CustomerNotificationInbox> listCustomerNotifications({
    bool unreadOnly = true,
  });

  /// Marks exactly this one notification as read.
  Future<CustomerNotificationReadResult> markCustomerNotificationRead(
    String notificationId,
  );

  // ---- Store offers (view-only; see docs/STORE_OFFERS_API.md) ----

  /// Offers customers can see now for [storeId], in display order (public,
  /// no sign-in needed). Fails with a 404 [YallaCashFailure] when the store
  /// is missing or inactive; an active store without offers gives `[]`.
  Future<List<StoreOffer>> listStoreOffers(String storeId);

  /// Admin: every offer of [storeId], including inactive, scheduled and
  /// expired ones, in display order.
  Future<List<StoreOffer>> listAdminStoreOffers(String storeId);
  Future<StoreOffer> createOffer(String storeId, StoreOfferDraft draft);

  /// Partial update: only the fields set in [update] change.
  Future<StoreOffer> updateOffer(String offerId, StoreOfferUpdate update);

  /// Deletes exactly this one offer (and its image).
  Future<void> deleteOffer(String offerId);

  /// PNG, JPEG or WebP, at most 300 KB. Bumps the offer's imageVersion.
  Future<StoreOffer> setOfferImage(String offerId, StoreLogoUpload image);

  /// Bumps the offer's imageVersion.
  Future<StoreOffer> removeOfferImage(String offerId);

  /// Admin preview bytes of an offer's image, for an offer in any status.
  /// It needs the admin token, so never load that URL as a plain network
  /// image. Pass the offer's [imageVersion] so a re-uploaded image is never
  /// served from a stale HTTP cache.
  Future<OfferImageData> fetchAdminOfferImage(
    String offerId, {
    int? imageVersion,
  });
}
