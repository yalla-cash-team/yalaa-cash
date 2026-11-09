import 'dart:typed_data';

import 'package:yalla_cash_core/src/data/auth_token_store.dart';
import 'package:yalla_cash_core/src/city_names.dart';
import 'package:yalla_cash_core/src/core/failure.dart';
import 'package:yalla_cash_core/src/customer_notifications.dart';
import 'package:yalla_cash_core/src/domain/yalla_cash_repository.dart';
import 'package:yalla_cash_core/src/in_memory_store.dart';
import 'package:yalla_cash_core/src/models.dart';
import 'package:yalla_cash_core/src/store_offers.dart';

class InMemoryYallaCashRepository implements YallaCashRepository {
  /// [clock] is the time source for offer availability and timestamps;
  /// tests inject a fixed clock for deterministic boundaries.
  InMemoryYallaCashRepository(this._store, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final YallaCashStore _store;
  final DateTime Function() _clock;

  /// Offers live only in this repository instance and start empty: no demo
  /// offers are fabricated. Insertion-ordered.
  final Map<String, _MemoryOffer> _offers = {};
  var _offerSequence = 0;

  /// Customer id -> that customer's notification inbox (starts empty).
  final Map<String, List<CustomerNotification>> _inboxes = {};
  var _notificationSequence = 0;

  @override
  Future<CustomerNotificationInbox> listCustomerNotifications({
    bool unreadOnly = true,
  }) async {
    final inbox = _currentInbox();
    final items = [
      for (final n in inbox)
        if (!unreadOnly || !n.isRead) n,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return CustomerNotificationInbox(
      items: List.unmodifiable(items),
      unreadCount: inbox.where((n) => !n.isRead).length,
    );
  }

  @override
  Future<CustomerNotificationReadResult> markCustomerNotificationRead(
    String notificationId,
  ) async {
    final inbox = _currentInbox();
    final index = inbox.indexWhere((n) => n.id == notificationId);
    if (index < 0) {
      throw const YallaCashFailure(
        statusCode: 404,
        code: 'not_found',
        message: 'الإشعار غير موجود.',
      );
    }
    if (!inbox[index].isRead) {
      inbox[index] = inbox[index].markedRead(_clock().toUtc());
    }
    return CustomerNotificationReadResult(
      notification: inbox[index],
      unreadCount: inbox.where((n) => !n.isRead).length,
    );
  }

  /// Only the signed-in customer's own inbox is ever reachable.
  List<CustomerNotification> _currentInbox() {
    final customer = _store.currentCustomer;
    if (customer == null) {
      throw const YallaCashFailure(
        statusCode: 401,
        code: 'unauthorized',
        message: 'يرجى تسجيل الدخول.',
      );
    }
    return _inboxes.putIfAbsent(customer.id, () => []);
  }

  @override
  Future<bool> hasSavedSession() async => _store.currentCustomer != null;

  @override
  Future<PhoneOtpChallenge> startCustomerPhoneOtp(String phone) async =>
      const PhoneOtpChallenge(
        challengeId: 'demo-otp',
        expiresInSeconds: 300,
        devCode: '000000',
      );

  @override
  Future<AuthSession> verifyCustomerPhoneOtp({
    required String challengeId,
    required String phone,
    required String code,
    required String name,
    String? governorate,
  }) async {
    if (challengeId != 'demo-otp' || code != '000000') {
      throw const YallaCashFailure(
        code: 'invalid_otp',
        message: 'رمز التحقق غير صحيح.',
      );
    }
    _store.registerCustomer(
      name: name,
      governorate: governorate,
      authMethod: AuthMethod.phone,
      phone: phone,
    );
    return AuthSession(
      userId: _store.currentCustomer!.id,
      role: YallaUserRole.customer,
      tokens: _demoTokens(),
      customer: _store.currentCustomer,
    );
  }

  @override
  Future<AuthSession> signInCustomerWithOAuth({
    required AuthMethod provider,
    required String firebaseIdToken,
    required String name,
    String? governorate,
  }) async {
    _store.registerCustomer(
      name: name,
      governorate: governorate,
      authMethod: provider,
    );
    return AuthSession(
      userId: _store.currentCustomer!.id,
      role: YallaUserRole.customer,
      tokens: _demoTokens(),
      customer: _store.currentCustomer,
    );
  }

  @override
  Future<AuthSession> signInMerchant(
      {required String email, required String password}) async {
    if (!_store.loginMerchant(email, password)) {
      throw const YallaCashFailure(
        code: 'invalid_credentials',
        message: 'بيانات دخول المحل غير صحيحة.',
      );
    }
    return AuthSession(
      userId: _store.currentMerchant!.id,
      role: YallaUserRole.merchant,
      tokens: _demoTokens(),
    );
  }

  @override
  Future<AuthSession> signInAdmin(
      {required String email, required String password}) async {
    if (email.trim().toLowerCase() != 'admin@yallacash.app' ||
        password != 'admin123') {
      throw const YallaCashFailure(
        code: 'invalid_credentials',
        message: 'بيانات دخول الإدارة غير صحيحة.',
      );
    }
    return AuthSession(
      userId: 'admin-demo',
      role: YallaUserRole.admin,
      tokens: _demoTokens(),
    );
  }

  @override
  Future<void> logout() async {
    _store.logoutCustomer();
    _store.logoutMerchant();
  }

  @override
  Future<void> registerDeviceToken(String token) async {}

  @override
  Future<void> unregisterDeviceToken(String token) async {}

  @override
  Future<Customer> getCustomerProfile() async => _store.currentCustomer!;

  @override
  Future<Customer> updateCustomerProfile({
    required String name,
    required String governorate,
    String? phone,
  }) async =>
      _store.currentCustomer!;

  @override
  Future<List<Governorate>> listActiveGovernorates() async =>
      _store.governorates.where((item) => item.isActive).toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  @override
  Future<List<Banner>> listActiveBanners(
      {String? placement, String? governorateId}) async {
    final now = DateTime.now();
    return _store.banners.where((banner) {
      final targetPlacement = placement == null ||
          banner.placement.toLowerCase() == placement.toLowerCase();
      final activeWindow =
          (banner.startsAt == null || !banner.startsAt!.isAfter(now)) &&
              (banner.endsAt == null || !banner.endsAt!.isBefore(now));
      final governorateMatches =
          banner.governorateId == null || banner.governorateId == governorateId;
      return banner.isActive &&
          targetPlacement &&
          activeWindow &&
          governorateMatches;
    }).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  }

  @override
  Future<List<City>> listActiveCities({String? governorateId}) async =>
      _store.cities
          .where((c) =>
              c.isActive &&
              (governorateId == null || c.governorateId == governorateId))
          .toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  @override
  Future<Customer> updateCustomerCity(String cityId) async {
    _store.updateCustomerCity(cityId);
    return _store.currentCustomer!;
  }

  @override
  Future<List<City>> listAdminCities({String? governorateId}) async => _store
      .cities
      .where((c) => governorateId == null || c.governorateId == governorateId)
      .toList(growable: false);

  @override
  Future<City> createCity(City city) async {
    final nameAr = normalizeCityName(city.nameAr);
    if (cityNameKey(nameAr).length < 2) {
      throw StateError('City name is too short.');
    }
    final clash = findCityNameClash<City>(
      _store.cities.where((c) => c.governorateId == city.governorateId),
      nameAr,
      nameOf: (c) => c.nameAr,
      idOf: (c) => c.id,
    );
    if (clash != null) {
      throw StateError('A similar city already exists: ${clash.nameAr}');
    }
    final created = City(
      id: 'city-${DateTime.now().microsecondsSinceEpoch}',
      governorateId: city.governorateId,
      nameAr: nameAr,
      isActive: city.isActive,
      displayOrder: city.displayOrder,
    );
    _store.addCity(created);
    return created;
  }

  /// Rename / reorder / (de)activate. A city never changes governorate, a
  /// new name must not collide with a sibling city, and a city with active
  /// stores cannot be deactivated (no store is ever orphaned).
  @override
  Future<City> updateCity(City city) async {
    final current = _store.cities.firstWhere((c) => c.id == city.id,
        orElse: () => throw StateError('City was not found.'));
    final nameAr = normalizeCityName(city.nameAr);
    if (nameAr != current.nameAr) {
      final clash = findCityNameClash<City>(
        _store.cities.where((c) => c.governorateId == current.governorateId),
        nameAr,
        nameOf: (c) => c.nameAr,
        idOf: (c) => c.id,
        exceptId: current.id,
      );
      if (clash != null) {
        throw StateError('A similar city already exists: ${clash.nameAr}');
      }
    }
    if (!city.isActive &&
        current.isActive &&
        _store.stores.any((s) => s.cityId == current.id && s.isActive)) {
      throw StateError('The city still has active stores.');
    }
    final saved = current.copyWith(
      nameAr: nameAr,
      isActive: city.isActive,
      displayOrder: city.displayOrder,
    );
    _store.updateCity(saved);
    return saved;
  }

  @override
  Future<Customer> updateCustomerGovernorate(String governorateId) async {
    _store.updateCustomerGovernorate(governorateId);
    return _store.currentCustomer!;
  }

  @override
  Future<PointsSummary> getCustomerPoints() async {
    final customer = _store.currentCustomer!;
    final available = _store.availablePoints(customer.id);
    return PointsSummary(
      pointsBalance: customer.pointsBalance,
      heldPoints: customer.pointsBalance - available,
      availablePoints: available,
    );
  }

  @override
  Future<CustomerQrToken> issueCustomerQrToken() async {
    final customer = _store.currentCustomer!;
    return CustomerQrToken(
      token: 'demo-only',
      payload: _store.customerQrPayload(customer.id),
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
  }

  @override
  Future<List<PartnerStore>> listActiveStores(
          {String? city,
          String? category,
          String? governorateId,
          String? cityId}) async =>
      (_store.stores
          .where((store) =>
              store.isActive &&
              (category == null || store.category == category) &&
              (governorateId == null || store.governorateId == governorateId) &&
              (cityId == null || store.cityId == cityId))
          .toList()
        ..sort((a, b) {
          final byOrder = a.displayOrder.compareTo(b.displayOrder);
          if (byOrder != 0) return byOrder;
          final byName = a.name.compareTo(b.name);
          return byName != 0 ? byName : a.id.compareTo(b.id);
        }));

  @override
  Future<List<LoyaltyTransaction>> listCustomerTransactions(
          {String? cursor}) async =>
      _store.transactionsForCustomer(_store.currentCustomer!.id);

  @override
  Future<List<DigitalProduct>> listDigitalProducts() async => _store.products
      .where((product) => product.isActive)
      .toList(growable: false);

  @override
  Future<List<CashRedemptionRequest>> listCustomerCashRequests() async =>
      _store.cashRequests
          .where((request) => request.customerId == _store.currentCustomer!.id)
          .toList(growable: false);

  @override
  Future<CashRedemptionRequest> requestCashRedemption(int points) async =>
      _store.requestCashRedemption(
        customerId: _store.currentCustomer!.id,
        points: points,
      );

  @override
  Future<void> redeemDigitalProduct({
    required DigitalProduct product,
    String? phoneNumber,
  }) async {
    _store.redeemProduct(
      customerId: _store.currentCustomer!.id,
      product: product,
      phoneNumber: phoneNumber,
    );
  }

  // Demo/in-memory mode doesn't track individual redemption records (see
  // listAdminProductRedemptions below, which is the same "not implemented
  // for the demo store" precedent).
  @override
  Future<List<ProductRedemption>> listCustomerProductRedemptions() async =>
      const [];

  @override
  Future<MerchantWorkspaceSnapshot> getMerchantWorkspace() async {
    final store = _store.currentMerchantStore!;
    final transactions = _store.transactionsForStore(store.id);
    final sales =
        transactions.fold<int>(0, (sum, item) => sum + item.amountSyp);
    final commission = transactions.fold<int>(
        0, (sum, item) => sum + item.commissionAmountSyp);
    return MerchantWorkspaceSnapshot(
      account: _store.currentMerchant!,
      store: store,
      summary: MerchantSummary(
        storeId: store.id,
        from: DateTime(DateTime.now().year, DateTime.now().month),
        to: DateTime(DateTime.now().year, DateTime.now().month + 1),
        transactionCount: transactions.length,
        totalSalesSyp: sales,
        commissionDueSyp: commission,
      ),
      recentTransactions: transactions.take(8).toList(growable: false),
    );
  }

  @override
  Future<void> registerMerchantDevice(
      {required String fingerprint, required String label}) async {}

  @override
  Future<Customer> resolveCustomerQr(String payload) async {
    final customerId = _store.customerIdFromQr(payload);
    if (customerId == null) {
      throw const YallaCashFailure(
        code: 'invalid_qr',
        message: 'الكود غير صالح أو منتهي الصلاحية.',
      );
    }
    return _store.customerById(customerId);
  }

  @override
  Future<LoyaltyTransaction> registerInvoice({
    required String customerQrPayload,
    required int amountSyp,
    required String idempotencyKey,
  }) async {
    final customerId = _store.customerIdFromQr(customerQrPayload);
    if (customerId == null) {
      throw const YallaCashFailure(
        code: 'invalid_qr',
        message: 'الكود غير صالح أو منتهي الصلاحية.',
      );
    }
    return _store.registerInvoice(
      customerId: customerId,
      storeId: _store.currentMerchantStore!.id,
      amountSyp: amountSyp,
    );
  }

  @override
  Future<MerchantSummary> getMerchantSummary(
          {DateTime? from, DateTime? to}) async =>
      (await getMerchantWorkspace()).summary;

  @override
  Future<List<LoyaltyTransaction>> listMerchantTransactions(
          {String? cursor}) async =>
      _store.transactionsForStore(_store.currentMerchantStore!.id);

  @override
  Future<AdminOverviewSnapshot> getAdminOverview() async {
    final sales =
        _store.transactions.fold<int>(0, (sum, item) => sum + item.amountSyp);
    final revenue = _store.transactions
        .fold<int>(0, (sum, item) => sum + item.platformRevenueSyp);
    final commission = _store.transactions
        .fold<int>(0, (sum, item) => sum + item.commissionAmountSyp);
    return AdminOverviewSnapshot(
      customers: _store.customers.length,
      activeStores: _store.stores.where((store) => store.isActive).length,
      transactions: _store.transactions.length,
      totalSalesSyp: sales,
      platformRevenueSyp: revenue,
      commissionDueSyp: commission,
      pendingCashRequests: _store.cashRequests
          .where((request) => request.status == CashRequestStatus.pending)
          .length,
    );
  }

  @override
  Future<List<Customer>> listAdminCustomers() async =>
      _store.customers.toList(growable: false);

  @override
  Future<List<LoyaltyTransaction>> listAdminRecentTransactions(
      {int limit = 8}) async {
    final transactions = [..._store.transactions]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return transactions.take(limit).toList(growable: false);
  }

  @override
  Future<Customer> grantCustomerPoints({
    required String customerId,
    required int points,
    required String note,
  }) async {
    _store.grantPoints(customerId, points);
    return _store.customerById(customerId);
  }

  @override
  Future<Customer> deductCustomerPoints({
    required String customerId,
    required int points,
    required String note,
  }) async {
    _store.deductPoints(customerId, points);
    return _store.customerById(customerId);
  }

  @override
  Future<void> deleteCustomer(String customerId) async {
    _store.removeCustomer(customerId);
  }

  @override
  Future<List<Governorate>> listAdminGovernorates() async =>
      _store.governorates.toList(growable: false);

  @override
  Future<List<Banner>> listAdminBanners({String? placement}) async => _store
      .banners
      .where((item) =>
          placement == null ||
          item.placement.toLowerCase() == placement.toLowerCase())
      .toList(growable: false)
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  @override
  // The in-memory demo has no image storage, so uploads are not kept here.
  @override
  Future<Banner> setBannerImage(String bannerId, StoreLogoUpload image) async =>
      (await listAdminBanners()).firstWhere((item) => item.id == bannerId);

  @override
  Future<Banner> removeBannerImage(String bannerId) async =>
      (await listAdminBanners()).firstWhere((item) => item.id == bannerId);

  @override
  Future<Banner> createBanner(Banner banner) async {
    _store.addBanner(banner);
    return banner;
  }

  @override
  Future<Banner> updateBanner(Banner banner) async {
    _store.updateBanner(banner);
    return banner;
  }

  @override
  Future<void> deleteBanner(String bannerId) async {
    _store.deleteBanner(bannerId);
  }

  @override
  Future<Governorate> createGovernorate(Governorate governorate) async {
    _store.addGovernorate(governorate);
    return governorate;
  }

  @override
  Future<Governorate> updateGovernorate(Governorate governorate) async {
    _store.updateGovernorate(governorate);
    return governorate;
  }

  @override
  Future<List<CashRedemptionRequest>> listAdminCashRequests(
          {String? status}) async =>
      _store.cashRequests
          .where((request) => status == null || request.status.name == status)
          .toList(growable: false);

  @override
  Future<CashRedemptionRequest> resolveCashRequest({
    required String requestId,
    required bool approve,
  }) async {
    if (approve) {
      _store.settleCashRequest(requestId);
    } else {
      _store.rejectCashRequest(requestId);
    }
    return _store.cashRequests.firstWhere((request) => request.id == requestId);
  }

  @override
  Future<List<ProductRedemption>> listAdminProductRedemptions(
          {String? status}) async =>
      const [];

  @override
  Future<ProductRedemption> resolveProductRedemption({
    required String redemptionId,
    required bool approve,
  }) async {
    throw const YallaCashFailure(
      code: 'not_supported',
      message: 'غير مدعوم في العرض التجريبي.',
    );
  }

  @override
  // The in-memory demo has no push provider, so nothing is delivered.
  @override
  Future<List<NotificationBroadcast>> listNotificationBroadcasts() async =>
      const [];

  @override
  Future<NotificationBroadcast> sendGeneralNotification({
    required String title,
    required String body,
    required String idempotencyKey,
  }) async {
    // Like the backend: every customer gets one inbox entry per broadcast,
    // and a repeated key adds nothing.
    final now = _clock().toUtc();
    for (final customer in _store.customers) {
      final inbox = _inboxes.putIfAbsent(customer.id, () => []);
      if (inbox.any((n) => n.broadcastId == idempotencyKey)) continue;
      inbox.add(CustomerNotification(
        id: 'notification-${++_notificationSequence}',
        broadcastId: idempotencyKey,
        title: title,
        body: body,
        createdAt: now.add(Duration(microseconds: _notificationSequence)),
      ));
    }
    return NotificationBroadcast(
      id: idempotencyKey,
      title: title,
      body: body,
      status: 'SENT',
      recipientCount: 0,
      sentCount: 0,
      failedCount: 0,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<PartnerStore>> listAdminStores() async =>
      _store.stores.toList(growable: false);

  @override
  Future<PartnerStore> createStore(PartnerStore store) async {
    return _store.saveStore(store.copyWith(
      cityId: store.cityId,
    ));
  }

  @override
  Future<PartnerStore> updateStore(PartnerStore store) async {
    return _store.saveStore(store);
  }

  @override
  Future<void> deleteStore(String storeId) async {
    _store.deleteStore(storeId);
  }

  // The in-memory demo has no file storage, so logos are not kept here.
  @override
  Future<PartnerStore> setStoreLogo(
          String storeId, StoreLogoUpload logo) async =>
      (await listAdminStores()).firstWhere((store) => store.id == storeId);

  @override
  Future<PartnerStore> removeStoreLogo(String storeId) async =>
      (await listAdminStores()).firstWhere((store) => store.id == storeId);

  @override
  Future<List<DigitalProduct>> listAdminProducts() async =>
      _store.products.toList(growable: false);

  @override
  Future<DigitalProduct> createProduct(DigitalProduct product) async {
    _store.addDigitalProduct();
    return _store.products.last;
  }

  @override
  Future<DigitalProduct> updateProduct(DigitalProduct product) async {
    _store.updateDigitalProduct(product.id, product);
    return product;
  }

  // The in-memory demo has no image storage, so images are not kept here.
  @override
  Future<DigitalProduct> setProductImage(
          String productId, StoreLogoUpload image) async =>
      (await listAdminProducts()).firstWhere((item) => item.id == productId);

  @override
  Future<DigitalProduct> removeProductImage(String productId) async =>
      (await listAdminProducts()).firstWhere((item) => item.id == productId);

  @override
  Future<List<MerchantAccount>> listMerchantAccounts() async =>
      _store.merchantAccounts.toList(growable: false);

  @override
  Future<IssuedMerchantAccount> createMerchantAccount({
    required String storeId,
    required String email,
    String? password,
    String? displayLabel,
  }) async {
    final account = _store.addMerchantAccount(storeId);
    return IssuedMerchantAccount(
      account: account,
      temporaryPassword: account.demoPassword,
    );
  }

  @override
  Future<double> getPointValue() async => _store.pointValueSyp;

  @override
  Future<double> updatePointValue(double pointValueSyp) async {
    _store.updatePointValue(pointValueSyp);
    return _store.pointValueSyp;
  }

  @override
  Future<int> getMinCashWithdrawal() async => _store.minCashWithdrawalSyp;

  @override
  Future<int> updateMinCashWithdrawal(int amountSyp) async {
    _store.updateMinCashWithdrawal(amountSyp);
    return _store.minCashWithdrawalSyp;
  }

  // The in-memory demo never grants points: the reward needs the backend.
  @override
  Future<ShareRewardResult> claimShareReward() async => const ShareRewardResult(
        status: 'disabled',
        pointsAwarded: 0,
        pointsBalance: 0,
      );

  @override
  Future<int> getShareRewardPoints() async => _store.shareRewardPoints;

  @override
  Future<int> updateShareRewardPoints(int points) async {
    _store.updateShareRewardPoints(points);
    return _store.shareRewardPoints;
  }

  @override
  Future<List<MerchantSettlementSummary>> listSettlements({
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final start =
        periodStart ?? DateTime(DateTime.now().year, DateTime.now().month);
    final end =
        periodEnd ?? DateTime(DateTime.now().year, DateTime.now().month + 1);
    return _store.stores.map((store) {
      final transactions = _store.transactionsForStore(store.id);
      final sales =
          transactions.fold<int>(0, (sum, item) => sum + item.amountSyp);
      final commission = transactions.fold<int>(
          0, (sum, item) => sum + item.commissionAmountSyp);
      final settled = _store.settledStoreIds.contains(store.id);
      return MerchantSettlementSummary(
        storeId: store.id,
        storeName: store.name,
        periodStart: start,
        periodEnd: end,
        transactionCount: transactions.length,
        totalSalesSyp: sales,
        commissionDueSyp: commission,
        status: settled ? 'settled' : 'open',
        settledAt: settled ? DateTime.now() : null,
      );
    }).toList(growable: false);
  }

  // The in-memory demo has no settlement ledger, so monthly runs are empty.
  @override
  Future<MonthlySettlementPreview> previewMonthlySettlement(
          String month) async =>
      MonthlySettlementPreview(
        month: month,
        merchants: const [],
        openMerchantCount: 0,
        totalSalesSyp: 0,
        totalCommissionSyp: 0,
      );

  @override
  Future<MonthlySettlementRunResult> runMonthlySettlement(String month) async =>
      MonthlySettlementRunResult(
        month: month,
        settledCount: 0,
        skippedCount: 0,
        failedCount: 0,
        totalCommissionSyp: 0,
        merchants: const [],
      );

  @override
  Future<List<MonthlySettlementRecord>> listMonthlySettlementHistory() async =>
      const [];

  @override
  Future<MerchantSettlementSummary> settleStore({
    required String storeId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    _store.toggleStoreSettlement(storeId);
    return (await listSettlements(
            periodStart: periodStart, periodEnd: periodEnd))
        .firstWhere((item) => item.storeId == storeId);
  }

  AuthTokens _demoTokens() => AuthTokens(
        accessToken: 'demo-access-token',
        refreshToken: 'demo-refresh-token',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );

  // ---- Store offers: mirrors the backend rules in docs/STORE_OFFERS_API.md.

  @override
  Future<List<StoreOffer>> listStoreOffers(String storeId) async {
    final store = _store.stores.where((s) => s.id == storeId).firstOrNull;
    if (store == null || !store.isActive) throw _storeNotFound();
    final now = _clock();
    return [
      for (final offer in _orderedOffersOf(storeId))
        if (offer.statusAt(now) == OfferStatus.active) offer.publicView(),
    ];
  }

  @override
  Future<List<StoreOffer>> listAdminStoreOffers(String storeId) async {
    _requireStore(storeId);
    final now = _clock();
    return [
      for (final offer in _orderedOffersOf(storeId)) offer.adminView(now),
    ];
  }

  @override
  Future<StoreOffer> createOffer(String storeId, StoreOfferDraft draft) async {
    _requireStore(storeId);
    final title = _validTitle(draft.title);
    final description = _validDescription(draft.description);
    final label = _validLabel(draft.discountLabel);
    final window = _validWindow(draft.startDate, draft.endDate);
    final displayOrder = _validDisplayOrder(draft.displayOrder);
    final now = _clock();
    final sequence = ++_offerSequence;
    final offer = _MemoryOffer(
      id: 'offer-$sequence',
      storeId: storeId,
      sequence: sequence,
      createdAt: now.toUtc(),
      title: title,
      description: description,
      discountLabel: label,
      startDate: window.$1,
      endDate: window.$2,
      isActive: draft.isActive,
      displayOrder: displayOrder,
    );
    _offers[offer.id] = offer;
    return offer.adminView(now);
  }

  @override
  Future<StoreOffer> updateOffer(
      String offerId, StoreOfferUpdate update) async {
    final offer = _requireOffer(offerId);
    final now = _clock();
    if (update.isEmpty) return offer.adminView(now);

    // Validate everything first so a rejected update changes nothing.
    final title = update.title == null ? null : _validTitle(update.title!);
    final description = update.description == null
        ? null
        : _validDescription(update.description!.value ?? '');
    final label = update.discountLabel == null
        ? null
        : _validLabel(update.discountLabel!.value);
    // The final combined window is validated, as on the backend.
    final window = _validWindow(
      update.startDate == null ? offer.startDate : update.startDate!.value,
      update.endDate == null ? offer.endDate : update.endDate!.value,
    );
    final displayOrder = update.displayOrder == null
        ? null
        : _validDisplayOrder(update.displayOrder!);

    if (title != null) offer.title = title;
    if (description != null) offer.description = description;
    if (update.discountLabel != null) offer.discountLabel = label;
    offer
      ..startDate = window.$1
      ..endDate = window.$2;
    if (update.isActive != null) offer.isActive = update.isActive!;
    if (displayOrder != null) offer.displayOrder = displayOrder;
    offer.updatedAt = now.toUtc();
    return offer.adminView(now);
  }

  @override
  Future<void> deleteOffer(String offerId) async {
    _requireOffer(offerId);
    _offers.remove(offerId);
  }

  @override
  Future<StoreOffer> setOfferImage(
      String offerId, StoreLogoUpload image) async {
    // Like the backend: the image is validated before the offer is touched.
    if (!offerImageContentTypes.contains(image.contentType)) {
      throw _invalidOffer('contentType');
    }
    if (image.bytes.isEmpty || image.bytes.length > _maxOfferImageBytes) {
      throw _invalidOffer('image size');
    }
    final offer = _requireOffer(offerId);
    final now = _clock();
    offer
      ..image = OfferImageData(
        bytes: Uint8List.fromList(image.bytes),
        contentType: image.contentType,
      )
      ..imageVersion += 1
      ..updatedAt = now.toUtc();
    return offer.adminView(now);
  }

  @override
  Future<StoreOffer> removeOfferImage(String offerId) async {
    final offer = _requireOffer(offerId);
    final now = _clock();
    offer
      ..image = null
      ..imageVersion += 1
      ..updatedAt = now.toUtc();
    return offer.adminView(now);
  }

  @override
  Future<OfferImageData> fetchAdminOfferImage(
    String offerId, {
    int? imageVersion,
  }) async {
    final image = _requireOffer(offerId).image;
    if (image == null) {
      throw const YallaCashFailure(
        statusCode: 404,
        code: 'not_found',
        message: 'صورة العرض غير موجودة.',
      );
    }
    return image;
  }

  /// displayOrder ascending, then newest first (the backend's OFFER_ORDER);
  /// the creation sequence breaks ties between equal timestamps.
  List<_MemoryOffer> _orderedOffersOf(String storeId) =>
      _offers.values.where((offer) => offer.storeId == storeId).toList()
        ..sort((a, b) {
          final byOrder = a.displayOrder.compareTo(b.displayOrder);
          if (byOrder != 0) return byOrder;
          final byCreated = b.createdAt.compareTo(a.createdAt);
          if (byCreated != 0) return byCreated;
          return b.sequence.compareTo(a.sequence);
        });

  /// Admin endpoints accept inactive (soft-deleted) stores too.
  void _requireStore(String storeId) {
    if (!_store.stores.any((store) => store.id == storeId)) {
      throw _storeNotFound();
    }
  }

  _MemoryOffer _requireOffer(String offerId) =>
      _offers[offerId] ??
      (throw const YallaCashFailure(
        statusCode: 404,
        code: 'not_found',
        message: 'العرض غير موجود.',
      ));
}

const _maxOfferImageBytes = 300 * 1024;

YallaCashFailure _storeNotFound() => const YallaCashFailure(
      statusCode: 404,
      code: 'not_found',
      message: 'المتجر غير موجود.',
    );

YallaCashFailure _invalidOffer(String field) => YallaCashFailure(
      statusCode: 400,
      code: 'bad_request',
      message: 'بيانات العرض غير صالحة.',
      details: field,
    );

String _validTitle(String value) {
  final title = value.trim();
  if (title.length < 2 || title.length > 120) throw _invalidOffer('title');
  return title;
}

String _validDescription(String value) {
  if (value.length > 1000) throw _invalidOffer('description');
  return value;
}

/// Blank or null means "no label".
String? _validLabel(String? value) {
  final label = value?.trim();
  if (label == null || label.isEmpty) return null;
  if (label.length > 60) throw _invalidOffer('discountLabel');
  return label;
}

int _validDisplayOrder(int value) {
  if (value < 0 || value > 9999) throw _invalidOffer('displayOrder');
  return value;
}

(OfferCalendarDate?, OfferCalendarDate?) _validWindow(
  OfferCalendarDate? start,
  OfferCalendarDate? end,
) {
  for (final date in [start, end]) {
    if (date != null && (date.year < 2000 || date.year > 2100)) {
      throw _invalidOffer('date year');
    }
  }
  if (start != null && end != null && end.compareTo(start) < 0) {
    throw _invalidOffer('endDate before startDate');
  }
  return (start, end);
}

/// IN-MEMORY APPROXIMATION ONLY. The backend converts Damascus calendar days
/// with the time zone database. This demo/test double uses Syria's fixed
/// UTC+3 (in force since October 2022) so that it can produce startsAt and
/// endsBefore without a time zone dependency.
const _damascusUtcOffset = Duration(hours: 3);

DateTime _damascusStartOf(OfferCalendarDate day) =>
    DateTime.utc(day.year, day.month, day.day).subtract(_damascusUtcOffset);

class _MemoryOffer {
  _MemoryOffer({
    required this.id,
    required this.storeId,
    required this.sequence,
    required this.createdAt,
    required this.title,
    required this.description,
    required this.discountLabel,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.displayOrder,
  }) : updatedAt = createdAt;

  final String id;
  final String storeId;
  final int sequence;
  final DateTime createdAt;
  String title;
  String description;
  String? discountLabel;
  OfferCalendarDate? startDate;
  OfferCalendarDate? endDate;
  bool isActive;
  int displayOrder;
  DateTime updatedAt;
  OfferImageData? image;
  var imageVersion = 0;

  /// 00:00 Damascus on [startDate] (inclusive).
  DateTime? get startsAt =>
      startDate == null ? null : _damascusStartOf(startDate!);

  /// 00:00 Damascus on the day after [endDate] (exclusive).
  DateTime? get endsBefore => endDate == null
      ? null
      : _damascusStartOf(endDate!).add(const Duration(days: 1));

  OfferStatus statusAt(DateTime now) => offerStatusAt(
        isActive: isActive,
        startsAt: startsAt,
        endsBefore: endsBefore,
        now: now,
      );

  /// The shape [StoreOffer.fromJson] gives for an admin response.
  StoreOffer adminView(DateTime now) => StoreOffer(
        id: id,
        storeId: storeId,
        title: title,
        description: description,
        discountLabel: discountLabel,
        imageUrl:
            image == null ? null : '/admin/offers/$id/image?v=$imageVersion',
        imageVersion: imageVersion,
        hasImage: image != null,
        imageAccess: OfferImageAccess.adminPreview,
        startDate: startDate,
        endDate: endDate,
        startsAt: startsAt,
        endsBefore: endsBefore,
        isActive: isActive,
        displayOrder: displayOrder,
        serverStatus: statusAt(now),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// The shape [StoreOffer.fromJson] gives for a public response (no admin
  /// fields; the version travels only inside the image URL).
  StoreOffer publicView() => StoreOffer(
        id: id,
        storeId: storeId,
        title: title,
        description: description,
        discountLabel: discountLabel,
        imageUrl: image == null ? null : '/offers/$id/image?v=$imageVersion',
        hasImage: image != null,
        startDate: startDate,
        endDate: endDate,
        startsAt: startsAt,
        endsBefore: endsBefore,
      );
}
