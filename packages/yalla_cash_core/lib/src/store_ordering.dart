/// Manual store ordering inside one city. Mirrors the backend rules
/// (backend/nestjs/src/admin/store-ordering.ts): positions are 1-based and only
/// ACTIVE stores of the city take part.
library;

/// Inserts [movingId] among [siblingIds] (the other active stores, already in
/// display order) at [requested] (1-based). A null or non-positive request
/// means "last"; too-large values are clamped to last.
List<String> insertAtPosition(
  List<String> siblingIds,
  String movingId, [
  int? requested,
]) {
  final others = siblingIds.where((id) => id != movingId).toList();
  final position = (requested == null || requested < 1)
      ? others.length + 1
      : requested.clamp(1, others.length + 1);
  return [
    ...others.take(position - 1),
    movingId,
    ...others.skip(position - 1),
  ];
}

/// Validates the admin's Display Order text. Empty = null (put last).
/// Returns an Arabic error message, or null when valid.
String? validateDisplayOrder(String? text) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 1 || parsed > 10000) {
    return 'أدخل رقماً صحيحاً من 1 إلى 10000';
  }
  return null;
}
