/// 拼豆图纸数据模型。
library;

/// 用量清单条目。
class BomEntry {
  /// 色号。
  final String code;

  /// 该色号的格子数量。
  final int count;

  /// 该色号的颜色（0xRRGGBB），用于列表展示。
  final int color;

  /// 可选：官方产品码 / 颜色名。
  final String? productCode;
  final String? name;

  const BomEntry({
    required this.code,
    required this.count,
    required this.color,
    this.productCode,
    this.name,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'count': count,
        'color': color,
        if (productCode != null) 'productCode': productCode,
        if (name != null) 'name': name,
      };

  factory BomEntry.fromJson(Map<String, dynamic> json) => BomEntry(
        code: json['code'] as String,
        count: json['count'] as int,
        color: json['color'] as int,
        productCode: json['productCode'] as String?,
        name: json['name'] as String?,
      );
}

/// 拼豆图纸：色号网格 + 用量清单。
class Pattern {
  /// 网格宽度（N）。
  final int size;

  /// 网格高度（M）；正方形时为 == size。支持按原图比例的非正方形图纸。
  final int height;

  /// 行优先色号索引矩阵（stride = [size]）；-1 = 透明格。
  final List<int> grid;

  /// 色卡 id（如 "mard_221"）。
  final String paletteId;

  /// 用量清单（按数量降序）。
  final List<BomEntry> bom;

  Pattern({
    required this.size,
    required this.grid,
    required this.paletteId,
    required this.bom,
    int? height,
  }) : height = height ?? size;

  int at(int x, int y) => grid[y * size + x];

  /// 有效格子总数（不含透明格）。
  int get totalBeads => grid.where((i) => i >= 0).length;

  /// 使用的色号数。
  int get colorCount => bom.length;

  Map<String, dynamic> toJson() => {
        'size': size,
        if (height != size) 'height': height,
        'grid': grid,
        'paletteId': paletteId,
        'bom': bom.map((e) => e.toJson()).toList(),
      };

  factory Pattern.fromJson(Map<String, dynamic> json) => Pattern(
        size: json['size'] as int,
        height: json['height'] as int?,
        grid: (json['grid'] as List<dynamic>).cast<int>(),
        paletteId: json['paletteId'] as String,
        bom: (json['bom'] as List<dynamic>)
            .map((e) => BomEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
