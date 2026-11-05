import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

void main() {
  group('ShareRewardResult', () {
    test('only the granted status counts as a reward', () {
      const granted = ShareRewardResult(
        status: 'granted',
        pointsAwarded: 50,
        pointsBalance: 120,
      );
      const repeated = ShareRewardResult(
        status: 'already_claimed',
        pointsAwarded: 0,
        pointsBalance: 70,
      );
      const disabled = ShareRewardResult(
        status: 'disabled',
        pointsAwarded: 0,
        pointsBalance: 70,
      );

      expect(granted.granted, isTrue);
      expect(repeated.granted, isFalse);
      expect(disabled.granted, isFalse);
    });
  });
}
