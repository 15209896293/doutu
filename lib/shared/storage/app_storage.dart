/// 跨端存储抽象：io（文件系统）/ web（localStorage）双实现。
///
/// 各 Store 只依赖本接口，不直接使用 dart:io，从而支持浏览器编译。
library;

/// 键值存储抽象。
abstract class AppStorage {
  /// 读取文本；不存在或失败返回 null。
  Future<String?> readText(String path);

  /// 写入文本。
  Future<void> writeText(String path, String content);

  /// 读取字节；不存在或失败返回 null。
  Future<List<int>?> readBytes(String path);

  /// 写入字节。
  Future<void> writeBytes(String path, List<int> bytes);

  /// 是否存在。
  Future<bool> exists(String path);

  /// 删除。
  Future<void> delete(String path);

  /// 列出路径以 [prefix] 开头的条目（返回文件名/键名）。
  Future<List<String>> list(String prefix);
}
