import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart' hide Banner;

/// Opens the city manager for one governorate: list, add, rename and
/// activate/deactivate cities. Cities are only ever added here (or from the
/// store form's explicit "add city" button), never created from free text.
Future<void> showCitiesManager(
  BuildContext context, {
  required YallaCashRepository repository,
  required Governorate governorate,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          CitiesManagerDialog(repository: repository, governorate: governorate),
    );

/// Human-readable Arabic message for a failed city operation.
String cityErrorMessage(Object error, {String fallback = 'تعذرت العملية.'}) {
  if (error is YallaCashFailure && error.message.isNotEmpty) {
    return error.statusCode == 409
        ? 'توجد مدينة بنفس الاسم أو باسم مشابه، أو لا تزال لديها محلات نشطة.'
        : error.message;
  }
  return fallback;
}

/// Asks for a city name; returns the normalized name or null if cancelled.
/// Owns its controller so it is disposed after the closing animation.
class CityNameDialog extends StatefulWidget {
  const CityNameDialog({required this.title, this.initial = '', super.key});

  final String title;
  final String initial;

  @override
  State<CityNameDialog> createState() => _CityNameDialogState();
}

class _CityNameDialogState extends State<CityNameDialog> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: const Key('new-city-name'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم المدينة'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              key: const Key('city-name-confirm'),
              onPressed: () =>
                  Navigator.pop(context, normalizeCityName(controller.text)),
              child: const Text('حفظ')),
        ],
      );
}

class CitiesManagerDialog extends StatefulWidget {
  const CitiesManagerDialog({
    required this.repository,
    required this.governorate,
    super.key,
  });

  final YallaCashRepository repository;
  final Governorate governorate;

  @override
  State<CitiesManagerDialog> createState() => _CitiesManagerDialogState();
}

class _CitiesManagerDialogState extends State<CitiesManagerDialog> {
  List<City> cities = const [];
  Map<String, int> activeStores = const {};
  bool loading = true;
  String? message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = (await widget.repository
              .listAdminCities(governorateId: widget.governorate.id))
          .toList()
        ..sort((a, b) {
          final byOrder = a.displayOrder.compareTo(b.displayOrder);
          return byOrder != 0 ? byOrder : a.nameAr.compareTo(b.nameAr);
        });
      final stores = await widget.repository.listAdminStores();
      final counts = <String, int>{};
      for (final store in stores) {
        final id = store.cityId;
        if (id != null && store.isActive) counts[id] = (counts[id] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        cities = loaded;
        activeStores = counts;
        loading = false;
        message = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        message = cityErrorMessage(error, fallback: 'تعذر تحميل المدن.');
      });
    }
  }

  /// Arabic reason when [name] cannot be used, or null when it is free.
  String? _nameProblem(String name, {String? exceptId}) {
    if (cityNameKey(name).length < 2) return 'اسم المدينة قصير جداً.';
    final clash = findCityNameClash<City>(cities, name,
        nameOf: (c) => c.nameAr, idOf: (c) => c.id, exceptId: exceptId);
    return clash == null
        ? null
        : 'توجد مدينة بنفس الاسم أو باسم مشابه: ${clash.nameAr}';
  }

  Future<void> _add() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CityNameDialog(title: 'إضافة مدينة'),
    );
    if (name == null) return;
    final problem = _nameProblem(name);
    if (problem != null) return setState(() => message = problem);
    try {
      await widget.repository.createCity(City(
        id: '',
        governorateId: widget.governorate.id,
        nameAr: name,
        displayOrder: cities.length + 1,
      ));
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => message =
            cityErrorMessage(error, fallback: 'تعذرت إضافة المدينة.'));
      }
    }
  }

  Future<void> _rename(City city) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          CityNameDialog(title: 'تعديل اسم المدينة', initial: city.nameAr),
    );
    if (name == null || name == city.nameAr) return;
    final problem = _nameProblem(name, exceptId: city.id);
    if (problem != null) return setState(() => message = problem);
    try {
      await widget.repository.updateCity(city.copyWith(nameAr: name));
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => message =
            cityErrorMessage(error, fallback: 'تعذر تعديل اسم المدينة.'));
      }
    }
  }

  Future<void> _setActive(City city, bool active) async {
    if (!active && (activeStores[city.id] ?? 0) > 0) {
      return setState(() => message =
          'لا يمكن إيقاف مدينة لديها محلات نشطة. انقل المحلات أو أوقفها أولاً.');
    }
    try {
      await widget.repository.updateCity(city.copyWith(isActive: active));
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() => message =
            cityErrorMessage(error, fallback: 'تعذر تغيير حالة المدينة.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('مدن ${widget.governorate.nameAr}'),
      content: SizedBox(
        width: 480,
        child: loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(message!,
                          key: const Key('cities-message'),
                          style: TextStyle(color: scheme.error)),
                    ),
                  if (cities.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('لا توجد مدن بعد. أضف أول مدينة.',
                          textAlign: TextAlign.center),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final city in cities)
                            ListTile(
                              key: Key('city-row-${city.id}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(city.nameAr,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                  '${city.isActive ? 'نشطة' : 'غير نشطة'} · '
                                  '${activeStores[city.id] ?? 0} محل نشط'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    key: Key('city-active-${city.id}'),
                                    value: city.isActive,
                                    onChanged: (value) =>
                                        _setActive(city, value),
                                  ),
                                  IconButton(
                                    key: Key('city-rename-${city.id}'),
                                    tooltip: 'تعديل الاسم',
                                    onPressed: () => _rename(city),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق')),
        FilledButton.icon(
          key: const Key('city-add'),
          onPressed: loading ? null : _add,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('إضافة مدينة'),
        ),
      ],
    );
  }
}
