import 'package:flutter_test/flutter_test.dart';
import 'package:doutu/models/inventory.dart';
import 'package:doutu/models/pattern.dart';

void main() {
  test('computeMissing 返回缺豆明细', () {
    const bom = [
      BomEntry(code: 'A01', count: 10, color: 0xFFFFFF),
      BomEntry(code: 'H07', count: 5, color: 0x000000),
    ];
    final missing = computeMissing(bom, {'A01': 6, 'H07': 5});
    expect(missing.length, 1);
    expect(missing.first.code, 'A01');
    expect(missing.first.missing, 4);
  });

  test('未录入库存或足够时返回空', () {
    const bom = [BomEntry(code: 'A01', count: 10, color: 0xFFFFFF)];
    expect(computeMissing(bom, null), isEmpty);
    expect(computeMissing(bom, const {}), isEmpty);
    expect(computeMissing(bom, {'A01': 20}), isEmpty);
  });
}
