import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yalla_cash_core/src/core/failure.dart';
import 'package:yalla_cash_core/src/domain/yalla_cash_repository.dart';
import 'package:yalla_cash_core/src/models.dart';

const _unset = Object();

/// Builds a user-visible failure for exceptions that are not
/// [YallaCashFailure] (mapping bugs, unexpected runtime errors, ...).
///
/// These are logged and surfaced instead of being swallowed or crashing the
/// whole app.
YallaCashFailure _unexpectedFailure(Object error, StackTrace stackTrace) {
  debugPrint('YALLA CASH UNEXPECTED ERROR: $error');
  debugPrint('$stackTrace');
  return YallaCashFailure(
    code: 'unexpected_error',
    message: 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    details: error,
  );
}

class CustomerAppState extends Equatable {
  const CustomerAppState({
    this.status = LoadStatus.initial,
    this.session,
    this.customer,
    this.points,
    this.qrToken,
    this.stores = const [],
    this.transactions = const [],
    this.products = const [],
    this.cashRequests = const [],
    this.productRedemptions = const [],
    this.banners = const [],
    this.failure,
  });

  final LoadStatus status;
  final AuthSession? session;
  final Customer? customer;
  final PointsSummary? points;
  final CustomerQrToken? qrToken;
  final List<PartnerStore> stores;
  final List<LoyaltyTransaction> transactions;
  final List<DigitalProduct> products;
  final List<CashRedemptionRequest> cashRequests;

  /// The customer's own digital-product redemption requests (PENDING,
  /// FULFILLED, REJECTED), newest first — persistent history, loaded as
  /// secondary/background startup data alongside the other lists below.
  final List<ProductRedemption> productRedemptions;

  /// Home-page banners. Owned by the Cubit (not local widget state) so that
  /// every refresh() reflects the latest admin-managed banners.
  final List<Banner> banners;
  final YallaCashFailure? failure;

  bool get isAuthenticated => session?.role == YallaUserRole.customer;

  CustomerAppState copyWith({
    LoadStatus? status,
    Object? session = _unset,
    Object? customer = _unset,
    Object? points = _unset,
    Object? qrToken = _unset,
    List<PartnerStore>? stores,
    List<LoyaltyTransaction>? transactions,
    List<DigitalProduct>? products,
    List<CashRedemptionRequest>? cashRequests,
    List<ProductRedemption>? productRedemptions,
    List<Banner>? banners,
    Object? failure = _unset,
  }) =>
      CustomerAppState(
        status: status ?? this.status,
        session:
            identical(session, _unset) ? this.session : session as AuthSession?,
        customer:
            identical(customer, _unset) ? this.customer : customer as Customer?,
        points:
            identical(points, _unset) ? this.points : points as PointsSummary?,
        qrToken: identical(qrToken, _unset)
            ? this.qrToken
            : qrToken as CustomerQrToken?,
        stores: stores ?? this.stores,
        transactions: transactions ?? this.transactions,
        products: products ?? this.products,
        cashRequests: cashRequests ?? this.cashRequests,
        productRedemptions: productRedemptions ?? this.productRedemptions,
        banners: banners ?? this.banners,
        failure: identical(failure, _unset)
            ? this.failure
            : failure as YallaCashFailure?,
      );

  @override
  List<Object?> get props => [
        status,
        session,
        customer,
        points,
        qrToken,
        stores,
        transactions,
        products,
        cashRequests,
        productRedemptions,
        banners,
        failure,
      ];
}

class CustomerAppCubit extends Cubit<CustomerAppState> {
  CustomerAppCubit(this._repository) : super(const CustomerAppState());

  /// Returns null when the claim could not be completed, so the UI never
  /// reports a reward the server did not grant.
  Future<ShareRewardResult?> claimShareReward() async {
    try {
      final result = await _repository.claimShareReward();
      await refresh();
      return result;
    } on Object {
      return null;
    }
  }

