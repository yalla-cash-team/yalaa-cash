part of '../../customer_app.dart';

class CustomerGovernorateGate extends StatefulWidget {
  const CustomerGovernorateGate({
    required this.cubit,
    required this.state,
    required this.repository,
    required this.darkMode,
    required this.onDarkModeChanged,
    super.key,
  });

  final CustomerAppCubit cubit;
  final CustomerAppState state;
  final YallaCashRepository repository;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<CustomerGovernorateGate> createState() =>
      _CustomerGovernorateGateState();
}

class _CustomerGovernorateGateState extends State<CustomerGovernorateGate> {
  List<Governorate> governorates = const [];
  bool loading = true;
  String? error;

  // Step 2: the active cities of the selected governorate. null = still
  // loading; a governorate without cities falls back to its whole list.
  List<City>? cities;
  String? _citiesFor;
  String? citiesError;
  bool editingGovernorate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stopwatch = Stopwatch()..start();
    try {
      final items = await widget.repository.listActiveGovernorates();
      final selectedId = widget.state.customer?.governorateId;
      if (!mounted) return;
      setState(() {
        governorates = items.where((item) => item.isActive).toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        loading = false;
        error = null;
      });
      if (kDebugMode) {
        debugPrint(
          'CUSTOMER_STARTUP governorate_validation_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      if (selectedId != null &&
          governorates.any((item) => item.id == selectedId)) {
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذر تحميل المحافظات المتاحة. حاول مرة أخرى.';
      });
    }
  }

  String? _cityName() {
    final id = widget.state.customer?.cityId;
    final list = cities;
    if (id == null || list == null) return null;
    for (final city in list) {
      if (city.id == id) return city.nameAr;
    }
    return null;
  }

  Future<void> _loadCities(String governorateId) async {
    try {
      final items = await widget.repository
          .listActiveCities(governorateId: governorateId);
      if (!mounted || _citiesFor != governorateId) return;
      setState(() {
        cities = items.where((item) => item.isActive).toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        citiesError = null;
      });
    } catch (_) {
      if (!mounted || _citiesFor != governorateId) return;
      setState(() {
        cities = const [];
        citiesError = 'تعذر تحميل المدن المتاحة. حاول مرة أخرى.';
      });
    }
  }

  void _retryCities() {
    final id = _citiesFor;
    if (id == null) return;
    setState(() {
      cities = null;
      citiesError = null;
    });
    _loadCities(id);
  }

  Future<void> _selectCity(City city) async {
    try {
      await widget.cubit.updateCity(city.id);
      if (!mounted) return;
      if (widget.cubit.state.failure != null) {
        setState(() =>
            citiesError = _customerFailureMessage(widget.cubit.state.failure));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => citiesError = 'تعذر حفظ المدينة المختارة. حاول مرة أخرى.');
    }
  }

  Future<void> _select(Governorate governorate) async {
    if (editingGovernorate &&
        governorate.id == widget.state.customer?.governorateId) {
      // Same governorate again: keep the saved city, just go back to step 2.
      setState(() => editingGovernorate = false);
      return;
    }
    setState(() => loading = true);
    try {
      await widget.cubit.updateGovernorate(governorate.id);
      if (!mounted) return;
      if (widget.cubit.state.failure != null) {
        setState(() {
          loading = false;
          error = _customerFailureMessage(widget.cubit.state.failure);
        });
        return;
      }
      setState(() {
        loading = false;
        editingGovernorate = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذر حفظ المحافظة المختارة. حاول مرة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.state.customer?.governorateId;
    final hasProfileGovernorate = selectedId != null && selectedId.isNotEmpty;
    final validSelection =
        selectedId != null && governorates.any((item) => item.id == selectedId);
    if (validSelection || (loading && hasProfileGovernorate)) {
      if (validSelection) {
        if (_citiesFor != selectedId) {
          // The governorate changed: forget the old cities and fetch anew.
          _citiesFor = selectedId;
          cities = null;
          citiesError = null;
          scheduleMicrotask(() => _loadCities(selectedId));
        }
        final customer = widget.state.customer!;
        if (editingGovernorate) {
          return GovernorateSelectionScreen(
            governorates: governorates,
            error: error,
            onRetry: _load,
            onSelected: _select,
            step: 1,
            onBack: () => setState(() => editingGovernorate = false),
          );
        }
        final loaded = cities;
        final savedCity = customer.cityId;
        final savedStillValid = savedCity != null &&
            (loaded == null || loaded.any((c) => c.id == savedCity));
        if (!savedStillValid) {
          if (loaded == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          // A governorate with cities needs a city; one without keeps the
          // governorate-wide list.
          if (loaded.isNotEmpty || citiesError != null) {
            return CitySelectionScreen(
              governorateName: customer.governorate,
              cities: loaded,
              error: citiesError,
              onRetry: _retryCities,
              onSelected: _selectCity,
              onChangeGovernorate: () =>
                  setState(() => editingGovernorate = true),
            );
          }
        }
      }
      return CustomerShell(
        cubit: widget.cubit,
        state: widget.state,
        repository: widget.repository,
        darkMode: widget.darkMode,
        onDarkModeChanged: widget.onDarkModeChanged,
        cityName: _cityName(),
      );
    }
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return GovernorateSelectionScreen(
      governorates: governorates,
      error: error,
      onRetry: _load,
      onSelected: _select,
    );
  }
}

class GovernorateSelectionScreen extends StatelessWidget {
  const GovernorateSelectionScreen({
    required this.governorates,
    required this.onSelected,
    this.error,
    this.onRetry,
    this.step,
    this.onBack,
    super.key,
  });

  final List<Governorate> governorates;
  final String? error;
  final Future<void> Function(Governorate) onSelected;
  final VoidCallback? onRetry;

  /// Shows "الخطوة 1 من 2" when the picker has a city step.
  final int? step;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('المحافظة'),
          leading: onBack == null
              ? null
              : BackButton(key: const Key('location-back'), onPressed: onBack),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (step != null) _LocationStepLabel(step: step!),
                  const SizedBox(height: 24),
                  Text('اختر محافظتك',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('اختر محافظتك وابدأ بجمع نقاطك',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 28),
                  if (error != null) ...[
                    Text(error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: onRetry,
                        child: const Text('إعادة المحاولة')),
                    const SizedBox(height: 12),
                  ],
                  if (governorates.isEmpty && error == null)
                    const Text('لا توجد محافظات متاحة حالياً.',
                        textAlign: TextAlign.center)
                  else
                    ...governorates.map(
                      (governorate) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => onSelected(governorate),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 18),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(governorate.nameAr,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700))),
                                  const Icon(Icons.chevron_left_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Small "الخطوة n من 2" caption shared by the two location steps.
class _LocationStepLabel extends StatelessWidget {
  const _LocationStepLabel({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => Text(
        'الخطوة $step من 2',
        key: const Key('location-step'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
}

/// Step 2 of the location picker: the active cities of one governorate.
class CitySelectionScreen extends StatelessWidget {
  const CitySelectionScreen({
    required this.governorateName,
    required this.cities,
    required this.onSelected,
    this.error,
    this.onRetry,
    this.onChangeGovernorate,
    this.onBack,
    super.key,
  });

  final String governorateName;
  final List<City> cities;
  final String? error;
  final Future<void> Function(City) onSelected;
  final VoidCallback? onRetry;

  /// Returns to step 1 (shown as a text button under the list).
  final VoidCallback? onChangeGovernorate;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المدينة'),
        leading: onBack == null
            ? null
            : BackButton(key: const Key('location-back'), onPressed: onBack),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              key: const Key('city-list'),
              padding: const EdgeInsets.all(24),
              children: [
                const _LocationStepLabel(step: 2),
                const SizedBox(height: 24),
                Text('اختر مدينتك',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('المدن المتاحة في $governorateName',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 28),
                if (error != null) ...[
                  Text(error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 12),
                  if (onRetry != null)
                    OutlinedButton(
                        onPressed: onRetry,
                        child: const Text('إعادة المحاولة')),
                  const SizedBox(height: 12),
                ],
                ...cities.map(
                  (city) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: InkWell(
                        key: Key('city-${city.id}'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => onSelected(city),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 18),
                          child: Row(
                            children: [
                              Icon(Icons.location_city_outlined,
                                  color: scheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(city.nameAr,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700))),
                              const Icon(Icons.chevron_left_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (onChangeGovernorate != null)
                  TextButton.icon(
                    key: const Key('change-governorate'),
                    onPressed: onChangeGovernorate,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('تغيير المحافظة'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
