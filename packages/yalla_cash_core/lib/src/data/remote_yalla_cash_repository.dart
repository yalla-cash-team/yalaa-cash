import 'dart:convert';

import 'package:yalla_cash_core/src/core/failure.dart';
import 'package:yalla_cash_core/src/customer_notifications.dart';
import 'package:yalla_cash_core/src/data/yalla_cash_api_client.dart';
import 'package:yalla_cash_core/src/domain/yalla_cash_repository.dart';
import 'package:yalla_cash_core/src/models.dart';
import 'package:yalla_cash_core/src/store_offers.dart';

class RemoteYallaCashRepository implements YallaCashRepository {
  RemoteYallaCashRepository(this._client);

  final YallaCashApiClient _client;

  @override
  Future<bool> hasSavedSession() => _client.hasSavedSession();

  @override
  Future<PhoneOtpChallenge> startCustomerPhoneOtp(String phone) async {
    final json = apiMap(
      await _client.post(
        '/auth/customer/phone/start',
        body: {'phone': phone},
        authenticated: false,
      ),
    );
    return PhoneOtpChallenge(
      challengeId: json['challengeId']! as String,
      expiresInSeconds: json['expiresInSeconds']! as int,
      devCode: json['devCode'] as String?,
    );
  }

  @override
  Future<AuthSession> verifyCustomerPhoneOtp({
    required String challengeId,
    required String phone,
    required String code,
    required String name,
    required String governorate,
  }) =>
      _authenticate(
        '/auth/customer/phone/verify',
        {
          'challengeId': challengeId,
          'phone': phone,
          'code': code,
          'name': name,
          'governorate': governorate,
        },
      );

  @override
  Future<AuthSession> signInCustomerWithOAuth({
    required AuthMethod provider,
    required String firebaseIdToken,
    required String name,
    required String governorate,
  }) =>
      _authenticate(
        '/auth/customer/oauth',
        {
          'provider': provider == AuthMethod.gmail ? 'GOOGLE' : 'FACEBOOK',
          'firebaseIdToken': firebaseIdToken,
          'name': name,
          'governorate': governorate,
        },
      );

  @override
  Future<AuthSession> signInMerchant({
    required String email,
    required String password,
  }) =>
      _authenticate(
        '/auth/merchant/login',
        {'email': email, 'password': password},
      );

  @override
  Future<AuthSession> signInAdmin({
    required String email,
    required String password,
  }) =>
      _authenticate(
        '/auth/admin/login',
        {'email': email, 'password': password},
      );

  @override
  Future<void> logout() async {
    final tokens = await _client.tokens;
    try {
      if (tokens != null) {
        await _client
            .post('/auth/logout', body: {'refreshToken': tokens.refreshToken});
      }
    } finally {
      await _client.clearTokens();
    }
  }

  @override
  Future<Customer> getCustomerProfile() async =>
      _customerFromApi(apiMap(await _client.get('/customer/profile')));

  @override
  Future<Customer> updateCustomerProfile({
    required String name,
    required String governorate,
    String? phone,
  }) async =>
      _customerFromApi(
        apiMap(
          await _client.patch(
            '/customer/profile',
            body: {
              'name': name,
              'governorate': governorate,
              if (phone != null) 'phone': phone,
            },
          ),
        ),
      );

  @override
  Future<List<Governorate>> listActiveGovernorates() async =>
      apiItems(await _client.get('/customer/governorates'))
          .map(_governorateFromApi)
          .toList(growable: false);

  @override
  Future<List<City>> listActiveCities({String? governorateId}) async =>
      apiItems(await _client.get('/customer/cities',
              query: {'governorateId': governorateId}))
          .map(_cityFromApi)
          .toList(growable: false);

  @override
  Future<Customer> updateCustomerCity(String cityId) async => _customerFromApi(
        apiMap(await _client.patch('/customer/city', body: {'cityId': cityId})),
      );

  @override
  Future<List<City>> listAdminCities({String? governorateId}) async =>
      apiItems(await _client
              .get('/admin/cities', query: {'governorateId': governorateId}))
          .map(_cityFromApi)
          .toList(growable: false);

  @override
  Future<City> createCity(City city) async => _cityFromApi(apiMap(
        await _client.post('/admin/cities', body: {
          'governorateId': city.governorateId,
          'nameAr': city.nameAr,
          'isActive': city.isActive,
          'displayOrder': city.displayOrder,
        }),
      ));

  @override
  Future<City> updateCity(City city) async => _cityFromApi(apiMap(
        await _client.patch('/admin/cities/${city.id}', body: {
          'nameAr': city.nameAr,
          'isActive': city.isActive,
          'displayOrder': city.displayOrder,
        }),
      ));

  @override
  Future<Customer> updateCustomerGovernorate(String governorateId) async =>
      _customerFromApi(
        apiMap(
          await _client.patch(
            '/customer/governorate',
            body: {'governorateId': governorateId},
          ),
        ),
      );

