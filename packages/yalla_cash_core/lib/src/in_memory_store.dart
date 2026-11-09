import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:yalla_cash_core/src/commission.dart';
import 'package:yalla_cash_core/src/models.dart';
import 'package:yalla_cash_core/src/store_ordering.dart';

class YallaCashStore extends ChangeNotifier {
  YallaCashStore.demo() {
    _governorates.addAll([
      Governorate(
        id: 'gov-idlib',
        nameAr: 'إدلب',
        isActive: true,
        displayOrder: 1,
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      ),
      Governorate(
        id: 'gov-damascus',
        nameAr: 'دمشق',
        isActive: true,
        displayOrder: 2,
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      ),
    ]);
    _cities.addAll(const [
      City(
          id: 'city-idlib',
          governorateId: 'gov-idlib',
          nameAr: 'إدلب',
          displayOrder: 1),
      City(
          id: 'city-ariha',
          governorateId: 'gov-idlib',
          nameAr: 'أريحا',
          displayOrder: 2),
      City(
          id: 'city-salqin',
          governorateId: 'gov-idlib',
          nameAr: 'سلقين',
          displayOrder: 3),
      City(
          id: 'city-saraqib',
          governorateId: 'gov-idlib',
          nameAr: 'سراقب',
          displayOrder: 4),
      City(
          id: 'city-damascus',
          governorateId: 'gov-damascus',
          nameAr: 'دمشق',
          displayOrder: 1),
    ]);
    _customers.addAll([
      Customer(
        id: 'cust-001',
        name: 'أحمد الحلبي',
        phone: '0933000001',
        governorate: 'إدلب',
        governorateId: 'gov-idlib',
        pointsBalance: 2860,
        createdAt: DateTime(2026, 8, 2),
      ),
      Customer(
        id: 'cust-002',
        name: 'سارة قاسم',
        phone: '0944000002',
        governorate: 'دمشق',
        governorateId: 'gov-damascus',
        pointsBalance: 2100,
        createdAt: DateTime(2026, 7, 28),
      ),
    ]);

    _banners.addAll([
      Banner(
        id: 'banner-001',
        title: 'عرض الصيف',
        subtitle: 'خصومات حتى 40% على المطاعم المختارة',
        imageUrl:
            'https://images.unsplash.com/photo-1552566626-52f8b828add9?auto=format&fit=crop&w=1200&q=80',
        targetUrl: '/stores?category=مطاعم',
        placement: 'home',
        style: 'promo',
        governorateId: 'gov-idlib',
        displayOrder: 1,
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      ),
      Banner(
        id: 'banner-002',
        title: 'فرصة التسوق',
        subtitle: 'خصم إضافي على المتاجر المحلية',
        imageUrl:
            'https://images.unsplash.com/photo-1524758631624-e2822e304c36?auto=format&fit=crop&w=1200&q=80',
        targetUrl: '/stores?category=سوبرماركت',
        placement: 'home',
        style: 'feature',
        displayOrder: 2,
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      ),
    ]);

    _stores.addAll(const [
      PartnerStore(
        id: 'store-001',
        name: 'مطعم الوسيم',
        category: 'مطاعم',
        commissionRate: 6.7,
        description: 'مطعم شامي تقليدي بأطباق منزلية.',
        location: 'دمشق - المزة',
        iconSeed: 0,
        governorateId: 'gov-damascus',
        cityId: 'city-damascus',
        displayOrder: 1,
      ),
      PartnerStore(
        id: 'store-002',
        name: 'ماركت البركة',
        category: 'سوبرماركت',
        commissionRate: 5,
        description: 'ماركت شامل للمواد الغذائية والمنزلية.',
        location: 'دمشق - الميدان',
        iconSeed: 1,
        governorateId: 'gov-damascus',
        cityId: 'city-damascus',
        displayOrder: 2,
      ),
      PartnerStore(
        id: 'store-003',
        name: 'كافيه الزاوية',
        category: 'كافيهات',
        commissionRate: 8,
        description: 'كافيه هادئ لمحبي القهوة المختصة.',
        location: 'دمشق - أبو رمانة',
        iconSeed: 2,
        governorateId: 'gov-damascus',
        cityId: 'city-damascus',
        displayOrder: 3,
      ),
      PartnerStore(
        id: 'store-004',
        name: 'صالون لمسة',
        category: 'صالونات',
        commissionRate: 7,
        description: 'صالون عناية وتجميل متكامل.',
        location: 'إدلب - مركز المدينة',
        iconSeed: 3,
        governorateId: 'gov-idlib',
        cityId: 'city-idlib',
        displayOrder: 1,
      ),
      PartnerStore(
        id: 'store-005',
        name: 'صيدلية الشفاء',
        category: 'صيدليات',
        commissionRate: 4,
        description: 'صيدلية متكاملة على مدار الساعة.',
        location: 'إدلب - شارع الثلاثين',
        iconSeed: 4,
        governorateId: 'gov-idlib',
        cityId: 'city-idlib',
        displayOrder: 2,
      ),
    ]);

    _products.addAll(const [
      DigitalProduct(
        id: 'product-001',
        name: 'رصيد اتصالات',
        costInPoints: 500,
        iconSeed: 0,
        requiresPhoneNumber: true,
      ),
      DigitalProduct(
        id: 'product-002',
        name: 'قسيمة تسوق رقمية',
        costInPoints: 950,
        iconSeed: 1,
      ),
      DigitalProduct(
        id: 'product-003',
        name: 'اشتراك موسيقى لشهر',
        costInPoints: 700,
        iconSeed: 2,
      ),
      DigitalProduct(
        id: 'product-004',
        name: 'باقة إنترنت',
        costInPoints: 400,
        iconSeed: 3,
        requiresPhoneNumber: true,
      ),
    ]);

    _merchantAccounts.add(
      const MerchantAccount(
        id: 'merchant-001',
        storeId: 'store-001',
        email: 'wasim@yallacash.app',
        demoPassword: '123456',
      ),
    );

    _transactions.addAll([
      _seedTransaction(
        id: 'tx-001',
        store: _stores[0],
        customerId: 'cust-001',
        amountSyp: 340000,
        createdAt: DateTime(2026, 8, 15),
      ),
      _seedTransaction(
        id: 'tx-002',
        store: _stores[2],
        customerId: 'cust-001',
        amountSyp: 90000,
        createdAt: DateTime(2026, 8, 13),
      ),
    ]);

    _cashRequests.add(
      CashRedemptionRequest(
        id: 'cash-demo-001',
        customerId: 'cust-002',
        pointsRequested: 300,
        cashValueSyp: 1500,
        status: CashRequestStatus.pending,
        createdAt: DateTime(2026, 8, 17),
      ),
    );
  }

