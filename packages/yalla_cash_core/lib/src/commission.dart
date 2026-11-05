class CommissionResult {
  const CommissionResult({
    required this.invoiceAmountSyp,
    required this.commissionRate,
    required this.commissionAmountSyp,
    required this.platformRevenueSyp,
    required this.customerShareSyp,
    required this.customerPoints,
    required this.pointValueSyp,
    required this.customerRemainderScaled,
  });

  final int invoiceAmountSyp;
  final double commissionRate;
  final int commissionAmountSyp;
  final int platformRevenueSyp;
  final int customerShareSyp;
  final int customerPoints;
  final double pointValueSyp;

  /// Earned value not yet covered by whole points, in 1/10000 SYP.
  /// Carry it into the next reward for the same customer.
  final int customerRemainderScaled;
}

class CommissionCalculator {
  const CommissionCalculator._();

  /// Point values are stored with 4 decimals, matching the backend.
  static const int _valueScale = 10000;

  static CommissionResult calculate({
    required int invoiceAmountSyp,
    required double commissionRate,
    required double pointValueSyp,
    int carriedRemainderScaled = 0,
  }) {
    if (invoiceAmountSyp <= 0) {
      throw ArgumentError.value(invoiceAmountSyp, 'invoiceAmountSyp');
    }
    if (commissionRate < 0 || commissionRate > 100) {
      throw ArgumentError.value(commissionRate, 'commissionRate');
    }
    final scaledValue = _scaledPointValue(pointValueSyp);

    final commission = (invoiceAmountSyp * commissionRate / 100).round();
    final customerShare = (commission / 2).round();
    final platformShare = commission - customerShare;
    // Points are rounded down so awarded points never exceed the reward, and
    // the leftover is carried forward. Integer math avoids float drift.
    final earnedScaled = customerShare * _valueScale + carriedRemainderScaled;
    final points = earnedScaled ~/ scaledValue;
    final remainderScaled = earnedScaled - points * scaledValue;

    return CommissionResult(
      invoiceAmountSyp: invoiceAmountSyp,
      commissionRate: commissionRate,
      commissionAmountSyp: commission,
      platformRevenueSyp: platformShare,
      customerShareSyp: customerShare,
      customerPoints: points,
      pointValueSyp: pointValueSyp,
      customerRemainderScaled: remainderScaled,
    );
  }

  /// True when [points] convert to an exact whole-SYP amount.
  static bool isWholeCashValue(int points, double pointValueSyp) =>
      (points * _scaledPointValue(pointValueSyp)) % _valueScale == 0;

  /// SYP value of [points], rounded down to a whole SYP amount.
  static int cashValueFor(int points, double pointValueSyp) {
    final scaledValue = _scaledPointValue(pointValueSyp);
    return (points * scaledValue) ~/ _valueScale;
  }

  static int _scaledPointValue(double pointValueSyp) {
    if (!pointValueSyp.isFinite || pointValueSyp <= 0) {
      throw ArgumentError.value(pointValueSyp, 'pointValueSyp');
    }
    final scaled = (pointValueSyp * _valueScale).round();
    if ((pointValueSyp * _valueScale - scaled).abs() > 1e-6 || scaled <= 0) {
      throw ArgumentError.value(
        pointValueSyp,
        'pointValueSyp',
        'must have at most 4 decimal places',
      );
    }
    return scaled;
  }
}
