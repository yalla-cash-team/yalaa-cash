import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

void main() {
  // The in-memory demo has no settlement ledger, so these calls must never
  // report a settlement or move money.
  test('demo monthly settlement makes no changes', () async {
    final repository = InMemoryYallaCashRepository(YallaCashStore.demo());

    final preview = await repository.previewMonthlySettlement('2026-09');
    expect(preview.openMerchantCount, 0);
    expect(preview.totalCommissionSyp, 0);

    final run = await repository.runMonthlySettlement('2026-09');
    expect(run.settledCount, 0);
    expect(run.failedCount, 0);
    expect(run.merchants, isEmpty);

    expect(await repository.listMonthlySettlementHistory(), isEmpty);
  });
}
