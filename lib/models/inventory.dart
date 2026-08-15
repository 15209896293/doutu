/// 库存/套盒匹配相关模型（v0.4）。
library;

import 'pattern.dart';

/// 缺少的豆色。
class MissingBead {
  final String code;
  final String? name;
  final int color; // 0xRRGGBB
  final int missing; // 还缺颗数

  const MissingBead(this.code, this.name, this.color, this.missing);
}

/// 对比用量清单与用户库存，返回缺豆明细（需数 > 已有数）。
///
/// [owned]：`{ 色号: 已有颗数 }`；为 null 或空时表示未录入库存，返回空。
List<MissingBead> computeMissing(List<BomEntry> bom, Map<String, int>? owned) {
  if (owned == null || owned.isEmpty) return const [];
  final out = <MissingBead>[];
  for (final e in bom) {
    final have = owned[e.code] ?? 0;
    if (have < e.count) {
      out.add(MissingBead(e.code, e.name, e.color, e.count - have));
    }
  }
  return out;
}