  final YallaCashRepository _repository;

  /// In-flight guard for [updateGovernorate]: prevents overlapping
  /// governorate-change operations (e.g. a rapid double-tap on two
  /// governorates) from racing each other and leaving stale/mixed
  /// stores or banners in state. Always released via try/finally.
  bool _changingGovernorate = false;

  /// Restores the session using ONLY the minimum request needed to confirm
  /// the saved token is still valid and load the customer's identity
  /// (`getCustomerProfile`). This is what unblocks the startup spinner.
  ///
  /// The remaining startup data (points, stores, transactions, products,
  /// cash requests, banners) is then loaded in the background via
  /// [_loadSecondaryStartupData] — a startup-only loader that deliberately
  /// excludes getCustomerProfile() (already fetched above) so startup never
  /// performs a redundant second profile request — so a slow/failing
  /// non-critical request can never delay or block the app from becoming
  /// interactive.
  Future<void> restoreSession() async {
    final localLookupStopwatch = Stopwatch()..start();
    try {
      emit(state.copyWith(status: LoadStatus.loading, failure: null));
      final hasSavedSession = await _repository.hasSavedSession();
      if (kDebugMode) {
        debugPrint(
          'CUSTOMER_STARTUP local_session_lookup_ms=${localLookupStopwatch.elapsedMilliseconds} has_session=$hasSavedSession',
        );
      }
      if (!hasSavedSession) {
        emit(const CustomerAppState());
        return;
      }

      final profileStopwatch = Stopwatch()..start();
      final customer = await _repository.getCustomerProfile();
      if (kDebugMode) {
        debugPrint(
          'CUSTOMER_STARTUP profile_request_ms=${profileStopwatch.elapsedMilliseconds}',
        );
      }
      emit(state.copyWith(
        status: LoadStatus.success,
        customer: customer,
        failure: null,
      ));
      if (kDebugMode) {
        debugPrint('CUSTOMER_STARTUP secondary_data_kicked_off');
      }
      unawaited(_loadSecondaryStartupData());
    } on YallaCashFailure catch (failure) {
      if (failure.statusCode == 401 || failure.code == 'unauthorized') {
        // Invalid/expired session -> clean logout state (intentional).
        emit(const CustomerAppState());
        return;
      }
      emit(state.copyWith(status: LoadStatus.failure, failure: failure));
    } on Object catch (error, stackTrace) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
    }
  }

  Future<PhoneOtpChallenge?> startPhoneOtp(String phone) async {
    try {
      emit(state.copyWith(status: LoadStatus.loading, failure: null));
      final challenge = await _repository.startCustomerPhoneOtp(phone);
      emit(state.copyWith(status: LoadStatus.success, failure: null));
      return challenge;
    } on YallaCashFailure catch (failure) {
      emit(state.copyWith(status: LoadStatus.failure, failure: failure));
      return null;
    } on Object catch (error, stackTrace) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
      return null;
    }
  }

  Future<void> verifyPhoneOtp({
    required String challengeId,
    required String phone,
    required String code,
    required String name,
    required String governorate,
  }) async {
    await _run(() async {
      final session = await _repository.verifyCustomerPhoneOtp(
        challengeId: challengeId,
        phone: phone,
        code: code,
        name: name,
        governorate: governorate,
      );
      emit(state.copyWith(session: session, customer: session.customer));
      await refresh();
    });
  }

  Future<void> signInWithOAuth({
    required AuthMethod provider,
    required String firebaseIdToken,
    required String name,
    required String governorate,
  }) async {
    await _run(() async {
      final session = await _repository.signInCustomerWithOAuth(
        provider: provider,
        firebaseIdToken: firebaseIdToken,
        name: name,
        governorate: governorate,
      );
      emit(state.copyWith(session: session, customer: session.customer));
      await refresh();
    });
  }

  Future<void> refresh() async {
    await _run(() async {
      final results = await _loadCustomerData();
      emit(
        state.copyWith(
          status: LoadStatus.success,
          customer: results[0] as Customer,
          points: results[1] as PointsSummary,
          stores: results[2] as List<PartnerStore>,
          transactions: results[3] as List<LoyaltyTransaction>,
          products: results[4] as List<DigitalProduct>,
          cashRequests: results[5] as List<CashRedemptionRequest>,
          productRedemptions: results[6] as List<ProductRedemption>,
          banners: results[7] as List<Banner>,
          failure: null,
        ),
      );
    });
  }

  /// Best-effort: a failed device-token registration must never disrupt the
  /// rest of the app, so failures are swallowed rather than surfaced.
  Future<void> registerDeviceToken(String token) async {
    _deviceToken = token;
    try {
      await _repository.registerDeviceToken(token);
    } on Object {
      // Push notifications are a non-critical enhancement.
    }
  }

  /// The push token registered for the signed-in account on this device.
  String? _deviceToken;

  /// Only one governorate change can run at a time — a second call while one
  /// is already in flight is ignored (not queued), so a rapid double-tap
  /// can never race two overlapping updateGovernorate()+refresh() cycles
  /// against each other. The guard is always released, including on
  /// failure, since it's cleared in `finally`.
  Future<void> updateGovernorate(String governorateId) async {
    if (_changingGovernorate) return;
    _changingGovernorate = true;
    try {
      await _run(() async {
        final customer =
            await _repository.updateCustomerGovernorate(governorateId);
        emit(state.copyWith(customer: customer, qrToken: null));
        await refresh();
      });
    } finally {
      _changingGovernorate = false;
    }
  }

  Future<void> issueQrToken() async {
    await _run(() async {
      final qr = await _repository.issueCustomerQrToken();
      emit(state.copyWith(qrToken: qr));
    });
  }

  Future<void> requestCashRedemption(int points) async {
    await _run(() async {
      await _repository.requestCashRedemption(points);
      await refresh();
    });
  }

  Future<void> redeemDigitalProduct(DigitalProduct product,
      {String? phoneNumber}) async {
    await _run(() async {
      await _repository.redeemDigitalProduct(
          product: product, phoneNumber: phoneNumber);
      await refresh();
    });
  }

  /// Removes this device's push token from the account before the session is
  /// cleared. Logout never waits on the network for long and never fails
  /// because of it: if the call fails or times out, the backend still drops
  /// tokens that FCM rejects, and the app deletes its local token on sign-out.
  Future<void> logout() async {
    final token = _deviceToken;
    _deviceToken = null;
    if (token != null) {
      try {
        await _repository
            .unregisterDeviceToken(token)
            .timeout(const Duration(seconds: 5));
      } on Object {
        // Offline or slow network: logout continues without the removal.
      }
    }
    await _repository.logout();
    emit(const CustomerAppState());
  }

  /// Loads every piece of customer data in parallel. Banners are included so
  /// a single refresh() always reflects the latest server state.
  ///
  /// Stores are scoped to the customer's currently selected governorate
  /// (mirrors how listActiveBanners() is already scoped server-side), so a
  /// governorate switch always shows only that governorate's stores — never
  /// a stale/other governorate's as a fallback.
  Future<List<Object>> _loadCustomerData() => Future.wait<Object>([
        _repository.getCustomerProfile(),
        _repository.getCustomerPoints(),
        _repository.listActiveStores(
            governorateId: state.customer?.governorateId),
        _repository.listCustomerTransactions(),
        _repository.listDigitalProducts(),
        _repository.listCustomerCashRequests(),
        _repository.listCustomerProductRedemptions(),
        _repository.listActiveBanners(placement: 'HOME'),
      ]);

  /// Startup-only background loader used by [restoreSession] after it has
  /// already fetched the profile. Loads everything [_loadCustomerData]
  /// would, EXCEPT getCustomerProfile() — avoiding the redundant second
  /// profile request a plain [refresh] would otherwise perform on startup.
  /// A failure here is non-fatal: it updates [CustomerAppState.failure] but
  /// never resets the already-restored session/customer.
  Future<void> _loadSecondaryStartupData() async {
    try {
      final results = await Future.wait<Object>([
        _repository.getCustomerPoints(),
        _repository.listActiveStores(
            governorateId: state.customer?.governorateId),
        _repository.listCustomerTransactions(),
        _repository.listDigitalProducts(),
        _repository.listCustomerCashRequests(),
        _repository.listCustomerProductRedemptions(),
        _repository.listActiveBanners(placement: 'HOME'),
      ]);
      emit(state.copyWith(
        status: LoadStatus.success,
        points: results[0] as PointsSummary,
        stores: results[1] as List<PartnerStore>,
        transactions: results[2] as List<LoyaltyTransaction>,
        products: results[3] as List<DigitalProduct>,
        cashRequests: results[4] as List<CashRedemptionRequest>,
        productRedemptions: results[5] as List<ProductRedemption>,
        banners: results[6] as List<Banner>,
        failure: null,
      ));
    } on YallaCashFailure catch (failure) {
      emit(state.copyWith(status: LoadStatus.failure, failure: failure));
    } on Object catch (error, stackTrace) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      emit(state.copyWith(status: LoadStatus.loading, failure: null));
      await action();
      if (state.status == LoadStatus.loading) {
        emit(state.copyWith(status: LoadStatus.success, failure: null));
      }
    } on YallaCashFailure catch (failure) {
      emit(state.copyWith(status: LoadStatus.failure, failure: failure));
    } on Object catch (error, stackTrace) {
      // Surface unexpected errors visibly instead of crashing or hiding them.
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
    }
  }
}