  @override
  Future<List<Banner>> listActiveBanners(
          {String? placement, String? governorateId}) async =>
      apiItems(await _client.get('/customer/banners',
              query: {'placement': placement ?? 'HOME'}))
          .map(_bannerFromApi)
          .where((banner) =>
              governorateId == null ||
              banner.governorateId == null ||
              banner.governorateId == governorateId)
          .toList(growable: false);

  @override
  Future<PointsSummary> getCustomerPoints() async {
    final json = apiMap(await _client.get('/customer/points'));
    return PointsSummary(
      pointsBalance: _int(json['pointsBalance']),
      heldPoints: _int(json['heldPoints']),
      availablePoints: _int(json['availablePoints']),
    );
  }

  @override
  Future<CustomerQrToken> issueCustomerQrToken() async {
    final json = apiMap(await _client.post('/customer/qr-token'));
    return CustomerQrToken(
      token: json['token']! as String,
      payload: json['payload']! as String,
      expiresAt: DateTime.parse(json['expiresAt']! as String),
    );
  }

  @override
  Future<void> registerDeviceToken(String token) async {
    await _client.post('/customer/device-token', body: {'token': token});
  }

  @override
  Future<void> unregisterDeviceToken(String token) async {
    await _client.post('/customer/device-token/remove', body: {'token': token});
  }

  @override
  Future<List<PartnerStore>> listActiveStores(
          {String? city,
          String? category,
          String? governorateId,
          String? cityId}) async =>
      apiItems(
        await _client.get(
          '/stores',
          query: {
            'city': city,
            'category': category,
            'governorateId': governorateId,
            'cityId': cityId,
          },
          authenticated: false,
        ),
      ).map(_storeFromApi).toList(growable: false);

  @override
  Future<List<LoyaltyTransaction>> listCustomerTransactions(
          {String? cursor}) async =>
      apiItems(
        await _client.get(
          '/customer/transactions',
          query: {'cursor': cursor},
        ),
      ).map(_transactionFromApi).toList(growable: false);

  @override
  Future<List<DigitalProduct>> listDigitalProducts() async =>
      apiItems(await _client.get('/customer/digital-products'))
          .map(_productFromApi)
          .toList(growable: false);

  @override
  Future<List<CashRedemptionRequest>> listCustomerCashRequests() async =>
      apiItems(await _client.get('/customer/redemptions/cash'))
          .map(_cashRequestFromApi)
          .toList(growable: false);

  @override
  Future<CashRedemptionRequest> requestCashRedemption(int points) async =>
      _cashRequestFromApi(
        apiMap(
          await _client.post(
            '/customer/redemptions/cash',
            body: {'points': points},
          ),
        ),
      );

  @override
  Future<void> redeemDigitalProduct({
    required DigitalProduct product,
    String? phoneNumber,
  }) async {
    await _client.post(
      '/customer/redemptions/products',
      body: {
        'productId': product.id,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
      },
    );
  }

  @override
  Future<List<ProductRedemption>> listCustomerProductRedemptions() async =>
      apiItems(await _client.get('/customer/redemptions/products'))
          .map(_productRedemptionFromApi)
          .toList(growable: false);

  @override
  Future<MerchantWorkspaceSnapshot> getMerchantWorkspace() async {
    final json = apiMap(await _client.get('/merchant/me'));
    return MerchantWorkspaceSnapshot(
      account: _merchantAccountFromApi(apiMap(json['account'])),
      store: _storeFromApi(apiMap(json['store'])),
      summary: _merchantSummaryFromApi(apiMap(json['summary'])),
      recentTransactions: (json['recentTransactions'] as List? ?? const [])
          .map((item) => _transactionFromApi(apiMap(item)))
          .toList(growable: false),
    );
  }

  @override
  Future<void> registerMerchantDevice({
    required String fingerprint,
    required String label,
  }) async {
    await _client.post(
      '/merchant/devices',
      body: {'fingerprint': fingerprint, 'label': label},
    );
  }

  @override
  Future<Customer> resolveCustomerQr(String payload) async => _customerFromApi(
        apiMap(
          await _client
              .post('/merchant/qr/resolve', body: {'payload': payload}),
        ),
      );

  @override
  Future<LoyaltyTransaction> registerInvoice({
    required String customerQrPayload,
    required int amountSyp,
    required String idempotencyKey,
  }) async =>
      _transactionFromApi(
        apiMap(
          await _client.post(
            '/merchant/invoices',
            body: {
              'customerQrPayload': customerQrPayload,
              'amountSyp': amountSyp,
              'idempotencyKey': idempotencyKey,
            },
          ),
        ),
      );

  @override
  Future<MerchantSummary> getMerchantSummary(
          {DateTime? from, DateTime? to}) async =>
      _merchantSummaryFromApi(
        apiMap(
          await _client.get(
            '/merchant/summary',
            query: {
              'from': from?.toIso8601String(),
              'to': to?.toIso8601String(),
            },
          ),
        ),
      );

  @override
  Future<List<LoyaltyTransaction>> listMerchantTransactions(
          {String? cursor}) async =>
      apiItems(
        await _client.get('/merchant/transactions', query: {'cursor': cursor}),
      ).map(_transactionFromApi).toList(growable: false);

