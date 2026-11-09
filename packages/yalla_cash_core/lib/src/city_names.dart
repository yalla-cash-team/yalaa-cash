/// City-name comparison shared by the admin UI and the in-memory repository.
/// Mirrors backend/nestjs/src/admin/city-names.ts: names that differ only in
/// case, spacing, diacritics or the common Arabic letter variants are the
/// same city, so a typo-like variant can never become a second city.
library;

String normalizeCityName(String name) =>
    name.replaceAll(RegExp(r'\s+'), ' ').trim();

String cityNameKey(String name) => normalizeCityName(name)
    .toLowerCase()
    .replaceAll(RegExp('[ً-ٰٟـ]'), '') // tashkeel, tatweel
    .replaceAll(RegExp('[أإآٱ]'), 'ا') // alef forms
    .replaceAll('ى', 'ي') // alef maqsura -> yaa
    .replaceAll('ة', 'ه'); // taa marbuta -> haa

/// The city of [cities] whose name collides with [name] (same governorate),
/// ignoring [exceptId]; null when [name] is free.
T? findCityNameClash<T>(
  Iterable<T> cities,
  String name, {
  required String Function(T) nameOf,
  required String Function(T) idOf,
  String? exceptId,
}) {
  final key = cityNameKey(name);
  for (final city in cities) {
    if (idOf(city) != exceptId && cityNameKey(nameOf(city)) == key) {
      return city;
    }
  }
  return null;
}