class MerchantAppState extends Equatable {
  const MerchantAppState({
    this.status = LoadStatus.initial,
    this.session,
    this.workspace,
    this.scannedCustomer,
    this.lastTransaction,
    this.failure,
  });

  final LoadStatus status;
  final AuthSession? session;
  final MerchantWorkspaceSnapshot? workspace;
  final Customer? scannedCustomer;
  final LoyaltyTransaction? lastTransaction;
  final YallaCashFailure? failure;

  bool get isAuthenticated => session?.role == YallaUserRole.merchant;

  MerchantAppState copyWith({
    LoadStatus? status,
    Object? session = _unset,
    Object? workspace = _unset,
    Object? scannedCustomer = _unset,
    Object? lastTransaction = _unset,
    Object? failure = _unset,
  }) =>
      MerchantAppState(
        status: status ?? this.status,
        session:
            identical(session, _unset) ? this.session : session as AuthSession?,
        workspace: identical(workspace, _unset)
            ? this.workspace
            : workspace as MerchantWorkspaceSnapshot?,
        scannedCustomer: identical(scannedCustomer, _unset)
            ? this.scannedCustomer
            : scannedCustomer as Customer?,
        lastTransaction: identical(lastTransaction, _unset)
            ? this.lastTransaction
            : lastTransaction as LoyaltyTransaction?,
        failure: identical(failure, _unset)
            ? this.failure
            : failure as YallaCashFailure?,
      );

