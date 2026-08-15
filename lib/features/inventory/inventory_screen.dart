/// 库存管理页：按色卡录入已有豆子颗数（套盒匹配，v0.4）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/palette.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _paletteId = 'mard_221';
  bool _onlyOwned = false;

  @override
  Widget build(BuildContext context) {
    final palettes = ref.watch(palettesProvider);
    final inventory = ref.watch(inventoryProvider);
    final owned = inventory.valueOrNull?[_paletteId] ?? const <String, int>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('📦 我的豆子库存'),
        actions: [
          if (owned.isNotEmpty)
            TextButton(
              onPressed: () =>
                  ref.read(inventoryProvider.notifier).clearPalette(_paletteId),
              child: const Text('清零当前色卡'),
            ),
        ],
      ),
      body: SafeArea(
        child: palettes.when(
          loading: () => const Center(child: BeadLoader()),
          error: (e, _) => CuteEmptyState(
            emoji: '😵',
            title: '色卡加载失败',
            subtitle: e.toString(),
          ),
          data: (map) {
            final palette = map[_paletteId] ?? map.values.first;
            final shown = _onlyOwned
                ? palette.entries
                    .where((e) => (owned[e.code] ?? 0) > 0)
                    .toList()
                : palette.entries;
            return Column(
              children: [
                _paletteBar(map, palette),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  dense: true,
                  title: const Text('只看已录入', style: TextStyle(fontSize: 14)),
                  value: _onlyOwned,
                  onChanged: (v) => setState(() => _onlyOwned = v),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: shown.isEmpty
                      ? const CuteEmptyState(
                          emoji: '🫙',
                          title: '还没有录入',
                          subtitle: '点右侧 + 录入你已有的豆子颗数',
                        )
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (context, i) =>
                              _row(palette, shown[i], owned),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _paletteBar(Map<String, Palette> map, Palette current) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final id in map.keys)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(map[id]!.displayName),
                selected: id == _paletteId,
                showCheckmark: false,
                onSelected: (_) => setState(() => _paletteId = id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(Palette palette, PaletteEntry e, Map<String, int> owned) {
    final count = owned[e.code] ?? 0;
    final bg = Color(0xFF000000 | (e.r << 16) | (e.g << 8) | e.b);
    return ListTile(
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
      ),
      title: Text(e.code, style: kMonoTextStyle.copyWith(fontSize: 14)),
      subtitle: e.name == null
          ? null
          : Text(e.name!,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded),
            color: AppColors.textSecondary,
            onPressed: count > 0
                ? () => _set(palette.id, e.code, count - 1)
                : null,
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: kMonoTextStyle.copyWith(fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: AppColors.primary,
            onPressed: () => _set(palette.id, e.code, count + 1),
          ),
        ],
      ),
    );
  }

  void _set(String paletteId, String code, int count) {
    ref.read(inventoryProvider.notifier).setCount(paletteId, code, count);
  }
}
