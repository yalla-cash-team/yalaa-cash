import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

void main() {
  group('DigitalProduct image', () {
    test('image is optional and defaults to null', () {
      const product = DigitalProduct(
        id: 'p1',
        name: 'Gift card',
        costInPoints: 500,
        iconSeed: 1,
      );

      expect(product.imageUrl, isNull);
    });

    test('copyWith keeps the image and the price', () {
      const product = DigitalProduct(
        id: 'p1',
        name: 'Gift card',
        costInPoints: 500,
        iconSeed: 1,
        imageUrl: 'https://example.com/product.png',
      );

      final renamed = product.copyWith(name: 'Gift card 2');

      expect(renamed.imageUrl, 'https://example.com/product.png');
      expect(renamed.costInPoints, 500);
    });
  });
}