  @override
  List<Object?> get props => [
        status,
        session,
        workspace,
        scannedCustomer,
        lastTransaction,
        failure,
      ];
}

class MerchantAppCubit extends Cubit<MerchantAppState> {
  MerchantAppCubit(this._repository) : super(const MerchantAppState());

  final YallaCashRepository _repository;

  Future<void> restoreSession() async {
    try {
      emit(state.copyWith(status: LoadStatus.loading, failure: null));
      final workspace = await _repository.getMerchantWorkspace();
      emit(
        state.copyWith(
          status: LoadStatus.success,
          workspace: workspace,
          failure: null,
        ),
      );
    } on YallaCashFailure catch (failure) {
      if (failure.statusCode == 401 || failure.code == 'unauthorized') {
        emit(const MerchantAppState());
        return;
      }
      emit(state.copyWith(status: LoadStatus.failure, failure: failure));
    } on Object catch (error, stackTrace) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      emit(state.copyWith(
        status: LoadStatus.loading,
        failure: null,
      ));

      // FIX: merchant accounts must authenticate through the MERCHANT login
      // endpoint (/auth/merchant/login). Calling signInAdmin here made the
      // backend filter by role=ADMIN, so valid merchant credentials were
      // always rejected with "Email or password is incorrect."
      final session = await _repository.signInMerchant(
        email: email,
        password: password,
      );

      emit(state.copyWith(
        session: session,
        status: LoadStatus.success,
        failure: null,
      ));

      unawaited(refresh());
    } on YallaCashFailure catch (failure) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: failure,
      ));
    } on Object catch (error, stackTrace) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
    }
  }

  Future<void> refresh() async {
    await _run(() async {
      final workspace = await _repository.getMerchantWorkspace();
      emit(state.copyWith(workspace: workspace, failure: null));
    });
  }

  Future<void> registerDevice(
      {required String fingerprint, required String label}) async {
    await _run(() => _repository.registerMerchantDevice(
        fingerprint: fingerprint, label: label));
  }

  Future<void> resolveQr(String payload) async {
    await _run(() async {
      final customer = await _repository.resolveCustomerQr(payload);
      emit(state.copyWith(scannedCustomer: customer, lastTransaction: null));
    });
  }

  Future<void> registerInvoice({
    required String customerQrPayload,
    required int amountSyp,
    required String idempotencyKey,
  }) async {
    await _run(() async {
      final transaction = await _repository.registerInvoice(
        customerQrPayload: customerQrPayload,
        amountSyp: amountSyp,
        idempotencyKey: idempotencyKey,
      );
      emit(state.copyWith(lastTransaction: transaction));
      await refresh();
    });
  }

  Future<void> logout() async {
    await _repository.logout();
    emit(const MerchantAppState());
  }

  void resetSaleFlow() {
    emit(
      state.copyWith(
        status:
            state.workspace == null ? LoadStatus.initial : LoadStatus.success,
        scannedCustomer: null,
        lastTransaction: null,
        failure: null,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      emit(state.copyWith(status: LoadStatus.loading, failure: null));
      await action();
      if (state.status == LoadStatus.loading) {
        emit(state.copyWith(status: LoadStatus.success, failure: null));
      }
    } on YallaCashFailure catch (failure) {
      emit(state.copyWith(status: LoadStatus.failure, failure: failure));
    } on Object catch (error, stackTrace) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
    }
  }
}