  @override
  Future<AdminOverviewSnapshot> getAdminOverview() async {
    final json = apiMap(await _client.get('/admin/overview'));
    return AdminOverviewSnapshot(
      customers: _int(json['customers']),
      activeStores: _int(json['activeStores']),
      transactions: _int(json['transactions']),
      totalSalesSyp: _int(json['totalSalesSyp']),
      platformRevenueSyp: _int(json['platformRevenueSyp']),
      commissionDueSyp: _int(json['commissionDueSyp']),
      pendingCashRequests: _int(json['pendingCashRequests']),
    );
  }

  @override
  Future<List<Customer>> listAdminCustomers() async =>
      apiItems(await _client.get('/admin/customers'))
          .map(_customerFromApi)
          .toList(growable: false);

  @override
  Future<List<LoyaltyTransaction>> listAdminRecentTransactions(
          {int limit = 8}) async =>
      apiItems(
        await _client.get(
          '/admin/transactions',
          query: {'limit': limit},
        ),
      ).map(_transactionFromApi).toList(growable: false);

  @override
  Future<List<Governorate>> listAdminGovernorates() async =>
      apiItems(await _client.get('/admin/governorates'))
          .map(_governorateFromApi)
          .toList(growable: false);

  @override
  Future<List<Banner>> listAdminBanners({String? placement}) async => apiItems(
          await _client.get('/admin/banners', query: {'placement': placement}))
      .map(_bannerFromApi)
      .toList(growable: false);

  @override
  Future<Banner> createBanner(Banner banner) async => _bannerFromApi(
        apiMap(
          await _client.post(
            '/admin/banners',
            body: {
              'title': banner.title,
              'subtitle': banner.subtitle,
              'imageUrl': banner.imageUrl,
              'targetUrl': banner.targetUrl,
              'placement': _enumToApi(banner.placement),
              'style': _enumToApi(banner.style),
              'isActive': banner.isActive,
              'displayOrder': banner.displayOrder,
              'startsAt': banner.startsAt?.toIso8601String(),
              'endsAt': banner.endsAt?.toIso8601String(),
              'governorateId': banner.governorateId,
            },
          ),
        ),
      );

  @override
  Future<Banner> updateBanner(Banner banner) async => _bannerFromApi(
        apiMap(
          await _client.patch(
            '/admin/banners/${banner.id}',
            body: {
              'title': banner.title,
              'subtitle': banner.subtitle,
              'imageUrl': banner.imageUrl,
              'targetUrl': banner.targetUrl,
              'placement': _enumToApi(banner.placement),
              'style': _enumToApi(banner.style),
              'isActive': banner.isActive,
              'displayOrder': banner.displayOrder,
              'startsAt': banner.startsAt?.toIso8601String(),
              'endsAt': banner.endsAt?.toIso8601String(),
              'governorateId': banner.governorateId,
            },
          ),
        ),
      );

  @override
  Future<void> deleteBanner(String bannerId) async {
    await _client.delete('/admin/banners/$bannerId');
  }

  @override
  Future<Governorate> createGovernorate(Governorate governorate) async =>
      _governorateFromApi(
        apiMap(
          await _client.post(
            '/admin/governorates',
            body: {
              'nameAr': governorate.nameAr,
              'isActive': governorate.isActive,
              'displayOrder': governorate.displayOrder,
            },
          ),
        ),
      );

  @override
  Future<Governorate> updateGovernorate(Governorate governorate) async =>
      _governorateFromApi(
        apiMap(
          await _client.patch(
            '/admin/governorates/${governorate.id}',
            body: {
              'nameAr': governorate.nameAr,
              'isActive': governorate.isActive,
              'displayOrder': governorate.displayOrder,
            },
          ),
        ),
      );

  @override
  Future<Customer> grantCustomerPoints({
    required String customerId,
    required int points,
    required String note,
  }) async =>
      _customerFromApi(
        apiMap(
          await _client.post(
            '/admin/customers/$customerId/points/grant',
            body: {'points': points, 'note': note},
          ),
        ),
      );

  @override
  Future<Customer> deductCustomerPoints({
    required String customerId,
    required int points,
    required String note,
  }) async =>
      _customerFromApi(
        apiMap(
          await _client.post(
            '/admin/customers/$customerId/points/deduct',
            body: {'points': points, 'note': note},
          ),
        ),
      );

  @override
  Future<void> deleteCustomer(String customerId) async {
    await _client.delete('/admin/customers/$customerId');
  }

  @override
  Future<List<CashRedemptionRequest>> listAdminCashRequests(
          {String? status}) async =>
      apiItems(
        await _client.get('/admin/cash-requests', query: {'status': status}),
      ).map(_cashRequestFromApi).toList(growable: false);

  @override
  Future<CashRedemptionRequest> resolveCashRequest({
    required String requestId,
    required bool approve,
  }) async =>
      _cashRequestFromApi(
        apiMap(
          await _client.post(
            '/admin/cash-requests/$requestId/resolve',
            body: {'approve': approve},
          ),
        ),
      );

