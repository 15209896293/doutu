/// 板型定义：方形板 / 圆形板预设。
library;

/// 板型形状。
enum BoardShape { square, circle }

/// 板型预设。
class BoardPreset {
  final String id;
  final String label;
  final int size;
  final BoardShape shape;

  const BoardPreset({
    required this.id,
    required this.label,
    required this.size,
    this.shape = BoardShape.square,
  });

  /// 预设列表：29 方 / 29 圆 / 52 方 / 81 方。
  /// 29×29 圆形板是拼豆最常用的板型（dev-plan 未覆盖，此处补充）。
  static const presets = <BoardPreset>[
    BoardPreset(id: '29', label: '29×29', size: 29),
    BoardPreset(id: '29c', label: '29 圆形', size: 29, shape: BoardShape.circle),
    BoardPreset(id: '52', label: '52×52', size: 52),
    BoardPreset(id: '81', label: '81×81', size: 81),
    BoardPreset(id: '128', label: '128×128', size: 128),
  ];

  static const minCustomSize = 16;
  static const maxCustomSize = 256;

  /// 圆形板掩码：格子是否属于圆板（中心半径 size/2 的圆）。
  static bool isInsideCircle(int x, int y, int size) {
    final c = (size - 1) / 2.0;
    final dx = x - c;
    final dy = y - c;
    return dx * dx + dy * dy <= c * c + 0.1; // 边界含入
  }
}