  final List<Customer> _customers = [];
  final List<Governorate> _governorates = [];
  final List<City> _cities = [];
  final List<Banner> _banners = [];
  final List<PartnerStore> _stores = [];
  final List<DigitalProduct> _products = [];
  final List<LoyaltyTransaction> _transactions = [];
  final List<CashRedemptionRequest> _cashRequests = [];
  final List<MerchantAccount> _merchantAccounts = [];
  final Set<String> _settledStoreIds = {};

  Customer? currentCustomer;
  MerchantAccount? currentMerchant;
  double pointValueSyp = 5;
  int minCashWithdrawalSyp = 0;
  int shareRewardPoints = 0;

  void updateShareRewardPoints(int value) {
    if (value < 0) throw ArgumentError.value(value, 'value');
    shareRewardPoints = value;
    notifyListeners();
  }

  // Earned value not yet converted into whole points, per customer (1/10000 SYP).
  final Map<String, int> _pointRemainderScaled = {};

  UnmodifiableListView<Customer> get customers =>
      UnmodifiableListView(_customers);
  UnmodifiableListView<City> get cities => UnmodifiableListView(_cities);

  UnmodifiableListView<Governorate> get governorates =>
      UnmodifiableListView(_governorates);
  UnmodifiableListView<Banner> get banners => UnmodifiableListView(_banners);
  UnmodifiableListView<PartnerStore> get stores =>
      UnmodifiableListView(_stores);
  UnmodifiableListView<DigitalProduct> get products =>
      UnmodifiableListView(_products);
  UnmodifiableListView<LoyaltyTransaction> get transactions =>
      UnmodifiableListView(_transactions);
  UnmodifiableListView<CashRedemptionRequest> get cashRequests =>
      UnmodifiableListView(_cashRequests);
  UnmodifiableListView<MerchantAccount> get merchantAccounts =>
      UnmodifiableListView(_merchantAccounts);
  Set<String> get settledStoreIds => Set.unmodifiable(_settledStoreIds);