class AdminAppState extends Equatable {
  const AdminAppState({
    this.status = LoadStatus.initial,
    this.session,
    this.overview,
    this.customers = const [],
    this.stores = const [],
    this.products = const [],
    this.cashRequests = const [],
    this.productRedemptions = const [],
    this.merchantAccounts = const [],
    this.settlements = const [],
    this.recentTransactions = const [],
    this.pointValueSyp,
    this.minCashWithdrawalSyp,
    this.shareRewardPoints,
    this.failure,
  });

  final LoadStatus status;
  final AuthSession? session;
  final AdminOverviewSnapshot? overview;
  final List<Customer> customers;
  final List<PartnerStore> stores;
  final List<DigitalProduct> products;
  final List<CashRedemptionRequest> cashRequests;
  final List<ProductRedemption> productRedemptions;
  final List<MerchantAccount> merchantAccounts;
  final List<MerchantSettlementSummary> settlements;

  /// Latest loyalty transactions shown in the overview "recent activity"
  /// table. Previously this table rendered a hardcoded empty list.
  final List<LoyaltyTransaction> recentTransactions;
  final double? pointValueSyp;

  /// Configured minimum cash payout in SYP. Stored only; not enforced yet.
  final int? minCashWithdrawalSyp;

  /// Points granted once per customer for sharing the app. 0 disables it.
  final int? shareRewardPoints;
  final YallaCashFailure? failure;

