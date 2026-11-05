import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

void main() {
  group('CommissionCalculator', () {
    test('splits commission and converts customer share to points', () {
      final result = CommissionCalculator.calculate(
        invoiceAmountSyp: 100000,
        commissionRate: 10,
        pointValueSyp: 5,
      );

      expect(result.commissionAmountSyp, 10000);
      expect(result.customerShareSyp, 5000);
      expect(result.platformRevenueSyp, 5000);
      expect(result.customerPoints, 1000);
    });

    test('rejects invalid amounts', () {
      expect(
        () => CommissionCalculator.calculate(
          invoiceAmountSyp: 0,
          commissionRate: 5,
          pointValueSyp: 5,
        ),
        throwsArgumentError,
      );
    });

    test('fractional point values award proportionally more points', () {
      final cases = {0.10: 50000, 0.25: 20000, 0.50: 10000};
      for (final entry in cases.entries) {
        final result = CommissionCalculator.calculate(
          invoiceAmountSyp: 100000,
          commissionRate: 10,
          pointValueSyp: entry.key,
        );

        expect(result.customerShareSyp, 5000);
        expect(result.customerPoints, entry.value, reason: '${entry.key}');
      }
    });

    test('rounds customer points down and reports the remainder', () {
      // Customer share is 5 SYP.
      final atPoint4 = CommissionCalculator.calculate(
        invoiceAmountSyp: 100,
        commissionRate: 10,
        pointValueSyp: 0.4,
      );
      expect(atPoint4.customerPoints, 12); // 12.5 -> 12
      expect(atPoint4.customerRemainderScaled, 2000); // 0.2 SYP

      final atPoint3 = CommissionCalculator.calculate(
        invoiceAmountSyp: 100,
        commissionRate: 10,
        pointValueSyp: 0.3,
      );
      expect(atPoint3.customerPoints, 16); // 16.67 -> 16
      expect(atPoint3.customerRemainderScaled, 2000); // 0.2 SYP
    });

    test('carries remainders forward so repeated rewards lose no value', () {
      // Five 1-SYP rewards at 0.30 SYP/point: 5 SYP is worth 16 points.
      var carried = 0;
      var totalPoints = 0;
      for (var i = 0; i < 5; i++) {
        final result = CommissionCalculator.calculate(
          invoiceAmountSyp: 20,
          commissionRate: 10,
          pointValueSyp: 0.3,
          carriedRemainderScaled: carried,
        );
        totalPoints += result.customerPoints;
        carried = result.customerRemainderScaled;
      }

      expect(totalPoints, 16);
      expect(carried, 2000);
    });

    test('whole-SYP check guards cash redemptions', () {
      expect(CommissionCalculator.isWholeCashValue(10, 0.1), isTrue);
      expect(CommissionCalculator.isWholeCashValue(16, 0.3), isFalse);
      expect(CommissionCalculator.isWholeCashValue(20, 0.25), isTrue);
    });

    test('awarded points never exceed the customer share', () {
      const values = [0.1, 0.25, 0.3, 0.4, 0.5, 0.7, 3.0, 5.0];
      const invoices = [1, 7, 13, 99, 101, 1000, 12345];

      for (final value in values) {
        for (final invoice in invoices) {
          final result = CommissionCalculator.calculate(
            invoiceAmountSyp: invoice,
            commissionRate: 10,
            pointValueSyp: value,
          );

          expect(result.customerRemainderScaled, greaterThanOrEqualTo(0));
          expect(
            result.customerRemainderScaled,
            lessThan((value * 10000).round()),
          );
        }
      }
    });

    test('computes exact points for 0.1 SYP per point', () {
      // Share 3 SYP at 0.1 SYP/point must be exactly 30 points.
      final result = CommissionCalculator.calculate(
        invoiceAmountSyp: 60,
        commissionRate: 10,
        pointValueSyp: 0.1,
      );

      expect(result.customerShareSyp, 3);
      expect(result.customerPoints, 30);
    });

    test('converts points back to whole SYP rounding down', () {
      expect(CommissionCalculator.cashValueFor(17, 0.3), 5); // 5.1 -> 5
      expect(CommissionCalculator.cashValueFor(16, 0.3), 4); // 4.8 -> 4
      expect(CommissionCalculator.cashValueFor(1, 0.5), 0); // 0.5 -> 0
      expect(CommissionCalculator.cashValueFor(20, 0.25), 5);
      expect(CommissionCalculator.cashValueFor(1000, 5), 5000);
    });

    test('rejects point values with more than four decimals or non-positive',
        () {
      for (final value in [0.0, -0.5, 0.00001, double.nan]) {
        expect(
          () => CommissionCalculator.calculate(
            invoiceAmountSyp: 100000,
            commissionRate: 10,
            pointValueSyp: value,
          ),
          throwsArgumentError,
          reason: '$value',
        );
      }
    });
  });
}