  PartnerStore? get currentMerchantStore => currentMerchant == null
      ? null
      : _stores
          .where((store) => store.id == currentMerchant!.storeId)
          .firstOrNull;

  int availablePoints(String customerId) {
    final customer = customerById(customerId);
    final held = _cashRequests
        .where((item) =>
            item.customerId == customerId &&
            item.status == CashRequestStatus.pending)
        .fold<int>(0, (total, item) => total + item.pointsRequested);
    return customer.pointsBalance - held;
  }

  Customer customerById(String id) =>
      _customers.firstWhere((item) => item.id == id);

  List<LoyaltyTransaction> transactionsForCustomer(String customerId) =>
      _transactions.where((item) => item.customerId == customerId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<LoyaltyTransaction> transactionsForStore(String storeId) =>
      _transactions.where((item) => item.storeId == storeId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void loginDemoCustomer() {
    currentCustomer = _customers.first;
    notifyListeners();
  }

  void updateCustomerGovernorate(String governorateId) {
    final governorate = _governorates.firstWhere(
      (item) => item.id == governorateId && item.isActive,
    );
    final customer = currentCustomer;
    if (customer == null) return;
    currentCustomer = customer.copyWith(
      governorate: governorate.nameAr,
      governorateId: governorate.id,
      clearCity: true,
    );
    final index = _customers.indexWhere((item) => item.id == customer.id);
    if (index >= 0) _customers[index] = currentCustomer!;
    notifyListeners();
  }

  /// The city must be active and inside the customer's governorate.
  void updateCustomerCity(String cityId) {
    final customer = currentCustomer;
    if (customer == null) return;
    final city = _cities.firstWhere(
      (item) =>
          item.id == cityId &&
          item.isActive &&
          item.governorateId == customer.governorateId,
      orElse: () => throw StateError('City is not available.'),
    );
    currentCustomer = customer.copyWith(cityId: city.id);
    final index = _customers.indexWhere((item) => item.id == customer.id);
    if (index >= 0) _customers[index] = currentCustomer!;
    notifyListeners();
  }

  void addCity(City city) {
    _cities.add(city);
    notifyListeners();
  }

  void updateCity(City city) {
    final index = _cities.indexWhere((item) => item.id == city.id);
    if (index < 0) return;
    _cities[index] = city;
    notifyListeners();
  }

  /// Active stores of [cityId] in display order (position, then name, id).
  List<PartnerStore> activeStoresOfCity(String cityId, {String? except}) =>
      _stores
          .where((s) => s.cityId == cityId && s.isActive && s.id != except)
          .toList()
        ..sort((a, b) {
          final byOrder = a.displayOrder.compareTo(b.displayOrder);
          if (byOrder != 0) return byOrder;
          final byName = a.name.compareTo(b.name);
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });

  void _renumber(List<String> ids) {
    for (var i = 0; i < ids.length; i++) {
      final index = _stores.indexWhere((s) => s.id == ids[i]);
      if (index >= 0 && _stores[index].displayOrder != i + 1) {
        _stores[index] = _stores[index].copyWith(displayOrder: i + 1);
      }
    }
  }

  /// Creates or replaces [store], applying the same ordering rules as the
  /// backend: one active store per city/category, insertion into an occupied
  /// position shifts the others, leaving a city closes its gap, a new or
  /// reactivated store without a position goes last, inactive stores hold 0.
  PartnerStore saveStore(PartnerStore store) {
    final index = _stores.indexWhere((s) => s.id == store.id);
    final previous = index < 0 ? null : _stores[index];
    final cityId = store.cityId;
    if (store.isActive) {
      if (cityId == null) throw StateError('A city is required.');
      final city = _cities.firstWhere((c) => c.id == cityId,
          orElse: () => throw StateError('City was not found.'));
      if (city.governorateId != store.governorateId) {
        throw StateError('City does not belong to the governorate.');
      }
      if (!city.isActive) throw StateError('City is not active.');
      final clash = _stores.any((s) =>
          s.id != store.id &&
          s.isActive &&
          s.cityId == cityId &&
          s.category.toLowerCase() == store.category.toLowerCase());
      if (clash) {
        throw StateError('An active exclusive store already exists.');
      }
    }
    if (previous != null &&
        previous.isActive &&
        previous.cityId != null &&
        (!store.isActive || previous.cityId != cityId)) {
      _renumber(activeStoresOfCity(previous.cityId!, except: store.id)
          .map((s) => s.id)
          .toList());
    }
    var saved = store;
    if (!store.isActive || cityId == null) {
      saved = store.copyWith(displayOrder: 0);
      _put(index, saved);
    } else {
      final sameCity =
          previous != null && previous.isActive && previous.cityId == cityId;
      final requested = store.displayOrder > 0
          ? store.displayOrder
          : (sameCity ? previous.displayOrder : null);
      final siblings = activeStoresOfCity(cityId, except: store.id);
      final order = insertAtPosition(
          siblings.map((s) => s.id).toList(), store.id, requested);
      saved = store.copyWith(displayOrder: order.indexOf(store.id) + 1);
      _put(index, saved);
      _renumber(order);
    }
    notifyListeners();
    return _stores.firstWhere((s) => s.id == store.id);
  }

  void _put(int index, PartnerStore store) {
    if (index < 0) {
      _stores.add(store);
    } else {
      _stores[index] = store;
    }
  }

  void setCurrentCustomer(Customer customer) {
    currentCustomer = customer;
    final index = _customers.indexWhere((item) => item.id == customer.id);
    if (index >= 0) _customers[index] = customer;
    notifyListeners();
  }

  void addBanner(Banner banner) {
    _banners.add(banner);
    notifyListeners();
  }

  void updateBanner(Banner banner) {
    final index = _banners.indexWhere((item) => item.id == banner.id);
    if (index < 0) return;
    _banners[index] = banner;
    notifyListeners();
  }

  void deleteBanner(String bannerId) {
    _banners.removeWhere((item) => item.id == bannerId);
    notifyListeners();
  }

  void addGovernorate(Governorate governorate) {
    _governorates.add(governorate);
    notifyListeners();
  }

  void updateGovernorate(Governorate governorate) {
    final index = _governorates.indexWhere((item) => item.id == governorate.id);
    if (index < 0) return;
    _governorates[index] = governorate;
    notifyListeners();
  }

  void registerCustomer({
    required String name,
    String? governorate,
    required AuthMethod authMethod,
    String? phone,
  }) {
    final customer = Customer(
      id: 'cust-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      phone: phone?.trim(),
      authMethod: authMethod,
      governorate: governorate ?? '',
      pointsBalance: 0,
      createdAt: DateTime.now(),
    );
    _customers.add(customer);
    currentCustomer = customer;
    notifyListeners();
  }

  bool loginMerchant(String email, String password) {
    final normalized = email.trim().toLowerCase();
    final matches = _merchantAccounts.where(
      (item) =>
          item.email.toLowerCase() == normalized &&
          item.demoPassword == password.trim(),
    );
    if (matches.isEmpty) return false;
    currentMerchant = matches.first;
    notifyListeners();
    return true;
  }

  void logoutCustomer() {
    currentCustomer = null;
    notifyListeners();
  }

  void logoutMerchant() {
    currentMerchant = null;
    notifyListeners();
  }

  void updateMinCashWithdrawal(int value) {
    if (value < 0) throw ArgumentError.value(value, 'value');
    minCashWithdrawalSyp = value;
    notifyListeners();
  }

  void updatePointValue(double value) {
    if (value <= 0) throw ArgumentError.value(value, 'value');
    pointValueSyp = value;
    notifyListeners();
  }

  void grantPoints(String customerId, int points) {
    if (points <= 0) return;
    _changeCustomerPoints(customerId, points);
  }

  void deductPoints(String customerId, int points) {
    if (points <= 0) return;
    _changeCustomerPoints(customerId, -points);
  }

  void removeCustomer(String customerId) {
    _customers.removeWhere((item) => item.id == customerId);
    _transactions.removeWhere((item) => item.customerId == customerId);
    _cashRequests.removeWhere((item) => item.customerId == customerId);
    if (currentCustomer?.id == customerId) currentCustomer = null;
    notifyListeners();
  }

  void updatePartnerStore(String storeId, PartnerStore updated) {
    final index = _stores.indexWhere((item) => item.id == storeId);
    if (index < 0) return;
    _stores[index] = updated;
    notifyListeners();
  }

  // Soft delete only: marks the store inactive. Never removes it (or any
  // transaction/settlement data) from the in-memory store. The demo
  // MerchantAccount model here has no isActive concept, so — unlike the
  // real backend — there is nothing further to deactivate for it.
  void deleteStore(String storeId) {
    final index = _stores.indexWhere((item) => item.id == storeId);
    if (index < 0) return;
    final previous = _stores[index];
    _stores[index] = previous.copyWith(isActive: false, displayOrder: 0);
    if (previous.isActive && previous.cityId != null) {
      _renumber(activeStoresOfCity(previous.cityId!, except: storeId)
          .map((s) => s.id)
          .toList());
    }
    notifyListeners();
  }

  void addPartnerStore() {
    _stores.add(
      PartnerStore(
        id: 'store-${DateTime.now().microsecondsSinceEpoch}',
        name: 'محل جديد',
        category: 'فئة جديدة',
        commissionRate: 5,
        description: '',
        location: 'المدينة - الحي',
        iconSeed: _stores.length,
        governorateId: _governorates.isNotEmpty ? _governorates.first.id : '',
      ),
    );
    notifyListeners();
  }

  void updateDigitalProduct(String productId, DigitalProduct updated) {
    final index = _products.indexWhere((item) => item.id == productId);
    if (index < 0) return;
    _products[index] = updated;
    notifyListeners();
  }

  void addDigitalProduct() {
    _products.add(
      DigitalProduct(
        id: 'product-${DateTime.now().microsecondsSinceEpoch}',
        name: 'منتج جديد',
        costInPoints: 100,
        iconSeed: _products.length,
      ),
    );
    notifyListeners();
  }

  MerchantAccount addMerchantAccount(String storeId) {
    final store = _stores.firstWhere((item) => item.id == storeId);
    final count =
        _merchantAccounts.where((item) => item.storeId == storeId).length + 1;
    final account = MerchantAccount(
      id: 'merchant-${DateTime.now().microsecondsSinceEpoch}',
      storeId: storeId,
      email: '${_emailSlug(store.name)}$count@yallacash.app',
      demoPassword:
          (100000 + DateTime.now().microsecondsSinceEpoch % 900000).toString(),
    );
    _merchantAccounts.add(account);
    notifyListeners();
    return account;
  }

  void settleCashRequest(String requestId) {
    final index = _cashRequests.indexWhere((item) => item.id == requestId);
    if (index < 0 || _cashRequests[index].status != CashRequestStatus.pending) {
      return;
    }
    final request = _cashRequests[index];
    _changeCustomerPoints(request.customerId, -request.pointsRequested,
        notify: false);
    _cashRequests[index] = CashRedemptionRequest(
      id: request.id,
      customerId: request.customerId,
      pointsRequested: request.pointsRequested,
      cashValueSyp: request.cashValueSyp,
      status: CashRequestStatus.settled,
      createdAt: request.createdAt,
      settledAt: DateTime.now(),
    );
    notifyListeners();
  }

  void rejectCashRequest(String requestId) {
    final index = _cashRequests.indexWhere((item) => item.id == requestId);
    if (index < 0 || _cashRequests[index].status != CashRequestStatus.pending) {
      return;
    }
    final request = _cashRequests[index];
    _cashRequests[index] = CashRedemptionRequest(
      id: request.id,
      customerId: request.customerId,
      pointsRequested: request.pointsRequested,
      cashValueSyp: request.cashValueSyp,
      status: CashRequestStatus.rejected,
      createdAt: request.createdAt,
      settledAt: DateTime.now(),
    );
    notifyListeners();
  }

  void toggleStoreSettlement(String storeId) {
    if (!_settledStoreIds.add(storeId)) _settledStoreIds.remove(storeId);
    notifyListeners();
  }

  String customerQrPayload(String customerId) =>
      'yallacash://customer/$customerId?v=1&token=demo-only';

  String? customerIdFromQr(String payload) {
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.scheme != 'yallacash' || uri.host != 'customer') {
      return null;
    }
    if (uri.pathSegments.isEmpty) return null;
    final id = uri.pathSegments.first;
    return _customers.any((item) => item.id == id) ? id : null;
  }

  LoyaltyTransaction registerInvoice({
    required String customerId,
    required String storeId,
    required int amountSyp,
  }) {
    final customerIndex =
        _customers.indexWhere((item) => item.id == customerId);
    final store = _stores.firstWhere((item) => item.id == storeId);
    if (customerIndex < 0) throw StateError('Customer not found');

    final result = CommissionCalculator.calculate(
      invoiceAmountSyp: amountSyp,
      commissionRate: store.commissionRate,
      pointValueSyp: pointValueSyp,
      carriedRemainderScaled: _pointRemainderScaled[customerId] ?? 0,
    );
    final transaction = LoyaltyTransaction(
      id: 'tx-${DateTime.now().microsecondsSinceEpoch}',
      storeId: store.id,
      storeName: store.name,
      customerId: customerId,
      amountSyp: amountSyp,
      commissionRateSnapshot: store.commissionRate,
      commissionAmountSyp: result.commissionAmountSyp,
      platformRevenueSyp: result.platformRevenueSyp,
      customerShareSyp: result.customerShareSyp,
      customerPointsEarned: result.customerPoints,
      createdAt: DateTime.now(),
    );
    _transactions.insert(0, transaction);
    _pointRemainderScaled[customerId] = result.customerRemainderScaled;
    final customer = _customers[customerIndex];
    _customers[customerIndex] = customer.copyWith(
      pointsBalance: customer.pointsBalance + result.customerPoints,
    );
    if (currentCustomer?.id == customerId) {
      currentCustomer = _customers[customerIndex];
    }
    notifyListeners();
    return transaction;
  }

  CashRedemptionRequest requestCashRedemption({
    required String customerId,
    required int points,
  }) {
    if (points <= 0 || points > availablePoints(customerId)) {
      throw ArgumentError.value(points, 'points');
    }
    if (!CommissionCalculator.isWholeCashValue(points, pointValueSyp)) {
      throw ArgumentError.value(
        points,
        'points',
        'must convert to whole SYP',
      );
    }
    final request = CashRedemptionRequest(
      id: 'cash-${DateTime.now().microsecondsSinceEpoch}',
      customerId: customerId,
      pointsRequested: points,
      cashValueSyp: CommissionCalculator.cashValueFor(points, pointValueSyp),
      status: CashRequestStatus.pending,
      createdAt: DateTime.now(),
    );
    _cashRequests.insert(0, request);
    notifyListeners();
    return request;
  }

  void redeemProduct({
    required String customerId,
    required DigitalProduct product,
    String? phoneNumber,
  }) {
    if (product.requiresPhoneNumber && (phoneNumber?.trim().length ?? 0) < 8) {
      throw ArgumentError('Phone number is required');
    }
    final index = _customers.indexWhere((item) => item.id == customerId);
    if (index < 0 || product.costInPoints > availablePoints(customerId)) {
      throw StateError('Insufficient points');
    }
    final customer = _customers[index];
    _customers[index] = customer.copyWith(
      pointsBalance: customer.pointsBalance - product.costInPoints,
    );
    if (currentCustomer?.id == customerId) currentCustomer = _customers[index];
    notifyListeners();
  }

  void _changeCustomerPoints(String customerId, int delta,
      {bool notify = true}) {
    final index = _customers.indexWhere((item) => item.id == customerId);
    if (index < 0) return;
    final customer = _customers[index];
    final next = (customer.pointsBalance + delta).clamp(0, 1 << 62).toInt();
    _customers[index] = customer.copyWith(pointsBalance: next);
    if (currentCustomer?.id == customerId) currentCustomer = _customers[index];
    if (notify) notifyListeners();
  }

  static String _emailSlug(String source) {
    final normalized =
        source.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '').trim();
    return normalized.isEmpty
        ? 'store'
        : normalized.substring(0, normalized.length.clamp(1, 10).toInt());
  }

  static LoyaltyTransaction _seedTransaction({
    required String id,
    required PartnerStore store,
    required String customerId,
    required int amountSyp,
    required DateTime createdAt,
  }) {
    final result = CommissionCalculator.calculate(
      invoiceAmountSyp: amountSyp,
      commissionRate: store.commissionRate,
      pointValueSyp: 5,
    );
    return LoyaltyTransaction(
      id: id,
      storeId: store.id,
      storeName: store.name,
      customerId: customerId,
      amountSyp: amountSyp,
      commissionRateSnapshot: store.commissionRate,
      commissionAmountSyp: result.commissionAmountSyp,
      platformRevenueSyp: result.platformRevenueSyp,
      customerShareSyp: result.customerShareSyp,
      customerPointsEarned: result.customerPoints,
      createdAt: createdAt,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