  bool get isAuthenticated => session?.role == YallaUserRole.admin;

  AdminAppState copyWith({
    LoadStatus? status,
    Object? session = _unset,
    Object? overview = _unset,
    List<Customer>? customers,
    List<PartnerStore>? stores,
    List<DigitalProduct>? products,
    List<CashRedemptionRequest>? cashRequests,
    List<ProductRedemption>? productRedemptions,
    List<MerchantAccount>? merchantAccounts,
    List<MerchantSettlementSummary>? settlements,
    List<LoyaltyTransaction>? recentTransactions,
    Object? pointValueSyp = _unset,
    Object? minCashWithdrawalSyp = _unset,
    Object? shareRewardPoints = _unset,
    Object? failure = _unset,
  }) =>
      AdminAppState(
        status: status ?? this.status,
        session:
            identical(session, _unset) ? this.session : session as AuthSession?,
        overview: identical(overview, _unset)
            ? this.overview
            : overview as AdminOverviewSnapshot?,
        customers: customers ?? this.customers,
        stores: stores ?? this.stores,
        products: products ?? this.products,
        cashRequests: cashRequests ?? this.cashRequests,
        productRedemptions: productRedemptions ?? this.productRedemptions,
        merchantAccounts: merchantAccounts ?? this.merchantAccounts,
        settlements: settlements ?? this.settlements,
        recentTransactions: recentTransactions ?? this.recentTransactions,
        pointValueSyp: identical(pointValueSyp, _unset)
            ? this.pointValueSyp
            : pointValueSyp as double?,
        minCashWithdrawalSyp: identical(minCashWithdrawalSyp, _unset)
            ? this.minCashWithdrawalSyp
            : minCashWithdrawalSyp as int?,
        shareRewardPoints: identical(shareRewardPoints, _unset)
            ? this.shareRewardPoints
            : shareRewardPoints as int?,
        failure: identical(failure, _unset)
            ? this.failure
            : failure as YallaCashFailure?,
      );

  @override
  List<Object?> get props => [
        status,
        session,
        overview,
        customers,
        stores,
        products,
        cashRequests,
        productRedemptions,
        merchantAccounts,
        settlements,
        recentTransactions,
        pointValueSyp,
        minCashWithdrawalSyp,
        shareRewardPoints,
        failure,
      ];
}

class AdminAppCubit extends Cubit<AdminAppState> {
  AdminAppCubit(this._repository) : super(const AdminAppState());

  final YallaCashRepository _repository;