  @override
  Future<List<ProductRedemption>> listAdminProductRedemptions(
          {String? status}) async =>
      apiItems(
        await _client
            .get('/admin/product-redemptions', query: {'status': status}),
      ).map(_productRedemptionFromApi).toList(growable: false);

  @override
  Future<ProductRedemption> resolveProductRedemption({
    required String redemptionId,
    required bool approve,
  }) async =>
      _productRedemptionFromApi(
        apiMap(
          await _client.post(
            '/admin/product-redemptions/$redemptionId/resolve',
            body: {'approve': approve},
          ),
        ),
      );

  @override
  Future<NotificationBroadcast> sendGeneralNotification({
    required String title,
    required String body,
    required String idempotencyKey,
  }) async =>
      _broadcastFromApi(apiMap(await _client.post(
        '/admin/notifications',
        body: {
          'title': title,
          'body': body,
          'idempotencyKey': idempotencyKey,
        },
      )));

  @override
  Future<List<NotificationBroadcast>> listNotificationBroadcasts() async =>
      apiItems(await _client.get('/admin/notifications'))
          .map(_broadcastFromApi)
          .toList(growable: false);

  NotificationBroadcast _broadcastFromApi(Map<String, Object?> json) =>
      NotificationBroadcast(
        id: json['id']! as String,
        title: json['title']! as String,
        body: json['body']! as String,
        status: json['status']! as String,
        recipientCount: _int(json['recipientCount'] ?? 0),
        sentCount: _int(json['sentCount'] ?? 0),
        failedCount: _int(json['failedCount'] ?? 0),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  @override
  Future<List<PartnerStore>> listAdminStores() async =>
      apiItems(await _client.get('/admin/stores'))
          .map(_storeFromApi)
          .toList(growable: false);

  @override
  Future<PartnerStore> createStore(PartnerStore store) async => _storeFromApi(
      apiMap(await _client.post('/admin/stores', body: _storeToApi(store))));

  @override
  Future<PartnerStore> updateStore(PartnerStore store) async =>
      _storeFromApi(apiMap(await _client.patch('/admin/stores/${store.id}',
          body: _storeToApi(store))));

  @override
  Future<PartnerStore> setStoreLogo(String storeId, StoreLogoUpload logo) async =>
      _storeFromApi(apiMap(await _client.put(
        '/admin/stores/$storeId/logo',
        body: {
          'contentType': logo.contentType,
          'dataBase64': base64Encode(logo.bytes),
        },
      )));

  @override
  Future<PartnerStore> removeStoreLogo(String storeId) async =>
      _storeFromApi(apiMap(await _client.delete('/admin/stores/$storeId/logo')));

  @override
  Future<void> deleteStore(String storeId) async {
    await _client.delete('/admin/stores/$storeId');
  }

  @override
  Future<List<DigitalProduct>> listAdminProducts() async =>
      apiItems(await _client.get('/admin/products'))
          .map(_productFromApi)
          .toList(growable: false);

  @override
  Future<DigitalProduct> createProduct(DigitalProduct product) async =>
      _productFromApi(apiMap(
          await _client.post('/admin/products', body: _productToApi(product))));

  @override
  Future<DigitalProduct> updateProduct(DigitalProduct product) async =>
      _productFromApi(apiMap(await _client.patch(
          '/admin/products/${product.id}',
          body: _productToApi(product))));

  @override
  Future<DigitalProduct> setProductImage(
          String productId, StoreLogoUpload image) async =>
      _productFromApi(apiMap(await _client.put(
        '/admin/products/$productId/image',
        body: {
          'contentType': image.contentType,
          'dataBase64': base64Encode(image.bytes),
        },
      )));

  @override
  Future<DigitalProduct> removeProductImage(String productId) async =>
      _productFromApi(
          apiMap(await _client.delete('/admin/products/$productId/image')));

  @override
  Future<List<MerchantAccount>> listMerchantAccounts() async =>
      apiItems(await _client.get('/admin/merchant-accounts'))
          .map(_merchantAccountFromApi)
          .toList(growable: false);

  @override
  Future<IssuedMerchantAccount> createMerchantAccount({
    required String storeId,
    required String email,
    String? password,
    String? displayLabel,
  }) async {
    final json = apiMap(
      await _client.post(
        '/admin/merchant-accounts',
        body: {
          'storeId': storeId,
          'email': email,
          if (password != null) 'password': password,
          if (displayLabel != null) 'displayLabel': displayLabel,
        },
      ),
    );
    return IssuedMerchantAccount(
      account: _merchantAccountFromApi(apiMap(json['account'])),
      temporaryPassword: json['temporaryPassword']! as String,
    );
  }

  @override
  Future<double> getPointValue() async => _pointValue(
      apiMap(await _client.get('/admin/settings'))['pointValueSyp']);

  @override
  Future<double> updatePointValue(double pointValueSyp) async => _pointValue(
        apiMap(
          await _client.patch(
            '/admin/settings',
            body: {'pointValueSyp': pointValueSyp},
          ),
        )['pointValueSyp'],
      );

  // The API returns the point value as a JSON number (may be fractional).
  double _pointValue(Object? value) => double.parse('$value');

  @override
  Future<int> getMinCashWithdrawal() async => _int(apiMap(
      await _client.get('/admin/settings'))['minCashWithdrawalSyp']);

  @override
  Future<int> updateMinCashWithdrawal(int amountSyp) async => _int(
        apiMap(
          await _client.patch(
            '/admin/settings/min-cash-withdrawal',
            body: {'minCashWithdrawalSyp': amountSyp},
          ),
        )['minCashWithdrawalSyp'],
      );

  @override
  Future<ShareRewardResult> claimShareReward() async {
    final json = apiMap(await _client.post('/customer/share-reward/claim'));
    return ShareRewardResult(
      status: json['status']! as String,
      pointsAwarded: _int(json['pointsAwarded']),
      pointsBalance: _int(json['pointsBalance']),
    );
  }

  @override
  Future<int> getShareRewardPoints() async => _int(
      apiMap(await _client.get('/admin/settings'))['shareRewardPoints']);

  @override
  Future<int> updateShareRewardPoints(int points) async => _int(
        apiMap(
          await _client.patch(
            '/admin/settings/share-reward',
            body: {'shareRewardPoints': points},
          ),
        )['shareRewardPoints'],
      );

  @override
  Future<List<MerchantSettlementSummary>> listSettlements({
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async =>
      apiItems(
        await _client.get(
          '/admin/settlements',
          query: {
            'periodStart': periodStart?.toIso8601String(),
            'periodEnd': periodEnd?.toIso8601String(),
          },
        ),
      ).map(_settlementFromApi).toList(growable: false);

  @override
  Future<MonthlySettlementPreview> previewMonthlySettlement(String month) async {
    final json = apiMap(await _client.get(
      '/admin/settlements/monthly',
      query: {'month': month},
    ));
    return MonthlySettlementPreview(
      month: json['month']! as String,
      merchants: (json['merchants']! as List<Object?>)
          .map((item) => _monthlyStatusFromApi(item! as Map<String, Object?>))
          .toList(growable: false),
      openMerchantCount: _int(json['openMerchantCount'] ?? 0),
      totalSalesSyp: _int(json['totalSalesSyp'] ?? 0),
      totalCommissionSyp: _int(json['totalCommissionSyp'] ?? 0),
    );
  }

  @override
  Future<MonthlySettlementRunResult> runMonthlySettlement(String month) async {
    final json = apiMap(await _client.post(
      '/admin/settlements/monthly',
      body: {'month': month},
    ));
    return MonthlySettlementRunResult(
      month: json['month']! as String,
      settledCount: _int(json['settledCount'] ?? 0),
      skippedCount: _int(json['skippedCount'] ?? 0),
      failedCount: _int(json['failedCount'] ?? 0),
      totalCommissionSyp: _int(json['totalCommissionSyp'] ?? 0),
      merchants: (json['merchants']! as List<Object?>)
          .map((item) => _monthlyOutcomeFromApi(item! as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  @override
  Future<List<MonthlySettlementRecord>> listMonthlySettlementHistory() async =>
      apiItems(await _client.get('/admin/settlements/monthly/history'))
          .map(_monthlyRecordFromApi)
          .toList(growable: false);

  MonthlyMerchantStatus _monthlyStatusFromApi(Map<String, Object?> json) =>
      MonthlyMerchantStatus(
        storeId: json['storeId']! as String,
        storeName: json['storeName']! as String,
        status: json['status']! as String,
        transactionCount: _int(json['transactionCount'] ?? 0),
        totalSalesSyp: _int(json['totalSalesSyp'] ?? 0),
        commissionDueSyp: _int(json['commissionDueSyp'] ?? 0),
      );

  MonthlyMerchantOutcome _monthlyOutcomeFromApi(Map<String, Object?> json) =>
      MonthlyMerchantOutcome(
        storeName: json['storeName']! as String,
        status: json['status']! as String,
        commissionDueSyp: _int(json['commissionDueSyp'] ?? 0),
        error: json['error'] as String?,
      );

  MonthlySettlementRecord _monthlyRecordFromApi(Map<String, Object?> json) =>
      MonthlySettlementRecord(
        storeName: json['storeName']! as String,
        month: json['month']! as String,
        transactionCount: _int(json['transactionCount'] ?? 0),
        totalSalesSyp: _int(json['totalSalesSyp'] ?? 0),
        commissionDueSyp: _int(json['commissionDueSyp'] ?? 0),
        settledAt: DateTime.tryParse(json['settledAt'] as String? ?? ''),
      );

  @override
  Future<MerchantSettlementSummary> settleStore({
    required String storeId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async =>
      _settlementFromApi(
        apiMap(
          await _client.post(
            '/admin/settlements/settle',
            body: {
              'storeId': storeId,
              'periodStart': periodStart.toIso8601String(),
              'periodEnd': periodEnd.toIso8601String(),
            },
          ),
        ),
      );

  Future<AuthSession> _authenticate(
      String path, Map<String, Object?> body) async {
    // NOTE: never log credentials, tokens, or password-derived values here.
    final json =
        apiMap(await _client.post(path, body: body, authenticated: false));
    final tokens = authTokensFromResponse(json);
    await _client.saveTokens(tokens);
    final user = apiMap(json['user']);
    return AuthSession(
      userId: user['id']! as String,
      role: _roleFromApi(user['role']! as String),
      tokens: tokens,
      customer: json['profile'] == null
          ? null
          : _customerFromApi(apiMap(json['profile'])),
    );
  }

  Customer _customerFromApi(Map<String, Object?> json) => Customer(
        id: json['id']! as String,
        name: json['name']! as String,
        phone: json['phone'] as String?,
        authMethod: _authMethodFromApi(json['authMethod'] as String?),
        governorate: json['governorate']! as String,
        governorateId: json['governorateId'] as String?,
        cityId: json['cityId'] as String?,
        pointsBalance: _int(json['pointsBalance']),
        createdAt: DateTime.parse(json['createdAt']! as String),
      );

  City _cityFromApi(Map<String, Object?> json) => City(
        id: json['id']! as String,
        governorateId: json['governorateId']! as String,
        nameAr: json['nameAr']! as String,
        isActive: json['isActive'] as bool? ?? true,
        displayOrder: _int(json['displayOrder'] ?? 0),
      );

  Governorate _governorateFromApi(Map<String, Object?> json) => Governorate(
        id: json['id']! as String,
        nameAr: json['nameAr']! as String,
        isActive: json['isActive'] as bool? ?? false,
        displayOrder: _int(json['displayOrder']),
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
      );

  @override
  Future<Banner> setBannerImage(String bannerId, StoreLogoUpload image) async =>
      _bannerFromApi(apiMap(await _client.put(
        '/admin/banners/$bannerId/image',
        body: {
          'contentType': image.contentType,
          'dataBase64': base64Encode(image.bytes),
        },
      )));

  @override
  Future<Banner> removeBannerImage(String bannerId) async => _bannerFromApi(
      apiMap(await _client.delete('/admin/banners/$bannerId/image')));

  // ---- Customer notification inbox ----

  @override
  Future<CustomerNotificationInbox> listCustomerNotifications({
    bool unreadOnly = true,
  }) async {
    final json = apiMap(await _client.get(
      '/customer/notifications',
      query: {'unread': unreadOnly ? 'true' : 'false'},
    ));
    final items = json['items'];
    if (items is! List) {
      throw const YallaCashFailure(
        code: 'invalid_response',
        message: 'استجابة الخادم لا تحتوي على قائمة صالحة.',
      );
    }
    return CustomerNotificationInbox(
      items: [for (final item in items) CustomerNotification.fromJson(apiMap(item))],
      unreadCount: _int(json['unreadCount'] ?? 0),
    );
  }

  @override
  Future<CustomerNotificationReadResult> markCustomerNotificationRead(
    String notificationId,
  ) async {
    final json = apiMap(await _client.post(
      '/customer/notifications/${Uri.encodeComponent(notificationId)}/read',
    ));
    return CustomerNotificationReadResult(
      notification: CustomerNotification.fromJson(json),
      unreadCount: _int(json['unreadCount'] ?? 0),
    );
  }

  // ---- Store offers. The endpoints return bare JSON arrays/objects. ----

  // Public endpoint: sent without the bearer token. Offers parsed from it
  // point at the public image endpoint.
  @override
  Future<List<StoreOffer>> listStoreOffers(String storeId) async =>
      storeOffersFromJson(
        await _client.get(
          '/stores/${Uri.encodeComponent(storeId)}/offers',
          authenticated: false,
        ),
        resolveUrl: _resolveOfferUrl,
      );

  @override
  Future<List<StoreOffer>> listAdminStoreOffers(String storeId) async =>
      storeOffersFromJson(
        await _client.get('/admin/stores/${Uri.encodeComponent(storeId)}/offers'),
        resolveUrl: _resolveOfferUrl,
        imageAccess: OfferImageAccess.adminPreview,
      );

  @override
  Future<StoreOffer> createOffer(String storeId, StoreOfferDraft draft) async =>
      _adminOfferFromApi(await _client.post(
        '/admin/stores/${Uri.encodeComponent(storeId)}/offers',
        body: draft.toJson(),
      ));

  @override
  Future<StoreOffer> updateOffer(
          String offerId, StoreOfferUpdate update) async =>
      _adminOfferFromApi(await _client.patch(
        '/admin/offers/${Uri.encodeComponent(offerId)}',
        body: update.toJson(),
      ));

  @override
  Future<void> deleteOffer(String offerId) async {
    await _client.delete('/admin/offers/${Uri.encodeComponent(offerId)}');
  }

  // POST (not PUT, unlike store logos), as defined by the offers API.
  @override
  Future<StoreOffer> setOfferImage(
          String offerId, StoreLogoUpload image) async =>
      _adminOfferFromApi(await _client.post(
        '/admin/offers/${Uri.encodeComponent(offerId)}/image',
        body: {
          'contentType': image.contentType,
          'dataBase64': base64Encode(image.bytes),
        },
      ));

  @override
  Future<StoreOffer> removeOfferImage(String offerId) async =>
      _adminOfferFromApi(await _client
          .delete('/admin/offers/${Uri.encodeComponent(offerId)}/image'));

  @override
  Future<OfferImageData> fetchAdminOfferImage(
    String offerId, {
    int? imageVersion,
  }) async {
    final response = await _client.getBytes(
      '/admin/offers/${Uri.encodeComponent(offerId)}/image',
      query: {'v': imageVersion},
    );
    final contentType = response.contentType;
    if (contentType == null || !offerImageContentTypes.contains(contentType)) {
      throw YallaCashFailure(
        code: 'invalid_response',
        message: 'استجابة الخادم غير متوقعة.',
        details: 'offer image content-type: $contentType',
      );
    }
    return OfferImageData(bytes: response.bytes, contentType: contentType);
  }

  StoreOffer _adminOfferFromApi(Object? response) => StoreOffer.fromJson(
        apiMap(response),
        resolveUrl: _resolveOfferUrl,
        imageAccess: OfferImageAccess.adminPreview,
      );

  /// Keeps the `?v=<imageVersion>` cache-buster of server-relative URLs.
  String _resolveOfferUrl(String path) => _client.resolveUrl(path).toString();

  Banner _bannerFromApi(Map<String, Object?> json) => Banner(
        id: json['id']! as String,
        title: json['title']! as String,
        subtitle: json['subtitle'] as String?,
        // Empty when the banner relies on an uploaded image without a URL.
        imageUrl: _absoluteUrl(json['imageUrl']) ?? '',
        targetUrl: json['targetUrl'] as String?,
        placement: (json['placement'] as String?) ?? 'home',
        style: (json['style'] as String?) ?? 'promo',
        isActive: json['isActive'] as bool? ?? true,
        displayOrder: _int(json['displayOrder'] ?? 0),
        governorateId: json['governorateId'] as String?,
        startsAt: json['startsAt'] == null
            ? null
            : DateTime.parse(json['startsAt']! as String),
        endsAt: json['endsAt'] == null
            ? null
            : DateTime.parse(json['endsAt']! as String),
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
      );

  PartnerStore _storeFromApi(Map<String, Object?> json) => PartnerStore(
        id: json['id']! as String,
        name: json['name']! as String,
        category: json['category']! as String,
        commissionRate: _double(json['commissionRate']),
        description: (json['description'] as String?) ?? '',
        location:
            (json['location'] as String?) ?? (json['city'] as String?) ?? '',
        iconSeed: _int(json['iconSeed'] ?? 0),
        governorateId: json['governorateId']! as String,
        cityId: json['cityId'] as String?,
        displayOrder: _int(json['displayOrder'] ?? 0),
        isActive: json['isActive'] as bool? ?? true,
        logoUrl: _absoluteUrl(json['logoUrl']),
      );

  /// Server-relative image paths (e.g. `/stores/1/logo?v=2`) made absolute.
  /// Legacy full URLs pass through unchanged.
  String? _absoluteUrl(Object? value) => value is String && value.isNotEmpty
      ? _client.resolveUrl(value).toString()
      : null;

  LoyaltyTransaction _transactionFromApi(Map<String, Object?> json) =>
      LoyaltyTransaction(
        id: json['id']! as String,
        storeId: json['storeId']! as String,
        storeName: (json['storeName'] as String?) ?? '',
        customerId: json['customerId']! as String,
        customerName: json['customerName'] as String?,
        amountSyp: _int(json['amountSyp']),
        commissionRateSnapshot: _double(json['commissionRateSnapshot']),
        commissionAmountSyp: _int(json['commissionAmountSyp']),
        platformRevenueSyp: _int(json['platformRevenueSyp']),
        customerShareSyp: _int(json['customerShareSyp']),
        customerPointsEarned: _int(json['customerPointsEarned']),
        createdAt: DateTime.parse(json['createdAt']! as String),
      );

  DigitalProduct _productFromApi(Map<String, Object?> json) => DigitalProduct(
        id: json['id']! as String,
        name: json['name']! as String,
        costInPoints: _int(json['costInPoints']),
        iconSeed: _int(json['iconSeed'] ?? 0),
        requiresPhoneNumber: json['requiresPhoneNumber'] as bool? ?? false,
        isActive: json['isActive'] as bool? ?? true,
        imageUrl: _absoluteUrl(json['imageUrl']),
      );

  CashRedemptionRequest _cashRequestFromApi(Map<String, Object?> json) =>
      CashRedemptionRequest(
        id: json['id']! as String,
        customerId: json['customerId']! as String,
        pointsRequested: _int(json['pointsRequested']),
        cashValueSyp: _int(json['cashValueSyp']),
        status: _cashStatusFromApi(json['status']! as String),
        createdAt: DateTime.parse(json['createdAt']! as String),
        settledAt: json['settledAt'] == null
            ? null
            : DateTime.parse(json['settledAt']! as String),
      );

  ProductRedemption _productRedemptionFromApi(Map<String, Object?> json) =>
      ProductRedemption(
        id: json['id']! as String,
        customerId: json['customerId']! as String,
        customerName: json['customerName'] as String?,
        customerPhone: json['customerPhone'] as String?,
        productId: json['productId']! as String,
        productName: json['productName'] as String?,
        pointsCostSnapshot: _int(json['pointsCostSnapshot']),
        phoneNumber: json['phoneNumber'] as String?,
        status: _redemptionStatusFromApi(json['status']! as String),
        createdAt: DateTime.parse(json['createdAt']! as String),
        fulfilledAt: json['fulfilledAt'] == null
            ? null
            : DateTime.parse(json['fulfilledAt']! as String),
      );

  RedemptionStatus _redemptionStatusFromApi(String value) {
    switch (value.toLowerCase()) {
      case 'fulfilled':
        return RedemptionStatus.fulfilled;
      case 'rejected':
        return RedemptionStatus.rejected;
      case 'pending':
      default:
        return RedemptionStatus.pending;
    }
  }

  MerchantAccount _merchantAccountFromApi(Map<String, Object?> json) =>
      MerchantAccount(
        id: json['id']! as String,
        storeId: json['storeId']! as String,
        email: (json['email'] as String?) ?? '',
        demoPassword: '',
        deviceCount: _int(json['deviceCount'] ?? 0),
      );

  MerchantSummary _merchantSummaryFromApi(Map<String, Object?> json) =>
      MerchantSummary(
        storeId: json['storeId']! as String,
        from: DateTime.parse(json['from']! as String),
        to: DateTime.parse(json['to']! as String),
        transactionCount: _int(json['transactionCount']),
        totalSalesSyp: _int(json['totalSalesSyp']),
        commissionDueSyp: _int(json['commissionDueSyp']),
      );

  MerchantSettlementSummary _settlementFromApi(Map<String, Object?> json) =>
      MerchantSettlementSummary(
        id: json['id'] as String?,
        storeId: json['storeId']! as String,
        storeName: json['storeName']! as String,
        periodStart: DateTime.parse(json['periodStart']! as String),
        periodEnd: DateTime.parse(json['periodEnd']! as String),
        transactionCount: _int(json['transactionCount']),
        totalSalesSyp: _int(json['totalSalesSyp']),
        commissionDueSyp: _int(json['commissionDueSyp']),
        status: json['status']! as String,
        settledAt: json['settledAt'] == null
            ? null
            : DateTime.parse(json['settledAt']! as String),
      );

  Map<String, Object?> _storeToApi(PartnerStore store) => {
        'name': store.name,
        'category': store.category,
        // A structured city wins; older data falls back to the location text.
        if (store.cityId != null)
          'cityId': store.cityId
        else
          'city': _cityFromLocation(store.location),
        // Omitted (not 0) so a new store lands at the end of its city.
        if (store.displayOrder > 0) 'displayOrder': store.displayOrder,
        'commissionRate': store.commissionRate,
        'description': store.description,
        'location': store.location,
        'iconSeed': store.iconSeed,
        'isActive': store.isActive,
        'governorateId': store.governorateId,
      };

  Map<String, Object?> _productToApi(DigitalProduct product) => {
        'name': product.name,
        'costInPoints': product.costInPoints,
        'iconSeed': product.iconSeed,
        'requiresPhoneNumber': product.requiresPhoneNumber,
        'isActive': product.isActive,
      };

  String _cityFromLocation(String location) {
    final parts = location.split(RegExp(r'\s*-\s*'));
    return parts.first.trim().isEmpty ? 'دمشق' : parts.first.trim();
  }

  int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.parse(value.toString());
  }

  double _double(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.parse(value.toString());
  }

  String _enumToApi(String value) =>
      value.trim().replaceAll('-', '_').toUpperCase();

  AuthMethod _authMethodFromApi(String? value) {
    switch (value?.toLowerCase()) {
      case 'facebook':
        return AuthMethod.facebook;
      case 'google':
      case 'gmail':
        return AuthMethod.gmail;
      case 'phone':
      default:
        return AuthMethod.phone;
    }
  }

  CashRequestStatus _cashStatusFromApi(String value) {
    switch (value.toLowerCase()) {
      case 'settled':
        return CashRequestStatus.settled;
      case 'rejected':
        return CashRequestStatus.rejected;
      case 'pending':
      default:
        return CashRequestStatus.pending;
    }
  }

  YallaUserRole _roleFromApi(String value) {
    switch (value.toLowerCase()) {
      case 'merchant':
        return YallaUserRole.merchant;
      case 'admin':
        return YallaUserRole.admin;
      case 'customer':
      default:
        return YallaUserRole.customer;
    }
  }
}
