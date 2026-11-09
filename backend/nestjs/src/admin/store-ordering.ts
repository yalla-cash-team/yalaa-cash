/**
 * Pure helpers for a city's manual store order. Positions are 1-based and
 * only the ACTIVE stores of one city take part in the sequence.
 */

/** Clamps a requested 1-based position into 1..(count + 1). */
export function clampPosition(requested: number, siblingCount: number): number {
  if (!Number.isFinite(requested)) return siblingCount + 1;
  return Math.min(Math.max(Math.trunc(requested), 1), siblingCount + 1);
}

/**
 * Inserts [movingId] into [siblingIds] (the other active stores, already in
 * display order) at [requested] (1-based). No request = end of the list.
 * Returns the full new order; position = index + 1.
 */
export function insertAtPosition(
  siblingIds: string[],
  movingId: string,
  requested?: number,
): string[] {
  const others = siblingIds.filter((id) => id !== movingId);
  const position =
    requested === undefined
      ? others.length + 1
      : clampPosition(requested, others.length);
  return [...others.slice(0, position - 1), movingId, ...others.slice(position - 1)];
}

/** Rows whose stored position differs from their index in [orderedIds]. */
export function positionChanges(
  orderedIds: string[],
  current: Map<string, number>,
): { id: string; displayOrder: number }[] {
  const changes: { id: string; displayOrder: number }[] = [];
  orderedIds.forEach((id, index) => {
    if (current.get(id) !== index + 1) {
      changes.push({ id, displayOrder: index + 1 });
    }
  });
  return changes;
}