  /// Monotonic refresh generation counter.
  ///
  /// Every refresh() call takes the next generation id; only the result of
  /// the LATEST generation may be emitted. Older concurrent refreshes are
  /// discarded when they finish late, so a stale snapshot can never
  /// overwrite newer state (e.g. resurrecting deleted rows or hiding new
  /// ones until an arbitrary later refresh).
  int _refreshGeneration = 0;

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _run(() async {
      final session =
          await _repository.signInAdmin(email: email, password: password);
      emit(state.copyWith(session: session));
      await refresh();
    });
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    try {
      emit(state.copyWith(status: LoadStatus.loading, failure: null));

      final results = await Future.wait<Object>([
        _repository.getAdminOverview(),
        _repository.listAdminCustomers(),
        _repository.listAdminStores(),
        _repository.listAdminProducts(),
        _repository.listAdminCashRequests(status: 'pending'),
        _repository.listAdminProductRedemptions(status: 'pending'),
        _repository.listMerchantAccounts(),
        _repository.listSettlements(),
        _repository.getPointValue(),
        _repository.listAdminRecentTransactions(limit: 8),
        _repository.getMinCashWithdrawal(),
        _repository.getShareRewardPoints(),
      ]);

      // A newer refresh has started while this one was in flight: discard
      // this stale snapshot entirely.
      if (generation != _refreshGeneration) return;

      emit(
        state.copyWith(
          status: LoadStatus.success,
          overview: results[0] as AdminOverviewSnapshot,
          customers: results[1] as List<Customer>,
          stores: results[2] as List<PartnerStore>,
          products: results[3] as List<DigitalProduct>,
          cashRequests: results[4] as List<CashRedemptionRequest>,
          productRedemptions: results[5] as List<ProductRedemption>,
          merchantAccounts: results[6] as List<MerchantAccount>,
          settlements: results[7] as List<MerchantSettlementSummary>,
          pointValueSyp: results[8] as double,
          recentTransactions: results[9] as List<LoyaltyTransaction>,
          minCashWithdrawalSyp: results[10] as int,
          shareRewardPoints: results[11] as int,
          failure: null,
        ),
      );
    } on YallaCashFailure catch (failure) {
      if (generation != _refreshGeneration) return;
      // Keep the currently displayed data, but DO NOT fake success: the
      // failure is stored in state so the UI can surface it.
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          failure: failure,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (generation != _refreshGeneration) return;
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          failure: _unexpectedFailure(error, stackTrace),
        ),
      );
    }
  }

  Future<bool> grantPoints(Customer customer, int points, String note) =>
      _run(() async {
        await _repository.grantCustomerPoints(
          customerId: customer.id,
          points: points,
          note: note,
        );
        await refresh();
      });

  Future<bool> deductPoints(Customer customer, int points, String note) =>
      _run(() async {
        await _repository.deductCustomerPoints(
          customerId: customer.id,
          points: points,
          note: note,
        );
        await refresh();
      });

  Future<bool> deleteCustomer(Customer customer) => _run(() async {
        await _repository.deleteCustomer(customer.id);
        await refresh();
      });

  Future<bool> resolveCashRequest(
          CashRedemptionRequest request, bool approve) =>
      _run(() async {
        await _repository.resolveCashRequest(
            requestId: request.id, approve: approve);
        await refresh();
      });

  Future<bool> resolveProductRedemption(
          ProductRedemption redemption, bool approve) =>
      _run(() async {
        await _repository.resolveProductRedemption(
            redemptionId: redemption.id, approve: approve);
        await refresh();
      });

  /// Returns the recorded broadcast, or null when the request failed. The same
  /// [idempotencyKey] may be retried safely: the server returns the original.
  Future<NotificationBroadcast?> sendGeneralNotification({
    required String title,
    required String body,
    required String idempotencyKey,
  }) async {
    try {
      return await _repository.sendGeneralNotification(
        title: title,
        body: body,
        idempotencyKey: idempotencyKey,
      );
    } on Object {
      return null;
    }
  }

  /// Newest broadcasts first; a failed load shows an empty history.
  Future<List<NotificationBroadcast>> listNotificationBroadcasts() async {
    try {
      return await _repository.listNotificationBroadcasts();
    } on Object {
      return const [];
    }
  }

  /// The new store's id is assigned by the server, so the logo is uploaded
  /// only after the store has been created.
  Future<bool> createStore(PartnerStore store, {StoreLogoUpload? logo}) =>
      _run(() async {
        final saved = await _repository.createStore(store);
        if (logo != null) await _repository.setStoreLogo(saved.id, logo);
        await refresh();
      });

  Future<bool> updateStore(
    PartnerStore store, {
    StoreLogoUpload? logo,
    bool removeLogo = false,
  }) =>
      _run(() async {
        await _repository.updateStore(store);
        if (logo != null) {
          await _repository.setStoreLogo(store.id, logo);
        } else if (removeLogo) {
          await _repository.removeStoreLogo(store.id);
        }
        await refresh();
      });

  Future<bool> deleteStore(PartnerStore store) => _run(() async {
        await _repository.deleteStore(store.id);
        await refresh();
      });

  /// The server assigns new product ids, so an image is uploaded only after
  /// the product has been created.
  Future<bool> createProduct(DigitalProduct product,
          {StoreLogoUpload? image}) =>
      _run(() async {
        final saved = await _repository.createProduct(product);
        if (image != null) await _repository.setProductImage(saved.id, image);
        await refresh();
      });

  Future<bool> updateProduct(
    DigitalProduct product, {
    StoreLogoUpload? image,
    bool removeImage = false,
  }) =>
      _run(() async {
        await _repository.updateProduct(product);
        if (image != null) {
          await _repository.setProductImage(product.id, image);
        } else if (removeImage) {
          await _repository.removeProductImage(product.id);
        }
        await refresh();
      });

  Future<IssuedMerchantAccount?> createMerchantAccount({
    required String storeId,
    required String email,
    String? password,
    String? displayLabel,
  }) async {
    try {
      emit(state.copyWith(status: LoadStatus.loading, failure: null));
      final account = await _repository.createMerchantAccount(
        storeId: storeId,
        email: email,
        password: password,
        displayLabel: displayLabel,
      );
      await refresh();
      return account;
    } on YallaCashFailure catch (failure) {
      emit(state.copyWith(status: LoadStatus.failure, failure: failure));
      return null;
    } on Object catch (error, stackTrace) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
      return null;
    }
  }

  /// Null when the preview cannot be loaded; nothing is changed by previewing.
  Future<MonthlySettlementPreview?> previewMonthlySettlement(
      String month) async {
    try {
      return await _repository.previewMonthlySettlement(month);
    } on Object {
      return null;
    }
  }

  /// Null when the run request fails. Successful merchants stay settled even
  /// when others fail, and the result lists each merchant's outcome.
  Future<MonthlySettlementRunResult?> runMonthlySettlement(String month) async {
    try {
      final result = await _repository.runMonthlySettlement(month);
      await refresh();
      return result;
    } on Object {
      return null;
    }
  }

  Future<List<MonthlySettlementRecord>> listMonthlySettlementHistory() async {
    try {
      return await _repository.listMonthlySettlementHistory();
    } on Object {
      return const [];
    }
  }

  Future<bool> settleStore(MerchantSettlementSummary settlement) =>
      _run(() async {
        await _repository.settleStore(
          storeId: settlement.storeId,
          periodStart: settlement.periodStart,
          periodEnd: settlement.periodEnd,
        );
        await refresh();
      });

  Future<bool> updatePointValue(double pointValueSyp) => _run(() async {
        final value = await _repository.updatePointValue(pointValueSyp);
        emit(state.copyWith(pointValueSyp: value));
        await refresh();
      });

  Future<bool> updateShareRewardPoints(int points) => _run(() async {
        final value = await _repository.updateShareRewardPoints(points);
        emit(state.copyWith(shareRewardPoints: value));
        await refresh();
      });

  Future<bool> updateMinCashWithdrawal(int amountSyp) => _run(() async {
        final value =
            await _repository.updateMinCashWithdrawal(amountSyp);
        emit(state.copyWith(minCashWithdrawalSyp: value));
        await refresh();
      });

  Future<void> logout() async {
    await _repository.logout();
    emit(const AdminAppState());
  }

  /// Runs [action], emitting loading/success/failure states.
  ///
  /// Returns true only when the whole action (including its trailing
  /// refresh) completed without failure, so callers can distinguish real
  /// success from silent failures.
  Future<bool> _run(Future<void> Function() action) async {
    try {
      emit(state.copyWith(status: LoadStatus.loading, failure: null));
      await action();
      if (state.status == LoadStatus.loading) {
        emit(state.copyWith(status: LoadStatus.success, failure: null));
      }
      return state.failure == null;
    } on YallaCashFailure catch (failure) {
      emit(state.copyWith(status: LoadStatus.failure, failure: failure));
      return false;
    } on Object catch (error, stackTrace) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        failure: _unexpectedFailure(error, stackTrace),
      ));
      return false;
    }
  }
}
